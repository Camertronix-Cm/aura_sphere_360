import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'texture_provider.dart';

/// Texture provider for static images
/// Wraps the existing ImageProvider logic
class ImageTextureProvider extends PanoramaTextureProvider {
  final ImageProvider imageProvider;
  ui.Image? _image;
  ImageStream? _imageStream;

  ImageTextureProvider(this.imageProvider);

  @override
  PanoramaSourceType get sourceType => PanoramaSourceType.image;

  @override
  bool get isReady => _image != null;

  @override
  Future<void> initialize() async {
    _imageStream?.removeListener(ImageStreamListener(_updateTexture));
    _imageStream = imageProvider.resolve(const ImageConfiguration());
    final completer = Completer<void>();

    void listener(ImageInfo info, bool synchronousCall) {
      _updateTexture(info, synchronousCall);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    _imageStream?.addListener(ImageStreamListener(listener));
    return completer.future;
  }

  void _updateTexture(ImageInfo imageInfo, bool synchronousCall) {
    _image = imageInfo.image;
    notifyListeners();
  }

  @override
  Future<ui.Image?> getCurrentFrame() async {
    return _image;
  }

  @override
  void dispose() {
    _imageStream?.removeListener(ImageStreamListener(_updateTexture));
    _imageStream = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
