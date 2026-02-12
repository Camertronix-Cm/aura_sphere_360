# Panorama Viewer Fork Plan
## Adding Video & WebRTC Support to panorama_viewer

### Overview
Fork the `panorama_viewer` package to add support for video playback (local files, network streams, WebRTC) while maintaining existing image support. This will create a unified 360° viewer for the entire Aura360 app.

---

## Phase 1: Setup & Analysis (1-2 days)

### 1.1 Fork the Repository
- [x] Fork `panorama_viewer` on GitHub
- [x] Clone to local development
- [x] Create new branch: `feature/video-support`
- [x] Review existing codebase structure

### 1.2 Analyze Current Implementation
- [x] Study `PanoramaViewer` widget architecture
- [x] Understand `CustomPainter` rendering logic
- [x] Identify equirectangular projection code
- [x] Document touch/sensor control implementation
- [x] Map out widget tree and state management

### 1.3 Research Video Integration
- [x] Test `video_player` package frame extraction
- [x] Test `flutter_webrtc` texture access
- [x] Investigate `Texture` widget for video rendering
- [x] Research performance optimization techniques

---

## Phase 2: Core Architecture Changes (3-4 days)

### 2.1 Create New Widget Structure
```dart
// New unified widget
class PanoramaViewer extends StatefulWidget {
  // Existing: Image support
  final Widget? child;
  final ImageProvider? imageProvider;
  
  // New: Video support
  final VideoPlayerController? videoController;
  
  // New: WebRTC support
  final RTCVideoRenderer? webrtcRenderer;
  
  // New: Raw texture support
  final int? textureId;
  
  // Existing: Controls
  final SensorControl sensorControl;
  final double animSpeed;
  
  PanoramaViewer({
    this.child,
    this.imageProvider,
    this.videoController,
    this.webrtcRenderer,
    this.textureId,
    this.sensorControl = SensorControl.orientation,
    this.animSpeed = 0.0,
  });
}
```

### 2.2 Implement Source Detection
- [ ] Add source type enum (Image, Video, WebRTC, Texture)
- [ ] Create source validator (ensure only one source provided)
- [ ] Add error handling for invalid configurations

### 2.3 Create Texture Provider Interface
```dart
abstract class PanoramaTextureProvider {
  Future<ui.Image> getCurrentFrame();
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
  void dispose();
}

class ImageTextureProvider implements PanoramaTextureProvider { }
class VideoTextureProvider implements PanoramaTextureProvider { }
class WebRTCTextureProvider implements PanoramaTextureProvider { }
```

---

## Phase 3: Video Player Integration (3-4 days)

### 3.1 Implement VideoTextureProvider
- [ ] Initialize `VideoPlayerController`
- [ ] Extract video frames as `ui.Image`
- [ ] Handle frame updates (30-60 FPS)
- [ ] Implement play/pause/seek controls
- [ ] Add buffering state handling

### 3.2 Frame Extraction Logic
```dart
class VideoTextureProvider implements PanoramaTextureProvider {
  final VideoPlayerController controller;
  ui.Image? _currentFrame;
  
  @override
  Future<ui.Image> getCurrentFrame() async {
    // Extract current video frame
    // Convert to ui.Image
    // Cache for rendering
  }
  
  @override
  void addListener(VoidCallback listener) {
    controller.addListener(listener);
  }
}
```

### 3.3 Performance Optimization
- [ ] Implement frame caching
- [ ] Add frame skip logic for low-end devices
- [ ] Optimize texture upload to GPU
- [ ] Profile memory usage

---

## Phase 4: WebRTC Integration (4-5 days)

### 4.1 Implement WebRTCTextureProvider
- [ ] Initialize `RTCVideoRenderer`
- [ ] Access video track texture
- [ ] Handle stream state changes
- [ ] Implement reconnection logic

### 4.2 Platform Channel Setup (if needed)
```dart
// iOS: Access CVPixelBuffer
// Android: Access SurfaceTexture

class WebRTCTextureProvider implements PanoramaTextureProvider {
  final RTCVideoRenderer renderer;
  
  @override
  Future<ui.Image> getCurrentFrame() async {
    // Platform-specific texture extraction
    if (Platform.isIOS) {
      return _extractFrameIOS();
    } else {
      return _extractFrameAndroid();
    }
  }
}
```

