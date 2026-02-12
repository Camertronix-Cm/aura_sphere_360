# Testing Guide - Video Panorama Support

## Quick Start

### 1. Install Dependencies
```bash
cd example
flutter pub get
```

### 2. Run the Example App
```bash
# iOS Simulator
flutter run -d "iPhone 15 Pro"

# Android Emulator
flutter run -d emulator-5554

# Physical Device
flutter run
```

### 3. Test Video Panorama

1. Launch the app
2. Tap on "Example 6 - Video Panorama (NEW)"
3. Wait for video to load
4. Test the following:

## Test Cases

### ✅ Basic Functionality

- [ ] Video loads and plays automatically
- [ ] Video loops when it reaches the end
- [ ] Touch pan works (drag to rotate view)
- [ ] Pinch zoom works
- [ ] Play/pause button in app bar works
- [ ] Restart button (floating action) works
- [ ] Info button shows video details

### ✅ Existing Features (Regression Testing)

- [ ] Example 1 (minimum code) still works
- [ ] Example 2 (transparent appbar) still works
- [ ] Example 3 (hotspots) still works
- [ ] Example 4 (zoom controls) still works
- [ ] Example 5 (side by side) still works

### ⚠️ Known Limitations (Current Phase)

- Frame rate: ~30 FPS (will be 60 FPS in Phase 3)
- Sample video is NOT 360° equirectangular (just for demo)
- Slight lag visible during playback (expected with screenshot approach)

## Testing with Real 360° Video

To test with an actual 360° equirectangular video:

### Option 1: Network Video
```dart
_videoController = VideoPlayerController.networkUrl(
  Uri.parse('YOUR_360_VIDEO_URL'),
);
```

### Option 2: Asset Video

1. Add video to `example/assets/`:
```bash
mkdir -p example/assets
# Copy your 360 video to example/assets/my_360_video.mp4
```

2. Update `example/pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/
    - assets/my_360_video.mp4  # Add this line
```

3. Update `example/lib/screens/example_screen_video.dart`:
```dart
_videoController = VideoPlayerController.asset(
  'assets/my_360_video.mp4',
);
```

### Option 3: File Video
```dart
_videoController = VideoPlayerController.file(
  File('/path/to/video.mp4'),
);
```

## Sample 360° Videos for Testing

Free 360° equirectangular videos:
- https://www.360cities.net/
- https://www.youtube.com/results?search_query=360+video+download
- https://github.com/google/spatial-media (sample videos)

## Performance Testing

### Check Frame Rate
```dart
// Add to example_screen_video.dart
int _frameCount = 0;
DateTime _lastTime = DateTime.now();

void _updateFrameRate() {
  _frameCount++;
  final now = DateTime.now();
  final diff = now.difference(_lastTime).inMilliseconds;
  if (diff >= 1000) {
    print('FPS: ${_frameCount * 1000 / diff}');
    _frameCount = 0;
    _lastTime = now;
  }
}
```

### Expected Performance (Phase 2)
- Frame Rate: 25-30 FPS
- CPU Usage: Medium-High
- Memory: ~100-200 MB
- Battery: Higher drain than static images

### Target Performance (Phase 3)
- Frame Rate: 60 FPS
- CPU Usage: Low-Medium
- Memory: ~100-150 MB
- Battery: Optimized

## Troubleshooting

### Video doesn't load
- Check internet connection (for network videos)
- Check video format (MP4 recommended)
- Check video codec (H.264 recommended)
- Check console for errors

### Video is distorted
- Ensure video is equirectangular format
- Check video aspect ratio (should be 2:1)
- Verify video resolution (4K recommended)

### Performance is poor
- Expected in Phase 2 (screenshot approach)
- Will be fixed in Phase 3 (platform channels)
- Try lower resolution video
- Close other apps

### Touch controls don't work
- Check `interactive: true` parameter
- Ensure video is playing
- Try restarting the app

## Platform-Specific Testing

### iOS
```bash
flutter run -d iPhone
```
- Test on iOS 12+ devices
- Check video playback with AVPlayer
- Test sensor controls (gyroscope)

### Android
```bash
flutter run -d android
```
- Test on Android 5.0+ devices
- Check video playback with ExoPlayer
- Test sensor controls (gyroscope)

### Web (Future)
```bash
flutter run -d chrome
```
- Video player support limited on web
- May require different implementation

## Reporting Issues

When reporting issues, include:
1. Device/Simulator info
2. Flutter version (`flutter --version`)
3. Video source (network/asset/file)
4. Video format and resolution
5. Console logs
6. Steps to reproduce

## Next Steps

After testing Phase 2:
- Provide feedback on performance
- Test with real 360° videos
- Report any bugs or issues
- Ready for Phase 3 (platform channels)

## Phase 2 Testing Status

- [ ] Tested on iOS Simulator
- [ ] Tested on iOS Device
- [ ] Tested on Android Emulator
- [ ] Tested on Android Device
- [ ] Tested with 360° video
- [ ] Performance profiled
- [ ] All existing examples work
- [ ] Ready for Phase 3
