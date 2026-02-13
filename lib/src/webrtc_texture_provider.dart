import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'texture_provider.dart';

/// Texture provider for WebRTC video streams
///
/// Extracts frames from an RTCVideoRenderer and provides them as ui.Image
/// for rendering in the panorama viewer. Uses RepaintBoundary to capture
/// frames at ~30 FPS.
///
/// Example:
/// ```dart
/// final renderer = RTCVideoRenderer();
/// await renderer.initialize();
/// renderer.srcObject = stream;
///
/// final provider = WebRTCTextureProvider(renderer);
/// await provider.initialize();
/// ```
class WebRTCTextureProvider extends PanoramaTextureProvider {
  final RTCVideoRenderer renderer;
  final GlobalKey _rendererKey = GlobalKey();
  ui.Image? _currentFrame;
  bool _isExtracting = false;
  bool _isReady = false;
  Timer? _frameExtractionTimer;

  WebRTCTextureProvider(this.renderer);

  @override
  PanoramaSourceType get sourceType => PanoramaSourceType.webrtc;

  @override
  bool get isReady => _isReady;

  @override
  Future<void> initialize() async {
    debugPrint('🌐 [WebRTCTextureProvider] Initializing...');

    // Listen for renderer updates
    renderer.addListener(_onRendererUpdate);

    // Start periodic frame extraction at 30 FPS
    _startFrameExtraction();

    _isReady = true;
    debugPrint('🌐 [WebRTCTextureProvider] Initialized');
  }

  void _startFrameExtraction() {
    debugPrint('🌐 [WebRTCTextureProvider] Starting frame extraction timer');
    _frameExtractionTimer?.cancel();
    _frameExtractionTimer = Timer.periodic(
      const Duration(milliseconds: 33), // ~30 FPS
      (_) => _extractFrame(),
    );
  }

  void _onRendererUpdate() {
    // Trigger frame extraction when renderer updates
    _extractFrame();
  }

  Future<void> _extractFrame() async {
    if (_isExtracting || !_isReady) return;
    _isExtracting = true;

    try {
      final boundary = _rendererKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary != null && boundary.debugNeedsPaint == false) {
        // Extract frame at native resolution
        final image = await boundary.toImage(pixelRatio: 1.0);

        // Update current frame
        _currentFrame?.dispose();
        _currentFrame = image;

        // Notify listeners
        notifyListeners();
      }
    } catch (e) {
      debugPrint('🌐 [WebRTCTextureProvider] Frame extraction error: $e');
    } finally {
      _isExtracting = false;
    }
  }

  @override
  Future<ui.Image?> getCurrentFrame() async {
    // If we don't have a frame yet, try to extract one
    if (_currentFrame == null) {
      await _extractFrame();
    }
    return _currentFrame;
  }

  /// Build the hidden WebRTC renderer widget
  ///
  /// This widget must be included in the widget tree (with low opacity)
  /// for frame extraction to work.
  Widget buildRendererWidget() {
    // Get actual video dimensions from renderer, or use defaults
    final videoWidth =
        renderer.videoWidth > 0 ? renderer.videoWidth.toDouble() : 640.0;
    final videoHeight =
        renderer.videoHeight > 0 ? renderer.videoHeight.toDouble() : 480.0;

    debugPrint(
        '🌐 [WebRTCTextureProvider] Video dimensions: ${videoWidth}x$videoHeight');

    return SizedBox(
      width: videoWidth,
      height: videoHeight,
      child: RepaintBoundary(
        key: _rendererKey,
        child: RTCVideoView(
          renderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          mirror: false,
        ),
      ),
    );
  }

  @override
  void dispose() {
    debugPrint('🌐 [WebRTCTextureProvider] Disposing...');
    _frameExtractionTimer?.cancel();
    _frameExtractionTimer = null;
    renderer.removeListener(_onRendererUpdate);
    _currentFrame?.dispose();
    _currentFrame = null;
    _isReady = false;
    super.dispose();
  }
}
