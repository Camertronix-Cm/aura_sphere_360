# Deployment Guide - Panorama Viewer with Video Support

## 🚀 Quick Deployment (5 Minutes)

### Step 1: Add Dependency to Your Aura360 App

Navigate to your Aura360 app directory and edit `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Add these two dependencies
  panorama_viewer:
    git:
      url: https://github.com/Camertronix-Cm/panorama_viewer.git
      ref: feature/video-support
  video_player: ^2.9.2
  
  # ... your other dependencies
```

### Step 2: Install Dependencies

```bash
cd /path/to/your/aura360/app
flutter pub get
```

### Step 3: Import in Your Dart Files

```dart
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:video_player/video_player.dart';
```

### Step 4: Use in Your App

#### For Captured 360° Videos

```dart
class VideoViewerScreen extends StatefulWidget {
  final String videoPath; // Path to captured video
  
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
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.file(File(widget.videoPath));
    
    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      await _controller.play();
      
      setState(() {
        _initialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing video: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('360° Video'),
        actions: [
          IconButton(
            icon: Icon(
              _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
            onPressed: () {
              setState(() {
                if (_controller.value.isPlaying) {
                  _controller.pause();
                } else {
                  _controller.play();
                }
              });
            },
          ),
        ],
      ),
      body: _initialized
          ? PanoramaViewer(
              videoPlayerController: _controller,
              sensorControl: SensorControl.orientation,
              interactive: true,
            )
          : const Center(
              child: CircularProgressIndicator(),
            ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### Step 5: Test on Device

```bash
flutter run
```

Navigate to your video viewer screen and test!

---

## 📱 Integration Patterns

### Pattern 1: After Video Capture

```dart
// After capturing 360° video with your camera
void onVideoCaptured(String videoPath) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => VideoViewerScreen(videoPath: videoPath),
    ),
  );
}
```

### Pattern 2: Video Gallery

```dart
class VideoGalleryScreen extends StatelessWidget {
  final List<String> videoPaths;

