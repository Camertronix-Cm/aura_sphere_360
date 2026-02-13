import 'dart:async';
import 'dart:typed_data';
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
  bool _hasFirstFrame = false;

  VideoTextureProvider(this.controller);

  @override
  PanoramaSourceType get sourceType => PanoramaSourceType.video;

  @override
  bool get isReady =>
      _isInitialized && _hasFirstFrame && controller.value.isInitialized;

  /// Key for the video widget (used for frame capture)
  GlobalKey get videoKey => _videoKey;

  @override
  Future<void> initialize() async {
    debugPrint('🎬 [VideoTextureProvider] initialize() called');

    if (!controller.value.isInitialized) {
      debugPrint('🎬 [VideoTextureProvider] Initializing video controller...');
      await controller.initialize();
    }
    debugPrint(
        '🎬 [VideoTextureProvider] Video controller initialized: ${controller.value.size}');

    _isInitialized = true;
    _hasFirstFrame = false;

    // Listen to video player state changes
    controller.addListener(_onVideoStateChanged);

    // NOTE: We do NOT start frame extraction here because the video widget
    // (RepaintBoundary with _videoKey) may not be in the widget tree yet.
    // The caller (PanoramaState) must trigger a rebuild first, then call
    // startFrameExtraction().
    debugPrint(
        '🎬 [VideoTextureProvider] initialize() complete, waiting for widget to be in tree');
  }

  /// Called by PanoramaState after the widget tree has been rebuilt
  /// to include the video widget. This starts frame extraction and
  /// waits for the first valid frame.
  Future<void> startFrameExtractionAndWaitForFirstFrame() async {
    debugPrint(
        '🎬 [VideoTextureProvider] startFrameExtractionAndWaitForFirstFrame() called');
    debugPrint(
        '🎬 [VideoTextureProvider] videoKey context: ${_videoKey.currentContext != null ? "EXISTS" : "NULL"}');

    _startFrameExtraction();
    await _waitForFirstFrame();
  }

  /// Waits until `_extractFrame()` captures a non-blank frame.
  Future<void> _waitForFirstFrame() async {
    const maxAttempts = 50; // 50 × 100ms = 5 seconds max
    debugPrint(
        '🎬 [VideoTextureProvider] Waiting for first valid frame (max ${maxAttempts * 100}ms)...');

    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 100));

      final context = _videoKey.currentContext;
      if (context == null) {
        debugPrint(
            '🎬 [VideoTextureProvider] Attempt ${i + 1}: video widget context is still NULL');
        continue;
      }

      if (_currentFrame != null) {
        final valid = await _isFrameValid(_currentFrame!);
        debugPrint(
            '🎬 [VideoTextureProvider] Attempt ${i + 1}: frame ${_currentFrame!.width}x${_currentFrame!.height}, valid=$valid');
        if (valid) {
          _hasFirstFrame = true;
          debugPrint(
              '🎬 [VideoTextureProvider] ✅ First valid frame captured after ${(i + 1) * 100}ms');
          return;
        }
      } else {
        debugPrint(
            '🎬 [VideoTextureProvider] Attempt ${i + 1}: _currentFrame is null');
      }
    }

    // Timeout — accept whatever we have
    _hasFirstFrame = true;
    debugPrint(
        '🎬 [VideoTextureProvider] ⚠️ Timed out waiting for valid frame, proceeding anyway');
  }

  /// Checks whether a captured frame contains actual video content.
  /// Rejects all-white and all-black/transparent frames.
  Future<bool> _isFrameValid(ui.Image image) async {
    try {
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return false;

      final Uint8List pixels = byteData.buffer.asUint8List();
      if (pixels.isEmpty) return false;

      final int totalPixels = pixels.length ~/ 4;
      final int step = (totalPixels / 20).floor().clamp(1, totalPixels);

      bool allWhite = true;
      bool allBlack = true;

      for (int i = 0; i < totalPixels; i += step) {
        final int offset = i * 4;
        if (offset + 3 >= pixels.length) break;

        final int r = pixels[offset];
        final int g = pixels[offset + 1];
        final int b = pixels[offset + 2];
        final int a = pixels[offset + 3];

        if (r != 255 || g != 255 || b != 255 || a != 255) {
          allWhite = false;
        }
        if (r != 0 || g != 0 || b != 0 || a != 0) {
          allBlack = false;
        }

        if (!allWhite && !allBlack) return true;
      }

      return !allWhite && !allBlack;
    } catch (e) {
      debugPrint('🎬 [VideoTextureProvider] Frame validation error: $e');
      return true;
    }
  }

  void _onVideoStateChanged() {
    if (_frameTimer == null) {
      _startFrameExtraction();
    }
  }

  void _startFrameExtraction() {
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
        return;
      }

      final boundary = context.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        return;
      }

      final image = await boundary.toImage(pixelRatio: 1.0);

      if (image.width > 0 && image.height > 0) {
        _currentFrame?.dispose();
        _currentFrame = image;

        if (_hasFirstFrame) {
          notifyListeners();
        }
      }
    } catch (e) {
      // Silently fail - frame extraction can fail during transitions
    }
  }

  @override
  Future<ui.Image?> getCurrentFrame() async {
    return _currentFrame;
  }

  /// Build the video widget for frame capture.
  /// This widget MUST be in the widget tree for frame extraction to work.
  Widget buildVideoWidget() {
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
    _hasFirstFrame = false;
    super.dispose();
  }
}
