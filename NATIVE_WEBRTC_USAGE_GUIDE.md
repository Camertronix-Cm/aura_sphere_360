# Native WebRTC Usage Guide — aura_sphere_360 v2.0.0

## Overview

Version 2.0.0 introduces **native pixel extraction** for WebRTC streams. Instead of using `RepaintBoundary.toImage()` (which blocks the iOS main thread with a GPU→CPU readback), raw BGRA frames are extracted directly on WebRTC's internal render thread and delivered to Dart via `EventChannel`.

This guide shows how to integrate the native path into your app.

---

## What You Need

```yaml
# pubspec.yaml
dependencies:
  aura_sphere_360: ^2.0.0
  flutter_webrtc: ^0.11.7
```

That's it — `webrtc_pixel_stream` (the companion plugin that does the actual extraction) is pulled in automatically as a transitive dependency. No forks. No `dependency_overrides`.

---

## Migration from v1.x

### Before (v1.x — legacy path)

```dart
AuraSphere(
  webrtcRenderer: _renderer,
  sensorControl: SensorControl.orientation,
)
```

This uses `RepaintBoundary.toImage()` internally — slow on iOS, blocks the main thread.

### After (v2.0.0 — native path)

```dart
AuraSphere(
  webrtcRenderer: _renderer,
  webrtcTrackId: _videoTrackId,  // NEW — just the track ID
  sensorControl: SensorControl.orientation,
)
```

The only change is passing **one additional string**: the video track ID. When it's present and `useNativeExtraction` is `true` (the default), the plugin automatically uses the native path.

> **Note:** `webrtcPeerConnectionId` is also accepted as an optional optimization hint, but you do **not** need it. The native layer automatically searches all peer connections to find the track.

---

## Step-by-Step Integration

### 1. Add state fields

```dart
class _MyPlayerState extends State<MyPlayer> {
  RTCVideoRenderer? _renderer;
  RTCPeerConnection? _peerConnection;

  // ↓ Add this field
  String? _videoTrackId;
  
  bool _streamReady = false;
  // ... rest of your state
}
```

### 2. Capture the video track ID in onTrack

```dart
_peerConnection!.onTrack = (event) {
  if (event.track.kind == 'video' && event.streams.isNotEmpty) {
    if (!mounted) return;
    _renderer!.srcObject = event.streams[0];

    // ↓ Add this line
    _videoTrackId = event.track.id;

    setState(() => _streamReady = true);
  }
};
```

### 3. Pass the track ID to AuraSphere

```dart
Widget build(BuildContext context) {
  if (_renderer == null) return const SizedBox.shrink();

  return AuraSphere(
    key: const ValueKey('live_sphere'),
    webrtcRenderer: _renderer,
    webrtcTrackId: _videoTrackId,  // ← Pass track ID
    sensorControl: SensorControl.orientation,
    animSpeed: 0.5,
  );
}
```

---

## How the Routing Works

| `webrtcRenderer` | `webrtcTrackId` | `useNativeExtraction` | Path Used |
|---|---|---|---|
| ✅ set | ✅ set | `true` (default) | **Native** — `webrtc_pixel_stream` EventChannel |
| ✅ set | ❌ null | any | **Legacy** — `RepaintBoundary.toImage()` |
| ✅ set | ✅ set | `false` | **Legacy** — `RepaintBoundary.toImage()` |

The native path is only activated when **all three conditions** are met:
1. `webrtcRenderer` is set
2. `webrtcTrackId` is provided
3. `useNativeExtraction` is `true` (the default)

If the native path fails (e.g., track not found), a debug message is printed and the sphere simply won't receive frames — it won't crash.

---

## Forcing the Legacy Path

If you ever need to fall back to the old behavior:

```dart
AuraSphere(
  webrtcRenderer: _renderer,
  useNativeExtraction: false,  // ← forces RepaintBoundary path
  sensorControl: SensorControl.orientation,
)
```

---

## Complete Example