### 4.3 Native Code (if required)
- [ ] iOS: Swift code to extract CVPixelBuffer
- [ ] Android: Kotlin code to extract SurfaceTexture
- [ ] Create method channels
- [ ] Test on both platforms

---

## Phase 5: Rendering Pipeline Update (2-3 days)

### 5.1 Modify CustomPainter
```dart
class PanoramaPainter extends CustomPainter {
  final PanoramaTextureProvider textureProvider;
  
  @override
  void paint(Canvas canvas, Size size) {
    final frame = textureProvider.getCurrentFrame();
    // Apply equirectangular projection
    // Render to sphere
  }
  
  @override
  bool shouldRepaint(PanoramaPainter oldDelegate) {
    // Repaint on every frame for video
    return textureProvider is VideoTextureProvider ||
           textureProvider is WebRTCTextureProvider;
  }
}
```

### 5.2 Frame Update Loop
- [ ] Implement efficient repaint triggering
- [ ] Add FPS limiting (30/60 FPS options)
- [ ] Handle pause/resume states
- [ ] Optimize for battery life

---

## Phase 6: Controls & Features (2-3 days)

### 6.1 Video Controls
- [ ] Play/pause button overlay
- [ ] Seek bar for video files
- [ ] Volume control
- [ ] Playback speed control
- [ ] Loop option

### 6.2 Touch Gestures (maintain existing)
- [ ] Pan (rotate view)
- [ ] Pinch (zoom)
- [ ] Double-tap (reset view)
- [ ] Ensure smooth interaction during video playback

### 6.3 Sensor Control (maintain existing)
- [ ] Gyroscope orientation
- [ ] Accelerometer support
- [ ] Compass integration
- [ ] Test with video playback

---

## Phase 7: Testing & Optimization (3-4 days)

### 7.1 Unit Tests
- [ ] Test source detection logic
- [ ] Test texture provider implementations
- [ ] Test frame extraction
- [ ] Test error handling

### 7.2 Integration Tests
- [ ] Test with local video files
- [ ] Test with network streams
- [ ] Test with WebRTC streams
- [ ] Test with static images (regression)

### 7.3 Performance Testing
- [ ] Profile CPU usage
- [ ] Profile memory usage
- [ ] Profile GPU usage
- [ ] Test on low-end devices
- [ ] Test battery drain

### 7.4 Platform Testing
- [ ] Test on iOS (multiple versions)
- [ ] Test on Android (multiple versions)
- [ ] Test on tablets
- [ ] Test on different screen sizes

---

## Phase 8: Documentation & Examples (2 days)

### 8.1 API Documentation
- [ ] Document all new parameters
- [ ] Add code examples for each source type
- [ ] Create migration guide from original package
- [ ] Document performance considerations

### 8.2 Example App
```dart
// Example 1: Static image (existing)
PanoramaViewer(
  child: Image.asset('assets/360_photo.jpg'),
)

// Example 2: Local video file
PanoramaViewer(
  videoController: VideoPlayerController.file(
    File('/path/to/video.mp4'),
  ),
)

// Example 3: WebRTC stream
PanoramaViewer(
  webrtcRenderer: rtcRenderer,
)

// Example 4: Network video
PanoramaViewer(
  videoController: VideoPlayerController.network(
    'https://example.com/360_video.mp4',
  ),
)
```

### 8.3 README Updates
- [ ] Update feature list
- [ ] Add installation instructions
- [ ] Add usage examples
- [ ] Add troubleshooting guide
- [ ] Add performance tips

---

## Phase 9: Integration with Aura360 App (2-3 days)

### 9.1 Replace Existing Viewers
- [ ] Replace `Demo360Player` with forked viewer
- [ ] Update `WebRTCPreviewWidget` to use forked viewer
- [ ] Update `LittlePlanetCubeViewer` if needed
- [ ] Test all capture modes

### 9.2 Media Gallery Integration
- [ ] Display captured photos with 360° viewer
- [ ] Display recorded videos with 360° viewer
- [ ] Add playback controls
- [ ] Test with real captured media

### 9.3 Live Preview Integration
- [ ] Use forked viewer for WebRTC preview
- [ ] Ensure smooth touch controls during live view
- [ ] Test with all capture modes (Video, Little Planet, Timelapse)

---

## Phase 10: Publishing & Maintenance (1-2 days)

### 10.1 Package Publishing
- [ ] Update pubspec.yaml version
- [ ] Update CHANGELOG.md
- [ ] Create GitHub release
- [ ] Publish to pub.dev (optional, or keep as git dependency)

