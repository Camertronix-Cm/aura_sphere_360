# WebRTC Setup Guide

## Overview

This guide helps you set up WebRTC support in your Flutter app using Aura Sphere 360.

## Prerequisites

- Flutter SDK 3.3.0 or higher
- iOS 13.0+ or Android 5.0+
- Camera and microphone permissions

## Installation

### 1. Add Dependencies

The flutter_webrtc dependency is already included in aura_sphere_360, but you need to ensure native code is properly linked.

```yaml
dependencies:
  aura_sphere_360: ^1.1.0
```

### 2. iOS Setup

#### Install CocoaPods Dependencies

```bash
cd ios
pod install
cd ..
```

#### Add Permissions to Info.plist

Add these keys to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for WebRTC 360° video streaming</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for WebRTC audio streaming</string>
```

#### Minimum iOS Version

Ensure your `ios/Podfile` has iOS 13.0 or higher:

```ruby
platform :ios, '13.0'
```

### 3. Android Setup

#### Add Permissions to AndroidManifest.xml

Add these permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- WebRTC permissions -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    
    <uses-feature android:name="android.hardware.camera" />
    <uses-feature android:name="android.hardware.camera.autofocus" />
    
    <application ...>
        ...
    </application>
</manifest>
```

#### Minimum Android SDK

Ensure your `android/app/build.gradle` has minSdkVersion 21 or higher:

```gradle
android {
    defaultConfig {
        minSdkVersion 21
        ...
    }
}
```

### 4. Clean and Rebuild

After adding permissions, clean and rebuild your app:

```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run
```

## Common Issues

### Issue 1: MissingPluginException

**Error:**
```
MissingPluginException(No implementation found for method initialize on channel FlutterWebRTC.Method)
```

**Solution:**
1. Run `flutter clean`
2. Run `flutter pub get`
3. For iOS: `cd ios && pod install && cd ..`
4. Rebuild the app completely (stop and restart)

### Issue 2: Camera Permission Denied

**Error:**
```
Camera permission denied
```

**Solution:**
1. Check that Info.plist (iOS) or AndroidManifest.xml (Android) has camera permissions
2. Uninstall and reinstall the app to trigger permission prompt
3. Check device settings to ensure camera permission is granted

### Issue 3: Black Screen on WebRTC

**Possible Causes:**
- Stream not initialized
- Renderer not initialized
- Widget not in tree

**Solution:**
```dart
// Ensure proper initialization order
final renderer = RTCVideoRenderer();
await renderer.initialize();  // Wait for this!

final stream = await navigator.mediaDevices.getUserMedia({
  'video': true,
  'audio': false,
});

renderer.srcObject = stream;  // Set stream after initialization
setState(() {});  // Trigger rebuild
```

### Issue 4: Hot Reload Issues

WebRTC doesn't always work well with hot reload. If you encounter issues:

1. Stop the app completely
2. Run `flutter run` again
3. Avoid hot reload when testing WebRTC features

## Usage Example

### Basic Local Camera Stream

```dart
import 'package:aura_sphere_360/aura_sphere_360.dart';

class WebRTCPanoramaScreen extends StatefulWidget {
  @override
  State<WebRTCPanoramaScreen> createState() => _WebRTCPanoramaScreenState();
}

class _WebRTCPanoramaScreenState extends State<WebRTCPanoramaScreen> {
  RTCVideoRenderer? _renderer;
  MediaStream? _localStream;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeWebRTC();
  }

  Future<void> _initializeWebRTC() async {
    try {
      // Initialize renderer
      _renderer = RTCVideoRenderer();
      await _renderer!.initialize();

      // Get local camera stream
      final mediaConstraints = {
        'audio': false,
        'video': {
          'facingMode': 'environment',  // Back camera
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
        }
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _renderer!.srcObject = _localStream;

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Error initializing WebRTC: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Center(child: CircularProgressIndicator());
    }

    return PanoramaViewer(
      webrtcRenderer: _renderer,
      sensorControl: SensorControl.orientation,
    );
  }

  @override
  void dispose() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _renderer?.dispose();
    super.dispose();
  }
}
```

### Remote WebRTC Peer Connection

For connecting to a remote WebRTC peer, you'll need:

1. Signaling server (WebSocket, Socket.IO, etc.)
2. STUN/TURN servers for NAT traversal
3. Peer connection setup

Example:

```dart
Future<void> _connectToRemotePeer() async {
  // Initialize renderer
  _renderer = RTCVideoRenderer();
  await _renderer!.initialize();

  // Create peer connection
  final configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      // Add TURN servers for production
    ]
  };

  _peerConnection = await createPeerConnection(configuration);

  // Handle remote stream
  _peerConnection!.onTrack = (RTCTrackEvent event) {
    if (event.track.kind == 'video') {
      setState(() {
        _renderer!.srcObject = event.streams[0];
      });
    }
  };

  // Connect via signaling server
  // (Implementation depends on your signaling protocol)
}
```

### Real-World Integration: 360° Camera Stream

Example of connecting to a 360° camera's WebRTC stream:

