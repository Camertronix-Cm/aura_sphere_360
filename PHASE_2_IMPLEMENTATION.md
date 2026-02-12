# Phase 2: Core Architecture Implementation

## Overview

Phase 2 implements the core architecture for video support in panorama_viewer. This phase adds the texture provider abstraction layer and basic video playback support.

## Changes Made

### 1. New Files Created

#### `lib/src/texture_provider.dart`
- Abstract base class for all texture providers
- Defines `PanoramaSourceType` enum (image, video, webrtc)
- Interface: `getCurrentFrame()`, `initialize()`, `dispose()`

#### `lib/src/image_texture_provider.dart`
- Wraps existing ImageProvider logic
- Maintains backward compatibility
- No changes to existing image functionality

#### `lib/src/video_texture_provider.dart`
- Extracts frames from VideoPlayerController
- Uses screenshot approach (temporary - 30 FPS)
- Will be replaced with platform channels for 60 FPS

### 2. Modified Files

#### `lib/panorama_viewer.dart`
- Added `videoPlayerController` parameter
- Added texture provider support
- Modified `_onSceneCreated()` to initialize providers
- Added `_initializeTextureProvider()` method
- Added `_updateTextureFromProvider()` method
- Hidden video widget for frame capture

#### `pubspec.yaml`
- Added `video_player: ^2.9.2` dependency

#### `example/lib/main.dart`
- Added video example to menu

#### `example/lib/screens/example_screen_video.dart`
- New example demonstrating video playback
- Play/pause controls
- Video info display

#### `example/pubspec.yaml`
- Added `video_player: ^2.9.2` dependency

## Architecture

```
PanoramaViewer
  ├─ PanoramaTextureProvider (abstract)
  │   ├─ ImageTextureProvider (existing images)
  │   ├─ VideoTextureProvider (new - video files)
  │   └─ WebRTCTextureProvider (future - Phase 4)
  │
  └─ flutter_cube Scene
      └─ Mesh with dynamic texture
```

## Usage

### Static Image (Existing - Unchanged)
```dart
PanoramaViewer(
  child: Image.asset('assets/panorama.jpg'),
)
```

### Video Panorama (New)
```dart
final controller = VideoPlayerController.network('video_url.mp4');
await controller.initialize();
controller.play();

PanoramaViewer(
  videoPlayerController: controller,
)
```

## Testing

### Run the Example App

1. Install dependencies:
```bash
cd example
flutter pub get
```

2. Run on device/simulator:
```bash
flutter run
```

3. Navigate to "Example 6 - Video Panorama (NEW)"

### Expected Behavior

- Video should load and play automatically
- Touch controls work (pan, zoom)
- Sensor controls work (if enabled)
- Play/pause button in app bar
- Restart button (floating action button)
- Info button shows video details

### Current Limitations

1. **Frame Rate**: ~30 FPS (screenshot approach)
   - Will be improved to 60 FPS with platform channels in Phase 3

2. **Performance**: Higher CPU usage than optimal
   - Platform channels will reduce CPU load

3. **Video Widget**: Hidden off-screen for frame capture
   - Necessary for screenshot approach
   - Will be removed when platform channels implemented

## Performance Notes

### Current Implementation (Screenshot Approach)

**Pros:**
- Simple implementation
- Works on all platforms
- No native code required
- Good for prototyping

**Cons:**
- Limited to ~30 FPS
- Higher CPU usage
- Memory overhead
- Not production-ready for high-quality 360° video

### Next Phase (Platform Channels)

Will implement direct frame access:
- iOS: AVPlayerItemVideoOutput + CVPixelBuffer
- Android: ExoPlayer VideoFrameMetadataListener + SurfaceTexture
- Target: 60 FPS
- Lower CPU usage
- Production-ready

## API Changes

### New Parameters

```dart
PanoramaViewer({
  // Existing parameters...
  Image? child,
  
  // NEW: Video support
  VideoPlayerController? videoPlayerController,
  
  // Existing parameters...
})
```

### Constraints

- Cannot provide both `child` and `videoPlayerController`
- Assertion will fail if both are provided

## Backward Compatibility

✅ All existing code continues to work unchanged
✅ No breaking changes to API
✅ Image panoramas work exactly as before

## Next Steps (Phase 3)

1. Implement platform channels for iOS
   - Swift code for CVPixelBuffer extraction
   - Method channel for frame transfer

2. Implement platform channels for Android
   - Kotlin code for SurfaceTexture access
   - Method channel for frame transfer

3. Replace screenshot approach with platform channels
   - Remove hidden video widget
   - Achieve 60 FPS performance

4. Add frame pooling and optimization
   - Reduce memory allocations
   - GPU acceleration where possible

## Testing Checklist

- [x] Image panoramas still work
- [x] Video panorama loads
- [x] Video plays automatically
- [x] Touch controls work with video
- [x] Play/pause works
- [x] Video loops correctly
- [ ] Test with actual 360° video (need sample)
- [ ] Test on iOS device
- [ ] Test on Android device
- [ ] Performance profiling

## Known Issues

1. Sample video is not 360° equirectangular
   - Need to add actual 360° video for proper testing
   - Current video is just for demonstration

2. Frame extraction visible lag
   - Expected with screenshot approach
   - Will be fixed in Phase 3

3. Memory usage higher than optimal
   - Frame caching needed
   - Will be optimized in Phase 3

## Phase 2 Status: ✅ COMPLETE (Testable)

Ready for testing and Phase 3 implementation.
