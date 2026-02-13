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

    // Start frame extraction immediately
    // This ensures we capture frames even when video is paused
    _startFrameExtraction();

    // Listen to video player state changes
    controller.addListener(_onVideoStateChanged);

    // Extract first frame immediately
    await Future.delayed(const Duration(milliseconds: 100));
    _extractFrame();
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
      if (context == null) return;

      final boundary = context.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      // Capture the current frame
      final image = await boundary.toImage(pixelRatio: 1.0);

      // Dispose old frame
      _currentFrame?.dispose();
      _currentFrame = image;

      // Notify listeners that a new frame is available
      notifyListeners();
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
    return RepaintBoundary(
      key: _videoKey,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
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
