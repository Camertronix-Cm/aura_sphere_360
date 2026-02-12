# Aura Sphere 360

Immersive 360° panorama and video viewer for Flutter. Perfect for VR experiences, virtual tours, and 360° media playback.

[![pub package](https://img.shields.io/pub/v/aura_sphere_360.svg)](https://pub.dev/packages/aura_sphere_360)

## ✨ Features

- ✅ 360° image panoramas
- ✅ 360° video panoramas
- ✅ Touch controls (pan, zoom, rotate)
- ✅ Sensor controls (gyroscope)
- ✅ Smooth 30 FPS video playback
- ✅ Cross-platform (iOS, Android, Web)
- ✅ Easy integration

## 🚀 Getting Started

### Installation

Add aura_sphere_360 to your `pubspec.yaml`:

```yaml
dependencies:
  aura_sphere_360: ^1.0.0
```

Then run:
```bash
flutter pub get
```

### Image Panoramas

```dart
import 'package:aura_sphere_360/aura_sphere_360.dart';

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: AuraSphere(
      child: Image.asset('assets/panorama360.jpg'),
    ),
  );
}
```

### Video Panoramas

```dart
import 'package:aura_sphere_360/aura_sphere_360.dart';
import 'package:video_player/video_player.dart';

class VideoPanoramaScreen extends StatefulWidget {
  @override
  _VideoPanoramaScreenState createState() => _VideoPanoramaScreenState();
}

class _VideoPanoramaScreenState extends State<VideoPanoramaScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    
    // Load video from file, network, or assets
    _controller = VideoPlayerController.file(File('path/to/video.mp4'));
    // Or from network:
    // _controller = VideoPlayerController.networkUrl(
    //   Uri.parse('https://example.com/video.mp4')
    // );
    
    _controller.initialize().then((_) {
      _controller.setLooping(true);
      _controller.play();
      setState(() => _initialized = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _initialized
          ? AuraSphere(
              videoPlayerController: _controller,
              sensorControl: SensorControl.orientation,
            )
          : Center(child: CircularProgressIndicator()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

## 🎮 Controls

### Touch Controls
- **Pan**: Drag to look around
- **Zoom**: Pinch to zoom in/out
- **Rotate**: Two-finger rotate

### Sensor Controls
- **Gyroscope**: Move your device to look around
- **Orientation**: Automatic orientation tracking

## 📱 Supported Platforms

- ✅ iOS
- ✅ Android
- ✅ Web (without sensor controls)

## 🎥 Video Support

- **Frame Rate**: 30 FPS (smooth for 360° viewing)
- **Supported Sources**: Local files, network URLs, assets
- **Performance**: Optimized for videos up to 1920x1080
- **Auto-scaling**: Larger videos are automatically scaled

## 📚 Documentation

- [Quick Start Guide](https://github.com/Camertronix-Cm/aura_sphere_360/blob/main/QUICK_START.md)
- [Deployment Guide](https://github.com/Camertronix-Cm/aura_sphere_360/blob/main/DEPLOYMENT_GUIDE.md)
- [API Documentation](https://pub.dev/documentation/aura_sphere_360/latest/)

## 💡 Examples

Check out the `example` folder for complete working examples:
- Image panoramas
- Video panoramas
- Custom controls
- Sensor integration

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

Apache 2.0

## 🙏 Credits

Built on top of the excellent [panorama_viewer](https://pub.dev/packages/panorama_viewer) package by dariocavada, with added video support and enhancements.

## 🔗 Links

- [GitHub Repository](https://github.com/Camertronix-Cm/aura_sphere_360)
- [Issue Tracker](https://github.com/Camertronix-Cm/aura_sphere_360/issues)
- [Pub.dev Package](https://pub.dev/packages/aura_sphere_360)
