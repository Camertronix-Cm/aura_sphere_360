import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'texture_provider.dart';
import 'native_frame_decoder.dart';

/// Native WebRTC texture provider that receives raw pixel data from a
/// flutter_webrtc fork via EventChannel.
///
/// This replaces [WebRTCTextureProvider] entirely. No hidden RTCVideoView widget,
/// no RepaintBoundary, no Timer.periodic — frames arrive via EventChannel from
/// native code running on WebRTC's internal render thread.
///
/// Uses the `webrtc_pixel_stream` companion plugin which attaches a secondary
/// RTCVideoRenderer to any video track via the existing flutter_webrtc
/// singleton — no fork required.
///
/// Example:
/// ```dart
/// final renderer = RTCVideoRenderer();
/// await renderer.initialize();
/// renderer.srcObject = stream;
///
/// final provider = NativeWebRTCTextureProvider(
///   renderer,
///   trackId: videoTrack.id!,
///   peerConnectionId: pc.peerConnectionId,
/// );
/// await provider.initialize();
/// ```
class NativeWebRTCTextureProvider extends PanoramaTextureProvider {
  // Method channel for the webrtc_pixel_stream companion plugin
  static const MethodChannel _pixelStreamMethod =
      MethodChannel('webrtc_pixel_stream/control');

  /// The RTCVideoRenderer associated with this stream.
  /// Retained for lifecycle management (dispose, etc.).
  final RTCVideoRenderer renderer;

  /// The MediaStreamTrack.id of the video track to stream pixels from.
  final String trackId;

  /// The peer connection ID, needed for remote track lookup.
  /// Pass null for local tracks (e.g., local camera demo).
  final String? peerConnectionId;

  EventChannel? _eventChannel;
  StreamSubscription? _sub;
  ui.Image? _currentFrame;
  bool _ready = false;
  bool _decoding = false;
  Map<dynamic, dynamic>? _pendingEvent;

  NativeWebRTCTextureProvider(
    this.renderer, {
    required this.trackId,
    this.peerConnectionId,
  });

  @override
  PanoramaSourceType get sourceType => PanoramaSourceType.webrtc;

  @override
  bool get isReady => _ready;

  @override
  Future<void> initialize() async {
    debugPrint(
        '[NativeWebRTCTextureProvider] Initializing for track: $trackId');

    try {
      // Ask the webrtc_pixel_stream companion plugin to attach a streaming
      // renderer to this track. It uses FlutterWebRTCPlugin.sharedSingleton
      // internally to look up the track — no fork needed.
      final result = await _pixelStreamMethod
          .invokeMapMethod<String, dynamic>('createPixelStream', {
        'trackId': trackId,
        'peerConnectionId': peerConnectionId,
      });
      final String? channelName = result?['channelName'];

      if (channelName == null || channelName.isEmpty) {
        debugPrint(
            '[NativeWebRTCTextureProvider] Failed to create pixel stream');
        return;
      }

      _eventChannel = EventChannel(channelName);

      // Latest-frame-wins strategy (same as NativeVideoTextureProvider).
      _sub = _eventChannel!
          .receiveBroadcastStream()
          .cast<Map<dynamic, dynamic>>()
          .listen(_onNativeEvent, onError: _onError);

      debugPrint(
          '[NativeWebRTCTextureProvider] Listening on channel: $channelName');
    } on PlatformException catch (e) {
      debugPrint(
          '[NativeWebRTCTextureProvider] PlatformException: ${e.message}');
      debugPrint('Ensure webrtc_pixel_stream is included as a dependency.');
    } on MissingPluginException catch (e) {
      debugPrint(
          '[NativeWebRTCTextureProvider] MissingPluginException: ${e.message}');
      debugPrint('webrtc_pixel_stream plugin not registered. '
          'Add it as a dependency in pubspec.yaml.');
    }
  }

  void _onNativeEvent(Map<dynamic, dynamic> event) {
    _pendingEvent = event;
    if (!_decoding) _processNext();
  }

  Future<void> _processNext() async {
    if (_pendingEvent == null) return;
    _decoding = true;
    final event = _pendingEvent!;
    _pendingEvent = null;

    try {
      final img = await decodeFrameEvent(event);
      if (img != null) {
        _currentFrame?.dispose();
        _currentFrame = img;
        if (!_ready) {
          _ready = true;
          debugPrint(
              '[NativeWebRTCTextureProvider] First frame: ${img.width}x${img.height}');
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[NativeWebRTCTextureProvider] decode error: $e');
    }

    _decoding = false;
    if (_pendingEvent != null) _processNext();
  }

  void _onError(Object err) {
    debugPrint('[NativeWebRTCTextureProvider] stream error: $err');
  }

  @override
  Future<ui.Image?> getCurrentFrame() async => _currentFrame;

  @override
  void dispose() {
    debugPrint('[NativeWebRTCTextureProvider] Disposing');
    _sub?.cancel();
    _sub = null;
    _currentFrame?.dispose();
    _currentFrame = null;
    // Tell the companion plugin to stop streaming and clean up the renderer
    _pixelStreamMethod.invokeMethod('disposePixelStream', {'trackId': trackId});
    super.dispose();
  }
}