  const VideoGalleryScreen({required this.videoPaths});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: videoPaths.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text('Video ${index + 1}'),
          trailing: const Icon(Icons.play_circle_outline),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoViewerScreen(
                  videoPath: videoPaths[index],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
```

### Pattern 3: With Custom Controls

```dart
class AdvancedVideoViewer extends StatefulWidget {
  final String videoPath;
  
  @override
  State<AdvancedVideoViewer> createState() => _AdvancedVideoViewerState();
}

class _AdvancedVideoViewerState extends State<AdvancedVideoViewer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.file(File(widget.videoPath));
    await _controller.initialize();
    await _controller.setLooping(true);
    await _controller.play();
    setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Panorama viewer
          if (_initialized)
            GestureDetector(
              onTap: () {
                setState(() {
                  _showControls = !_showControls;
                });
              },
              child: PanoramaViewer(
                videoPlayerController: _controller,
                sensorControl: SensorControl.orientation,
                interactive: true,
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          
          // Custom controls overlay
          if (_showControls && _initialized)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress bar
                    VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.blue,
                        bufferedColor: Colors.grey,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Control buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.replay_10, color: Colors.white),
                          onPressed: () {
                            final position = _controller.value.position;
                            _controller.seekTo(
                              position - const Duration(seconds: 10),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            _controller.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
                          onPressed: () {
                            setState(() {
                              _controller.value.isPlaying
                                  ? _controller.pause()
                                  : _controller.play();
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.forward_10, color: Colors.white),
                          onPressed: () {
                            final position = _controller.value.position;
                            _controller.seekTo(
                              position + const Duration(seconds: 10),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          
          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

---

## 🔧 Configuration Options

### PanoramaViewer Parameters

```dart
PanoramaViewer(
  // Required: Either child (for images) OR videoPlayerController (for videos)
  videoPlayerController: controller,  // For videos
  // child: Image.asset('...'),       // For images
  
  // Optional parameters
  sensorControl: SensorControl.orientation,  // Use gyroscope
  interactive: true,                         // Enable touch controls
  animSpeed: 1.0,                           // Animation speed
  zoom: 1.0,                                // Initial zoom level
  latSegments: 32,                          // Sphere detail (latitude)
  lonSegments: 64,                          // Sphere detail (longitude)
)
```

### Sensor Control Options

```dart
enum SensorControl {
  none,         // No sensor control
  orientation,  // Use gyroscope (recommended)
  absoluteOrientation,  // Use absolute orientation
}
```

---

## 🧪 Testing Checklist

### Before Deployment

- [ ] Test with local video files
- [ ] Test with different video resolutions (720p, 1080p)
- [ ] Test touch controls (pan, zoom, rotate)
- [ ] Test sensor controls (gyroscope)
- [ ] Test play/pause functionality
- [ ] Test video looping
- [ ] Test on iOS device
- [ ] Test on Android device
- [ ] Test with long videos (>1 minute)
- [ ] Test memory usage
- [ ] Test battery consumption

### Test Commands

```bash
# Run on iOS
flutter run -d <ios-device-id>

# Run on Android
flutter run -d <android-device-id>

# Run with performance profiling
flutter run --profile

# Check for issues
flutter analyze
```

---

## 🐛 Troubleshooting

### Issue: Video not showing

**Solution:**
```dart
// Make sure video is initialized before showing PanoramaViewer
if (_controller.value.isInitialized) {
  return PanoramaViewer(videoPlayerController: _controller);
} else {
  return CircularProgressIndicator();
}
```

### Issue: Video is choppy

**Possible causes:**
1. Video resolution too high (>1080p)
2. Device performance limitations
3. Other apps running in background

**Solution:**
- Use videos at 1920x1080 or lower
- Close other apps
- Test on newer device

### Issue: Sensor controls not working

**Solution:**
```dart
// Make sure sensor permission is granted
// Add to AndroidManifest.xml:
<uses-permission android:name="android.permission.SENSORS" />

// Check sensor availability
if (sensorControl != SensorControl.none) {
  // Sensors are being used
}
```

### Issue: Memory warnings

**Solution:**
```dart
// Always dispose controllers
@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

// Use smaller videos or implement video compression
```

---

## 📊 Performance Tips

### 1. Video Optimization

```dart
// Compress videos before playback
// Recommended settings:
// - Resolution: 1920x1080 or lower
// - Bitrate: 5-10 Mbps
// - Format: H.264 MP4
// - Frame rate: 30 FPS
```

### 2. Memory Management

```dart
// Dispose controllers when not needed
void navigateAway() {
  _controller.pause();
  _controller.dispose();
  Navigator.pop(context);
}
```

### 3. Battery Optimization

```dart
// Pause video when app goes to background
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    _controller.pause();
  } else if (state == AppLifecycleState.resumed) {
    _controller.play();
  }
}
```

---

## 🔄 Updating the Package

When updates are available:

```bash
# Update to latest version
flutter pub upgrade panorama_viewer

# Or specify a specific commit
# In pubspec.yaml:
panorama_viewer:
  git:
    url: https://github.com/Camertronix-Cm/panorama_viewer.git
    ref: <commit-hash-or-tag>
```

---

## 📞 Support

### Getting Help

1. **Check Documentation**
   - `README.md` - Usage examples
   - `RELEASE_NOTES.md` - Features and changes
   - `TESTING_GUIDE.md` - Testing instructions

2. **GitHub Issues**
   - https://github.com/Camertronix-Cm/panorama_viewer/issues

3. **Example App**
   - Run the example app: `cd example && flutter run`
   - Check `example/lib/screens/example_screen_video.dart`

---

## ✅ Deployment Checklist

- [ ] Added dependency to pubspec.yaml
- [ ] Ran `flutter pub get`
- [ ] Imported packages in Dart files
- [ ] Created video viewer screen
- [ ] Tested on iOS device
- [ ] Tested on Android device
- [ ] Tested with real 360° videos
- [ ] Verified touch controls work
- [ ] Verified sensor controls work
- [ ] Checked memory usage
- [ ] Added error handling
- [ ] Implemented proper disposal
- [ ] Ready to deploy! 🚀

---

## 🎉 You're Ready!

Your panorama_viewer with video support is now deployed and ready to use in your Aura360 app!

**Next Steps:**
1. Integrate into your video capture flow
2. Test with real users
3. Gather feedback
4. Iterate and improve

**Questions?** Check the documentation or create a GitHub issue.

**Happy coding! 🎥📱**
