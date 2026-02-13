import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';
import 'texture_provider.dart';

/// Texture provider for video playback
/// Extracts frames from VideoPlayerController
class VideoTextureProvider extends PanoramaTextureProvider {
  final VideoPlayerController controller;
  final GlobalKey _videoKey = GlobalKey();
  ui.Image? _currentFrame;
  Timer? _frameTimer;
  bool _isInitialized = false;

  VideoTextureProvider(this.controller);

  @override
  PanoramaSourceType get sourceType => PanoramaSourceType.video;

  @override
  bool get isReady => _isInitialized && controller.value.isInitialized;

  /// Key for the video widget (used for frame capture)
  GlobalKey get videoKey => _videoKey;

  @override
  Future<void> initialize() async {
    if (!controller.value.isInitialized) {
      await controller.initialize();
    }
    _isInitialized = true;

    // Listen to video player state changes
    controller.addListener(_onVideoStateChanged);

    // Extract first frame BEFORE starting periodic extraction
    // This ensures we have a frame ready before the panorama tries to render
    await Future.delayed(const Duration(milliseconds: 100));
    await _extractFrame();

    // Wait a bit more to ensure the frame is captured
    await Future.delayed(const Duration(milliseconds: 50));

    // Start frame extraction for continuous updates
    // This ensures we capture frames even when video is paused
    _startFrameExtraction();
  }

  void _onVideoStateChanged() {
    // Keep frame extraction running regardless of play/pause state
    // This ensures panorama updates even when video is paused
    if (_frameTimer == null) {
      _startFrameExtraction();
    }
  }

  void _startFrameExtraction() {
    // Extract frames at 30 FPS for now
    // This is a temporary solution using screenshot approach
    // Will be replaced with platform channels for 60 FPS
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(
      const Duration(milliseconds: 33), // ~30 FPS
      (_) => _extractFrame(),
    );
  }

  void _stopFrameExtraction() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  Future<void> _extractFrame() async {
    try {
      final context = _videoKey.currentContext;
      if (context == null) {
        debugPrint('Frame extraction: context is null');
        return;
      }

      final boundary = context.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('Frame extraction: boundary is null');
        return;
      }

      // Capture the current frame
      final image = await boundary.toImage(pixelRatio: 1.0);

      // Only update if we got a valid frame
      if (image.width > 0 && image.height > 0) {
        // Dispose old frame
        _currentFrame?.dispose();
        _currentFrame = image;

        // Notify listeners that a new frame is available
        notifyListeners();
      }
    } catch (e) {
      // Silently fail - frame extraction can fail during transitions
      debugPrint('Frame extraction failed: $e');
    }
  }

  @override
  Future<ui.Image?> getCurrentFrame() async {
    return _currentFrame;
  }

  /// Build the video widget for frame capture
  /// This widget should be placed in the widget tree but can be invisible
  Widget buildVideoWidget() {
    // Ensure we have valid dimensions
    final width =
        controller.value.size.width > 0 ? controller.value.size.width : 1920.0;
    final height = controller.value.size.height > 0
        ? controller.value.size.height
        : 1080.0;

    return RepaintBoundary(
      key: _videoKey,
      child: SizedBox(
        width: width,
        height: height,
        child: VideoPlayer(controller),
      ),
    );
  }

  @override
  void dispose() {
    _stopFrameExtraction();
    controller.removeListener(_onVideoStateChanged);
    _currentFrame?.dispose();
    _currentFrame = null;
    _isInitialized = false;
    super.dispose();
  }
}
