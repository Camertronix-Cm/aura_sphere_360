# Panorama Viewer

A 360-degree panorama viewer with support for both images and videos.

This package is an updated porting of the plugin https://github.com/zesage/panorama with added video support.

## Features

- ✅ 360° image panoramas
- ✅ 360° video panoramas (NEW!)
- ✅ Touch controls (pan, zoom, rotate)
- ✅ Sensor controls (gyroscope)
- ✅ Cross-platform (iOS, Android, Web)
- ✅ Smooth 30 FPS video playback

## Getting Started

### Installation

Add panorama_viewer as a dependency in your pubspec.yaml file.

```yaml
dependencies:
  panorama_viewer:
    git:
      url: https://github.com/Camertronix-Cm/panorama_viewer.git
      ref: feature/video-support
  video_player: ^2.9.2  # Required for video support
```

### Image Panoramas

Import and add the Panorama Viewer widget to your project.

```dart
import 'package:panorama_viewer/panorama_viewer.dart';

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Center(
      child: PanoramaViewer(
        child: Image.asset('assets/panorama360.jpg'),
      ),
    ),
  );
}
```

### Video Panoramas (NEW!)

```dart
import 'package:panorama_viewer/panorama_viewer.dart';
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
          ? PanoramaViewer(
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

## Video Support Details

- **Frame Rate**: 30 FPS (smooth for 360° viewing)
- **Supported Sources**: Local files, network URLs, assets
- **Platforms**: iOS and Android
- **Performance**: Optimized for videos up to 1920x1080
- **Auto-scaling**: Larger videos are automatically scaled

## Migration from the Panorama package

- In the dependencies, use `panorama_viewer` instead of `panorama`.
- In the Dart files where you use panorama, change the import to: `import 'package:panorama_viewer/panorama_viewer.dart';`.
- Change the widget name from `Panorama` to `PanoramaViewer`.
- If you've used `SensorControl`, change `SensorControl.Orientation` to `SensorControl.orientation`. All constant names are now in lower camel case, following the latest Dart best practices.

## Web implementation

On the web, sensors are not utilized because the sensor library used is only compatible with iOS and Android devices. Additionally, on some Android devices, if the panoramic image is too large, nothing is displayed. When checking the console log remotely, you may encounter WebGL errors or warnings.

## Examples

See the `example` folder for complete working examples of both image and video panoramas.

## License

Apache 2.0




