# Phase 3: Platform Channels Implementation

## Overview

Phase 3 implements native platform channels for direct video frame access, replacing the screenshot approach with high-performance 60 FPS frame extraction.

## Architecture

```
Flutter (Dart)
  ↓
PlatformVideoTextureProvider
  ↓
Method Channel / Event Channel
  ↓
Native Code (Swift/Kotlin)
  ↓
AVPlayer (iOS) / ExoPlayer (Android)
  ↓
Direct Frame Access (CVPixelBuffer / SurfaceTexture)
```

## Files Created

### Dart Layer
- `lib/src/platform_video_texture_provider.dart` - Platform channel interface

### iOS Layer
- `ios/Classes/PanoramaViewerPlugin.swift` - Main plugin implementation
- `ios/Classes/SwiftPanoramaViewerPlugin.swift` - Plugin registration
- `ios/panorama_viewer.podspec` - CocoaPods specification

### Android Layer
- `android/src/main/kotlin/com/camertronix/panorama_viewer/PanoramaViewerPlugin.kt` - Plugin implementation
- `android/src/main/AndroidManifest.xml` - Android manifest
- `android/build.gradle` - Build configuration

## Communication Protocol

### Method Channel: `panorama_viewer/video_frames`

**Methods:**

1. **registerVideoPlayer**
   - Input: `{ textureId: int }`
   - Output: `{ success: bool, message: string }`
   - Registers a video player for frame extraction

2. **unregisterVideoPlayer**
   - Input: `{ textureId: int }`
   - Output: `{ success: bool }`
   - Unregisters and cleans up resources

3. **getCurrentFrame**
   - Input: `{ textureId: int }`
   - Output: `{ width: int, height: int, bytes: Uint8List }` or `null`
   - Gets the current video frame

### Event Channel: `panorama_viewer/video_frames_stream`

**Stream Events:**
```dart
{
  width: int,
  height: int,
  bytes: Uint8List  // PNG or JPEG encoded frame
}
```

Streams video frames at 60 FPS from native side to Flutter.

## iOS Implementation Details

### Frame Extraction Strategy

```swift
// 1. Get AVPlayer from video_player plugin
// 2. Create AVPlayerItemVideoOutput
let output = AVPlayerItemVideoOutput()
player.currentItem?.add(output)

// 3. Use CADisplayLink for 60 FPS updates
displayLink = CADisplayLink(target: self, selector: #selector(frameUpdate))
displayLink?.preferredFramesPerSecond = 60

// 4. Extract CVPixelBuffer
if output.hasNewPixelBuffer(forItemTime: time) {
    let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
    // Convert to PNG/JPEG and send to Flutter
}
```

### Key Classes

- **PanoramaViewerPlugin**: Main plugin coordinator
- **VideoFrameExtractor**: Handles frame extraction per video player
- Uses CADisplayLink for precise 60 FPS timing

## Android Implementation Details

### Frame Extraction Strategy

```kotlin
// 1. Get ExoPlayer from video_player plugin
// 2. Set up VideoFrameMetadataListener
player.videoComponent?.setVideoFrameMetadataListener { 
    presentationTimeUs, releaseTimeNs, format, mediaFormat ->
    // Access frame from SurfaceTexture
}

// 3. Or use SurfaceTexture callback
surfaceTexture.setOnFrameAvailableListener {
    // Extract frame as Bitmap
    val bitmap = textureView.bitmap
    // Compress and send to Flutter
}
```

### Key Classes

- **PanoramaViewerPlugin**: Main plugin coordinator
- **VideoFrameExtractor**: Handles frame extraction with Handler for 60 FPS
- Uses Handler.postDelayed for frame timing

## Current Status

### ✅ Completed
- Platform channel architecture
- Method channel setup
- Event channel setup
- Plugin registration (iOS & Android)
- iOS native frame extraction (complete implementation)
- Fixed API access: Using `playerId` instead of non-existent `textureId`

### 🚧 TODO (Next Steps)

#### iOS
1. ✅ Access AVPlayer instance from video_player plugin (using playerId)
2. ✅ Implement AVPlayerItemVideoOutput integration
3. ✅ Convert CVPixelBuffer to JPEG bytes
4. Test on device with actual video
5. Optimize memory management

#### Android
1. Access ExoPlayer instance from video_player plugin (using playerId)
2. Implement VideoFrameMetadataListener or SurfaceTexture
3. Convert frame to Bitmap and compress
4. Optimize memory management

#### Both Platforms
1. Frame pooling to reduce allocations
2. GPU-based image encoding
3. Error handling and fallback
4. Performance profiling

## Integration with PanoramaViewer

The platform channel provider will be used automatically when available:

```dart
// In _initializeTextureProvider():
if (widget.videoPlayerController != null) {
  try {
    // Try platform channels first
    textureProvider = PlatformVideoTextureProvider(widget.videoPlayerController!);
    await textureProvider!.initialize();
  } catch (e) {
    // Fall back to screenshot approach
    textureProvider = VideoTextureProvider(widget.videoPlayerController!);
    await textureProvider!.initialize();
  }
}
```

## Performance Targets

| Metric | Phase 2 (Screenshot) | Phase 3 (Platform Channels) |
|--------|---------------------|----------------------------|
| Frame Rate | 25-30 FPS | 60 FPS |
| CPU Usage | High | Low-Medium |
| Memory | ~200 MB | ~100 MB |
| Latency | 50-100ms | <16ms |
| Max Resolution | 1920x1080 | 4K+ |

## Testing

### Manual Testing
```bash
cd example
flutter run
# Navigate to Example 6 - Video Panorama
# Should see improved performance
```

### Check Platform Channel
```dart
// Add to example app
print('Using platform channels: ${textureProvider is PlatformVideoTextureProvider}');
```

### Performance Profiling
```bash
flutter run --profile
# Use DevTools to check:
# - Frame rate (should be 60 FPS)
# - Memory usage (should be lower)
# - CPU usage (should be lower)
```

## Known Limitations

1. **Requires video_player internals**: Uses `playerId` property (marked `@visibleForTesting`)
2. **Platform-specific**: Different implementation for iOS/Android
3. **Maintenance**: Must keep up with video_player plugin changes
4. **AVPlayer access**: Requires reflection to access AVPlayer instance from video_player plugin

## Alternative Approaches

If accessing video_player internals is too complex:

1. **Fork video_player**: Create custom version with frame access API
2. **Use texture ID directly**: Access the native texture without frame extraction
3. **Custom video player**: Build our own video player with frame access

## Next Phase

**Phase 4**: WebRTC Integration
- Similar platform channel approach
- Access RTCVideoRenderer frames
- Support for live streaming

## Resources

- [Flutter Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [AVPlayerItemVideoOutput](https://developer.apple.com/documentation/avfoundation/avplayeritemvideooutput)
- [ExoPlayer VideoFrameMetadataListener](https://exoplayer.dev/doc/reference/com/google/android/exoplayer2/video/VideoFrameMetadataListener.html)
- [video_player source](https://github.com/flutter/packages/tree/main/packages/video_player)

## Phase 3 Status: 🚧 READY FOR TESTING

Platform channel infrastructure complete. iOS native implementation complete. Ready for device testing to verify AVPlayer access.

## API Resolution

**Issue:** VideoPlayerController doesn't expose `textureId` property
**Solution:** Use `playerId` property instead (marked `@visibleForTesting` but accessible)
**Status:** ✅ Resolved - Code updated to use `playerId` throughout