```dart
import 'package:aura_sphere_360/aura_sphere_360.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

class Camera360StreamScreen extends StatefulWidget {
  final String cameraId;
  final String signalingServerUrl;
  
  const Camera360StreamScreen({
    required this.cameraId,
    required this.signalingServerUrl,
  });

  @override
  State<Camera360StreamScreen> createState() => _Camera360StreamScreenState();
}

class _Camera360StreamScreenState extends State<Camera360StreamScreen> {
  RTCVideoRenderer? _renderer;
  RTCPeerConnection? _peerConnection;
  WebSocketChannel? _signaling;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToCamera();
  }

  Future<void> _connectToCamera() async {
    try {
      // 1. Initialize renderer
      _renderer = RTCVideoRenderer();
      await _renderer!.initialize();

      // 2. Connect to signaling server
      _signaling = WebSocketChannel.connect(
        Uri.parse(widget.signalingServerUrl),
      );

      // 3. Create peer connection
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          // Add your TURN servers here for production
        ],
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(config);

      // 4. Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _signaling!.sink.add(jsonEncode({
          'type': 'ice-candidate',
          'candidate': candidate.toMap(),
          'cameraId': widget.cameraId,
        }));
      };

      // 5. Handle remote stream (THIS IS THE KEY PART!)
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.track.kind == 'video') {
          print('Received video track from camera');
          setState(() {
            // The stream resolution is determined by the camera
            // Could be 1920x1080, 4K, or any resolution the camera sends
            _renderer!.srcObject = event.streams[0];
            _isConnected = true;
          });
        }
      };

      // 6. Listen for signaling messages
      _signaling!.stream.listen((message) {
        final data = jsonDecode(message);
        _handleSignalingMessage(data);
      });

      // 7. Send offer to camera
      _sendOffer();

    } catch (e) {
      print('Error connecting to camera: $e');
    }
  }

  Future<void> _sendOffer() async {
    // Create offer
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // Send to signaling server
    _signaling!.sink.add(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
      'cameraId': widget.cameraId,
    }));
  }

  void _handleSignalingMessage(Map<String, dynamic> data) async {
    switch (data['type']) {
      case 'answer':
        // Received answer from camera
        final answer = RTCSessionDescription(data['sdp'], 'answer');
        await _peerConnection!.setRemoteDescription(answer);
        break;

      case 'ice-candidate':
        // Received ICE candidate from camera
        final candidate = RTCIceCandidate(
          data['candidate']['candidate'],
          data['candidate']['sdpMid'],
          data['candidate']['sdpMLineIndex'],
        );
        await _peerConnection!.addCandidate(candidate);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to 360° camera...'),
            ],
          ),
        ),
      );
    }

    // Display the camera stream in 360° panorama
    return Scaffold(
      body: PanoramaViewer(
        webrtcRenderer: _renderer,
        sensorControl: SensorControl.orientation,
        interactive: true,
      ),
    );
  }

  @override
  void dispose() {
    _peerConnection?.close();
    _renderer?.dispose();
    _signaling?.sink.close();
    super.dispose();
  }
}
```

### Key Points for Real WebRTC Integration

1. **Resolution is Automatic**: The panorama viewer automatically detects and uses the incoming stream's resolution
   - No need to specify dimensions
   - Works with any resolution (720p, 1080p, 4K, 8K, etc.)

2. **Network Considerations**:
   - Use TURN servers for NAT traversal in production
   - WebRTC will adapt quality based on network conditions
   - Monitor connection quality and handle reconnections

3. **Signaling Server**: You need a signaling mechanism to exchange:
   - SDP offers/answers
   - ICE candidates
   - Connection state

4. **Camera-Specific Integration**: Your 360° camera should:
   - Act as a WebRTC peer
   - Stream equirectangular 360° video
   - Support standard WebRTC protocols

### Example: Aura360 Camera Integration

```dart
// Assuming your Aura360 camera has a WebRTC endpoint
class Aura360CameraViewer extends StatefulWidget {
  final String cameraIp;
  
  @override
  State<Aura360CameraViewer> createState() => _Aura360CameraViewerState();
}

class _Aura360CameraViewerState extends State<Aura360CameraViewer> {
  RTCVideoRenderer? _renderer;
  
  @override
  void initState() {
    super.initState();
    _connectToAura360Camera();
  }
  
  Future<void> _connectToAura360Camera() async {
    _renderer = RTCVideoRenderer();
    await _renderer!.initialize();
    
    // Your camera-specific connection logic here
    // This depends on your camera's WebRTC implementation
    
    setState(() {});
  }
  
  @override
  Widget build(BuildContext context) {
    return PanoramaViewer(
      webrtcRenderer: _renderer,
      sensorControl: SensorControl.orientation,
    );
  }
  
  @override
  void dispose() {
    _renderer?.dispose();
    super.dispose();
  }
}
```

## Performance Tips

1. **Resolution**: Use appropriate video resolution
   - 1920x1080 for high quality
   - 1280x720 for better performance
   - 640x480 for low-end devices

2. **Frame Rate**: WebRTC typically runs at 30 FPS, which is perfect for 360° viewing

3. **Network**: For remote streams, ensure good network connectivity
   - Use TURN servers for NAT traversal
   - Implement quality adaptation based on network conditions

4. **Battery**: Live streaming is battery-intensive
   - Warn users about battery usage
   - Provide option to reduce quality

## Testing

### Test on Real Device

WebRTC requires real device testing:
- iOS Simulator doesn't support camera
- Android Emulator has limited camera support

### Test Scenarios

1. ✅ Local camera stream
2. ✅ Remote peer connection
3. ✅ Connection loss and recovery
4. ✅ Permission denial handling
5. ✅ Background/foreground transitions

## Resources

- [flutter_webrtc Documentation](https://pub.dev/packages/flutter_webrtc)
- [WebRTC API](https://webrtc.org/)
- [Aura Sphere 360 Examples](https://github.com/Camertronix-Cm/aura_sphere_360/tree/main/example)

## Support

If you encounter issues:

1. Check this guide first
2. Review the example app code
3. Check flutter_webrtc documentation
4. Open an issue on GitHub with:
   - Flutter version
   - Platform (iOS/Android)
   - Error messages
   - Steps to reproduce

## Next Steps

After setting up WebRTC:

1. Test with local camera stream
2. Implement remote peer connection
3. Add connection state UI
4. Handle errors gracefully
5. Optimize for your use case

Happy streaming! 🎥
