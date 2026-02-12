import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Source type for panorama content
enum PanoramaSourceType {
  image,
  video,
  webrtc,
}

/// Abstract interface for providing textures to the panorama viewer
/// Supports both static images and dynamic video sources
abstract class PanoramaTextureProvider extends ChangeNotifier {
  /// The type of content this provider handles
  PanoramaSourceType get sourceType;

  /// Get the current frame as a ui.Image
  /// For static images, this returns the same image each time
  /// For video/WebRTC, this returns the current frame
  Future<ui.Image?> getCurrentFrame();

  /// Whether this provider has a valid texture ready
  bool get isReady;

  /// Initialize the provider (load image, start video, etc.)
  Future<void> initialize();

  /// Clean up resources
  @override
  void dispose();
}