Here is a minimal complete example matching the `Aura360Player` widget pattern:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:aura_sphere_360/aura_sphere_360.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class Aura360Player extends StatefulWidget {
  final String signalingUrl;
  const Aura360Player({super.key, required this.signalingUrl});

  @override
  State<Aura360Player> createState() => _Aura360PlayerState();
}

class _Aura360PlayerState extends State<Aura360Player> {
  RTCVideoRenderer? _renderer;
  RTCPeerConnection? _peerConnection;
  WebSocketChannel? _signalingChannel;
  StreamSubscription? _signalingSubscription;

  String? _videoTrackId;
  bool _streamReady = false;

  final List<RTCIceCandidate> _pendingIceCandidates = [];
  bool _remoteDescriptionSet = false;

  @override
  void initState() {
    super.initState();
    _startWebRtc();
  }

  Future<void> _startWebRtc() async {
    _renderer = RTCVideoRenderer();
    await _renderer!.initialize();
    if (mounted) setState(() {});

    _signalingChannel = WebSocketChannel.connect(
      Uri.parse(widget.signalingUrl),
    );
    _signalingSubscription = _signalingChannel!.stream.listen(
      _handleSignalingMessage,
      onError: (e) => debugPrint('Signaling error: $e'),
      onDone: () => debugPrint('Signaling closed'),
    );
    _sendMessage({'type': 'request_offer'});
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _sendMessage({
          'type': 'ice',
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      }
    };

    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        if (!mounted) return;
        _renderer!.srcObject = event.streams[0];

        // ✅ Capture the video track ID for native extraction
        _videoTrackId = event.track.id;

        setState(() => _streamReady = true);
      }
    };
  }

  void _handleSignalingMessage(dynamic message) async {
    final data = jsonDecode(message as String) as Map<String, dynamic>;
    switch (data['type']) {
      case 'offer':
        await _createPeerConnection();
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'] as String, 'offer'),
        );
        _remoteDescriptionSet = true;
        for (final c in _pendingIceCandidates) {
          await _peerConnection!.addCandidate(c);
        }
        _pendingIceCandidates.clear();
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _sendMessage({'type': 'answer', 'sdp': answer.sdp});
      case 'ice':
        final c = data['candidate'] as Map<String, dynamic>;
        final candidate = RTCIceCandidate(
          c['candidate'] as String,
          (c['sdpMid'] as String?) ?? '0',
          (c['sdpMLineIndex'] as int?) ?? 0,
        );
        if (_remoteDescriptionSet) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _pendingIceCandidates.add(candidate);
        }
    }
  }

  void _sendMessage(Map<String, dynamic> msg) {
    _signalingChannel?.sink.add(jsonEncode(msg));
  }

  @override
  void dispose() {
    _signalingSubscription?.cancel();
    _signalingChannel?.sink.close();
    _peerConnection?.close();
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_renderer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return AuraSphere(
      key: const ValueKey('live_sphere'),
      webrtcRenderer: _renderer,
      webrtcTrackId: _videoTrackId,  // ✅ Native extraction — track ID is all you need
      sensorControl: SensorControl.orientation,
      animSpeed: 0.5,
    );
  }
}
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Black sphere, no frames | `webrtcTrackId` is null when AuraSphere builds | Ensure `setState` is called after capturing the track ID in `onTrack` |
| Debug log: `MissingPluginException` | `webrtc_pixel_stream` not registered | Make sure `aura_sphere_360: ^2.0.0` is in your pubspec and you ran `pod install` |
| Debug log: `TRACK_NOT_FOUND` | Track ID is wrong or track not yet added | Verify `event.track.id` is non-null and `setState` is called after `onTrack` fires |
| Debug log: `NOT_READY` | `flutter_webrtc` plugin not initialized yet | Ensure the WebRTC peer connection is created before AuraSphere tries to use the track |
| Works on Android but not iOS | `webrtc_pixel_stream` only supports iOS currently | Set `useNativeExtraction: false` for Android, or wait for Android support |