### 10.2 Aura360 Integration
- [ ] Update pubspec.yaml to use forked package
- [ ] Test full app integration
- [ ] Update app documentation
- [ ] Create demo video

---

## Timeline Summary

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| 1. Setup & Analysis | 1-2 days | None |
| 2. Core Architecture | 3-4 days | Phase 1 |
| 3. Video Integration | 3-4 days | Phase 2 |
| 4. WebRTC Integration | 4-5 days | Phase 2 |
| 5. Rendering Pipeline | 2-3 days | Phase 3, 4 |
| 6. Controls & Features | 2-3 days | Phase 5 |
| 7. Testing & Optimization | 3-4 days | Phase 6 |
| 8. Documentation | 2 days | Phase 7 |
| 9. Aura360 Integration | 2-3 days | Phase 8 |
| 10. Publishing | 1-2 days | Phase 9 |

**Total Estimated Time: 3-4 weeks**

---

## Technical Challenges & Solutions

### Challenge 1: Frame Extraction Performance
**Problem:** Extracting video frames at 30-60 FPS is CPU intensive  
**Solution:** 
- Use hardware-accelerated decoding
- Implement frame caching
- Add FPS limiting options
- Use `Texture` widget instead of `CustomPainter` where possible

### Challenge 2: WebRTC Texture Access
**Problem:** `flutter_webrtc` doesn't expose raw texture directly  
**Solution:**
- Use platform channels to access native texture
- iOS: Access `CVPixelBuffer` from `RTCVideoTrack`
- Android: Access `SurfaceTexture` from video track
- Fallback: Screenshot-based approach (lower performance)

### Challenge 3: Memory Management
**Problem:** Video frames consume significant memory  
**Solution:**
- Implement frame pooling
- Limit cache size
- Release frames immediately after rendering
- Monitor memory usage and adjust dynamically

### Challenge 4: Cross-Platform Consistency
**Problem:** Different behavior on iOS vs Android  
**Solution:**
- Abstract platform-specific code behind interfaces
- Extensive testing on both platforms
- Platform-specific optimizations where needed
- Fallback implementations for unsupported features

---

## Success Criteria

✅ **Functional Requirements:**
- [ ] Display static 360° images (existing functionality maintained)
- [ ] Play local 360° video files with touch controls
- [ ] Stream WebRTC 360° video with touch controls
- [ ] Support network video URLs
- [ ] Maintain gyroscope/sensor controls
- [ ] Smooth 30+ FPS playback

✅ **Performance Requirements:**
- [ ] <5% CPU usage increase vs static images
- [ ] <50MB memory overhead for video playback
- [ ] <10% battery drain increase
- [ ] Smooth 60 FPS touch response

✅ **Quality Requirements:**
- [ ] No visual artifacts in 360° projection
- [ ] Smooth video playback without stuttering
- [ ] Responsive touch controls during playback
- [ ] Graceful error handling

---

## Alternative: Simpler Approach

If the full fork is too complex, consider a **hybrid approach**:

1. **Keep `panorama_viewer` for images only**
2. **Create separate `video_panorama_viewer` package**
3. **Use composition instead of modification**

```dart
class VideoPanoramaViewer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Video player (flat)
        VideoPlayer(controller),
        
        // Overlay with 360° projection shader
        ShaderMask(
          shaderCallback: (bounds) => equirectangularShader,
          child: Container(),
        ),
        
        // Touch controls
        GestureDetector(...),
      ],
    );
  }
}
```

This is **faster to implement** (1-2 weeks) but **less integrated** than a full fork.

---

## Next Steps

1. **Decision:** Full fork vs Hybrid approach?
2. **Setup:** Fork repository and create development branch
3. **Prototype:** Build minimal video support proof-of-concept
4. **Evaluate:** Test performance and feasibility
5. **Iterate:** Implement full feature set based on prototype learnings

---

## Resources

- **panorama_viewer source:** https://pub.dev/packages/panorama_viewer
- **video_player docs:** https://pub.dev/packages/video_player
- **flutter_webrtc docs:** https://pub.dev/packages/flutter_webrtc
- **Equirectangular projection:** https://en.wikipedia.org/wiki/Equirectangular_projection
- **Flutter Texture widget:** https://api.flutter.dev/flutter/widgets/Texture-class.html
