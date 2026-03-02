import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'texture_provider.dart';
import 'native_frame_decoder.dart';

/// Native video texture provider that extracts frames via AVPlayerItemVideoOutput
/// on iOS (and MediaCodec+ImageReader on Android).
///
/// This replaces [VideoTextureProvider] entirely. No hidden widgets, no
/// RepaintBoundary, no Timer.periodic — frames arrive via EventChannel from
/// native code running on a background thread.
///
/// The native extractor handles its own AVPlayer, so this provider takes a URL
/// directly rather than a VideoPlayerController. This avoids running two AVPlayer
/// instances on the same video (which doubles hardware decoder load).
///
/// Example:
/// ```dart
/// final provider = NativeVideoTextureProvider(
///   'https://example.com/360video.mp4',
/// );
/// await provider.initialize();
/// ```
class NativeVideoTextureProvider extends PanoramaTextureProvider {
  static const MethodChannel _method = MethodChannel('panorama_viewer/control');

  /// The URL of the video to play.
  final String videoUrl;

  /// Whether to loop the video. Defaults to true.
  final bool looping;

  String? _extractorId; // channel name returned by native
  EventChannel? _eventChannel;
  StreamSubscription? _sub;
  ui.Image? _currentFrame;
  bool _ready = false;
  bool _decoding = false;
  Map<dynamic, dynamic>? _pendingEvent;

  NativeVideoTextureProvider(
    this.videoUrl, {
    this.looping = true,
  });

  @override
  PanoramaSourceType get sourceType => PanoramaSourceType.video;

  @override
  bool get isReady => _ready;

  @override
  Future<void> initialize() async {
    debugPrint('[NativeVideoTextureProvider] Initializing with URL: $videoUrl');

    _extractorId = await _method
        .invokeMethod<String>('createVideoExtractor', {'url': videoUrl});

    if (_extractorId == null || _extractorId!.isEmpty) {
      debugPrint('[NativeVideoTextureProvider] Failed to create extractor');
      return;
    }

    _eventChannel = EventChannel(_extractorId!);

    // Listen for native frame events.
    // Uses a latest-frame-wins strategy to avoid unbounded queueing.
    _sub = _eventChannel!
        .receiveBroadcastStream()
        .cast<Map<dynamic, dynamic>>()
        .listen(_onNativeEvent, onError: _onError);

    // Configure looping
    await _method.invokeMethod(
        'videoSetLooping', {'id': _extractorId, 'looping': looping});

    // Start playback
    await _method.invokeMethod('videoPlay', {'id': _extractorId});

    debugPrint(
        '[NativeVideoTextureProvider] Initialized, awaiting first frame');
  }

  /// Called for each frame event from native. Uses latest-frame-wins:
  /// if a decode is in-flight, we store only the newest event and drop
  /// all intermediate ones.
  void _onNativeEvent(Map<dynamic, dynamic> event) {
    _pendingEvent = event;
    if (!_decoding) _processNext();
  }

  Future<void> _processNext() async {
    if (_pendingEvent == null) return;
    _decoding = true;
    final event = _pendingEvent!;
    _pendingEvent = null; // drop any older frames

    try {
      final img = await decodeFrameEvent(event);
      if (img != null) {
        _currentFrame?.dispose();
        _currentFrame = img;
        if (!_ready) {
          _ready = true;
          debugPrint(
              '[NativeVideoTextureProvider] First frame decoded: ${img.width}x${img.height}');
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[NativeVideoTextureProvider] decode error: $e');
    }

    _decoding = false;
    // If a newer frame arrived while we were decoding, process it now
    if (_pendingEvent != null) _processNext();
  }

  void _onError(Object err) {
    debugPrint('[NativeVideoTextureProvider] stream error: $err');
  }

  /// Resume playback.
  Future<void> play() =>
      _method.invokeMethod('videoPlay', {'id': _extractorId});

  /// Pause playback.
  Future<void> pause() =>
      _method.invokeMethod('videoPause', {'id': _extractorId});

  /// Seek to a specific position.
  Future<void> seek(Duration position) => _method.invokeMethod('videoSeek', {
        'id': _extractorId,
        'seconds': position.inMicroseconds / 1e6,
      });

  @override
  Future<ui.Image?> getCurrentFrame() async => _currentFrame;

  @override
  void dispose() {
    debugPrint('[NativeVideoTextureProvider] Disposing');
    _sub?.cancel();
    _sub = null;
    _currentFrame?.dispose();
    _currentFrame = null;
    if (_extractorId != null) {
      _method.invokeMethod('disposeVideoExtractor', {'id': _extractorId});
    }
    super.dispose();
  }
}
