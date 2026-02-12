# Quick Start - 5 Minute Integration

## 1. Add Dependency (30 seconds)

```yaml
# pubspec.yaml
dependencies:
  panorama_viewer:
    git:
      url: https://github.com/Camertronix-Cm/panorama_viewer.git
      ref: feature/video-support
  video_player: ^2.9.2
```

```bash
flutter pub get
```

## 2. Import (10 seconds)

```dart
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:video_player/video_player.dart';
```

## 3. Copy-Paste This Code (2 minutes)

```dart
class VideoViewerScreen extends StatefulWidget {
  final String videoPath;
  const VideoViewerScreen({required this.videoPath});

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath));
    _controller.initialize().then((_) {
      _controller.setLooping(true);
      _controller.play();
      setState(() => _initialized = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('360° Video'),
        actions: [
          IconButton(
            icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(() {
              _controller.value.isPlaying ? _controller.pause() : _controller.play();
            }),
          ),
        ],
      ),
      body: _initialized
          ? PanoramaViewer(
              videoPlayerController: _controller,
              sensorControl: SensorControl.orientation,
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

## 4. Use It (1 minute)

```dart
// Navigate to video viewer
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => VideoViewerScreen(
      videoPath: '/path/to/your/video.mp4',
    ),
  ),
);
```

## 5. Test (1 minute)

```bash
flutter run
```

## Done! 🎉

Your 360° video viewer is working!

---

## Common Customizations

### Remove Sensor Control
```dart
PanoramaViewer(
  videoPlayerController: _controller,
  sensorControl: SensorControl.none,  // Touch only
)
```

### Disable Touch
```dart
PanoramaViewer(
  videoPlayerController: _controller,
  interactive: false,  // Sensor only
)
```

### Change Initial Zoom
```dart
PanoramaViewer(
  videoPlayerController: _controller,
  zoom: 1.5,  // Zoomed in
)
```

### Network Video
```dart
_controller = VideoPlayerController.networkUrl(
  Uri.parse('https://example.com/video.mp4'),
);
```

### Asset Video
```dart
_controller = VideoPlayerController.asset('assets/video.mp4');
```

---

## Need More?

- **Full Guide**: See `DEPLOYMENT_GUIDE.md`
- **Examples**: Check `example/lib/screens/example_screen_video.dart`
- **Issues**: https://github.com/Camertronix-Cm/panorama_viewer/issues

**That's it! You're ready to go! 🚀**
