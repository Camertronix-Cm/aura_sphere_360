# Video Testing Checklist

## Current Testing Status

### ✅ Tested
- [x] Network video URL (butterfly.mp4 from Flutter assets)
- [x] Video playback at 30 FPS
- [x] Touch controls (pan, zoom)
- [x] Play/pause controls
- [x] Video looping
- [x] iOS device testing

### ⚠️ Not Yet Tested
- [ ] Local file video (`VideoPlayerController.file()`)
- [ ] Asset video (`VideoPlayerController.asset()`)
- [ ] Actual 360° video (butterfly.mp4 is not a 360° video)
- [ ] Android device testing
- [ ] WebRTC streams
- [ ] Different video formats (MP4, MOV, etc.)
- [ ] Large video files (>100MB)
- [ ] Different resolutions (4K, 8K)

## How to Test Local Video

### Option 1: Test with Asset Video

1. Download a 360° video sample (e.g., from YouTube or stock footage sites)
2. Add it to `example/assets/` folder
3. Update `example/pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/
       - assets/video360.mp4  # Add your video
   ```
4. Update `example/lib/screens/example_screen_video.dart`:
   ```dart
   _videoController = VideoPlayerController.asset('assets/video360.mp4');
   ```
5. Run the app and test

### Option 2: Test with Local File (iOS)

1. Add a video to your iOS device (via Files app or iTunes)
2. Update `example/lib/screens/example_screen_video.dart`:
   ```dart
   import 'dart:io';
   
   _videoController = VideoPlayerController.file(
     File('/var/mobile/Containers/Data/Application/.../video.mp4'),
   );
   ```
3. Or use file picker to select video at runtime

### Option 3: Test with File Picker (Recommended)

Add `file_picker` package and let user select video:

```dart
import 'package:file_picker/file_picker.dart';
import 'dart:io';

Future<void> _pickAndPlayVideo() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.video,
  );
  
  if (result != null) {
    File file = File(result.files.single.path!);
    _videoController = VideoPlayerController.file(file);
    await _videoController.initialize();
    _videoController.play();
    setState(() => _isInitialized = true);
  }
}
```

## Test Cases to Verify

### Basic Functionality
- [ ] Video loads and plays
- [ ] Video displays in 360° sphere
- [ ] Touch controls work (pan, zoom, rotate)
- [ ] Play/pause button works
- [ ] Video loops correctly
- [ ] Seek/restart works

### Performance
- [ ] Maintains ~30 FPS during playback
- [ ] No memory leaks during long playback
- [ ] Smooth transitions when seeking
- [ ] No frame drops during interaction

### Edge Cases
- [ ] Video with different aspect ratios
- [ ] Very short videos (<1 second)
- [ ] Very long videos (>1 hour)
- [ ] Corrupted video files (should fail gracefully)
- [ ] Network interruption (for network videos)
- [ ] App backgrounding/foregrounding

## Known Limitations

1. **Frame Rate**: Limited to ~30 FPS due to RepaintBoundary screenshot approach
2. **Video Size**: Video widget must be rendered at actual size (currently 0.01 opacity in corner)
3. **Not True 360°**: The butterfly.mp4 test video is NOT a 360° video, so it won't look correct when mapped to sphere

## Recommendation Before Publishing

**CRITICAL**: Test with at least one actual 360° video file using `VideoPlayerController.file()` or `VideoPlayerController.asset()` to ensure:
1. Local file loading works
2. Actual 360° content displays correctly
3. Performance is acceptable with real-world content

## Where to Get 360° Test Videos

1. **Free 360° Videos**:
   - https://www.360cities.net/
   - https://www.youtube.com/results?search_query=360+video+download
   - https://www.pexels.com/search/videos/360/

2. **Create Your Own**:
   - Use a 360° camera (Insta360, GoPro MAX, etc.)
   - Use smartphone apps that create 360° videos

## Current Implementation Details

The video texture provider uses:
- `RepaintBoundary` to capture video frames
- `toImage()` to convert to texture
- 33ms delay (~30 FPS) between frame captures
- Video widget rendered at actual size with 0.01 opacity

This approach works for:
- ✅ Network URLs
- ✅ Asset files (should work, not tested)
- ✅ Local files (should work, not tested)
- ✅ Any source supported by `video_player` package
