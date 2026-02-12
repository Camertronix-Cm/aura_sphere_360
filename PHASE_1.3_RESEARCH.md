# Phase 1.3: Research Video Integration

## Video Player Package Analysis

### video_player Package

**Official Flutter Package**: `video_player`
- Maintained by Flutter team
- Supports: Assets, Files, Network URLs
- Platform support: iOS (AVPlayer), Android (ExoPlayer), Web

**Architecture**:
```
VideoPlayerController
  └─ Platform Channel
      ├─ iOS: AVPlayer
      └─ Android: ExoPlayer
```

**Key Components**:

1. **VideoPlayerController**:
   - `VideoPlayerController.asset()`
   - `VideoPlayerController.file()`
   - `VideoPlayerController.network()`
   - `VideoPlayerController.contentUri()` (Android only)

2. **VideoPlayer Widget**:
   - Displays video using `Texture` widget
   - Internally uses `controller.textureId`
   - Renders native video surface

3. **Texture Widget**:
   - Flutter's built-in widget for native surfaces
   - Takes `textureId` parameter
   - Displays SurfaceTexture (Android) or CVPixelBuffer (iOS)
   - High performance, GPU-accelerated

### How video_player Works

```dart
// User code
final controller = VideoPlayerController.network('url');
await controller.initialize();

// VideoPlayer widget internally does:
Widget build(BuildContext context) {
  return Texture(textureId: controller.textureId);
}
```

**Rendering Pipeline**:
1. Native player (AVPlayer/ExoPlayer) decodes video
2. Frames rendered to native surface (SurfaceTexture/CVPixelBuffer)
3. Surface registered with Flutter's TextureRegistry
4. `Texture` widget displays the surface using textureId
5. Flutter composites texture into widget tree

### Critical Finding: textureId Property

✅ **VideoPlayerController exposes `textureId`**:
```dart
class VideoPlayerController {
  int get textureId => _textureId;
}
```

This means we can:
1. Access the native video texture
2. Use it with Flutter's `Texture` widget
3. Potentially access it for custom rendering

## WebRTC Package Analysis

### flutter_webrtc Package

**Community Package**: `flutter_webrtc`
- WebRTC implementation for Flutter
- Supports: Video calls, screen sharing, media streams
- Platform support: iOS, Android, Web, Desktop

**Key Components**:

1. **RTCVideoRenderer**:
   - Displays remote/local video tracks
   - Has `initialize()` and `dispose()` methods
   - Internally uses platform-specific rendering

2. **RTCVideoView Widget**:
   - Wrapper around RTCVideoRenderer
   - Uses PlatformView or Texture depending on platform

3. **MediaStream & VideoTrack**:
   - Represents video stream
   - Can be local (camera) or remote (peer)

### How flutter_webrtc Works

**Two Rendering Approaches**:

#### 1. PlatformView Approach (Hybrid Composition)
```dart
RTCVideoView(
  renderer: _renderer,
  objectFit: RTCVideoViewObjectFit.cover,
)
```
- Embeds native view directly
- Better compatibility
- Slightly lower performance (pre-Android 10)

#### 2. Texture Approach (Virtual Display)
```dart
// On Android:
SurfaceTextureRenderer → TextureRegistry → Texture widget

// On iOS:
CVPixelBuffer → TextureRegistry → Texture widget
```
- Higher performance
- More complex implementation
- Requires platform channels

### RTCVideoRenderer API

```dart
class RTCVideoRenderer {
  int? textureId;  // Available on some platforms
  RTCVideoViewObjectFit objectFit;
  
  Future<void> initialize();
  Future<void> dispose();
  
  // Set video track
  set srcObject(MediaStream? stream);
}
```

### Critical Finding: Frame Access

**Challenge**: RTCVideoRenderer doesn't directly expose frames as `ui.Image`

**Possible Solutions**:

1. **Use textureId** (if available):
   - Access `renderer.textureId`
   - Use with `Texture` widget
   - Similar to video_player approach

2. **Platform Channels** (complex):
   - iOS: Access CVPixelBuffer from RTCVideoTrack
   - Android: Access SurfaceTexture from VideoTrack
   - Convert to ui.Image (expensive)

3. **Screenshot Approach** (fallback):
   - Use `RenderRepaintBoundary` to capture widget
   - Convert to ui.Image
   - Lower performance but works everywhere

## Texture Widget Deep Dive

### Flutter's Texture Widget

```dart
Texture({
  Key? key,
  required int textureId,
  bool freeze = false,
  FilterQuality filterQuality = FilterQuality.low,
})
```

**How it works**:
1. Native code registers a texture with Flutter engine
2. Returns a textureId (integer)
3. `Texture` widget references this ID
4. Flutter composites the native texture into the scene

**Performance**:
- GPU-accelerated
- Zero-copy rendering (on modern devices)
- Efficient for video playback

### TextureRegistry API

```dart
// Platform side (Kotlin/Swift)
// Android:
val textureEntry = textureRegistry.createSurfaceTexture()
val textureId = textureEntry.id()

// iOS:
let textureEntry = textureRegistry.register(texture)
let textureId = textureEntry.textureId
```

## Frame Extraction Research

### Challenge: Converting Texture to ui.Image

**Problem**: 
- `Texture` widget displays native surface
- `flutter_cube` needs `ui.Image` for mesh texture
- No direct conversion available

**Potential Solutions**:

### Solution 1: Use Texture Widget Directly (Recommended)

**Approach**: Modify panorama viewer to use `Texture` instead of `flutter_cube`

**Pros**:
- Native performance
- No frame extraction needed
- Works with video_player and flutter_webrtc
- GPU-accelerated

**Cons**:
- Major architecture change
- Need to implement equirectangular projection differently
- May need custom shaders

**Implementation Strategy**:
```dart
// Instead of flutter_cube with ui.Image texture:
Stack(
  children: [
    // Video texture as background
    Texture(textureId: videoController.textureId),
    
    // Apply equirectangular shader
    ShaderMask(
      shaderCallback: (bounds) => equirectangularShader,
      child: Container(),
    ),
    
    // Touch controls
    GestureDetector(...),
  ],
)
```

### Solution 2: Screenshot-Based Frame Extraction

**Approach**: Capture video widget as image each frame

```dart
Future<ui.Image?> captureVideoFrame() async {
  final boundary = videoKey.currentContext!.findRenderObject() 
      as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  return image;
}
```

**Pros**:
- Works with any widget
- No platform channels needed
- Simple implementation

**Cons**:
- Very expensive (CPU → GPU → CPU)
- Poor performance (10-15 FPS max)
- High memory usage
- Not suitable for 360° video

### Solution 3: Platform Channels for Direct Frame Access

**Approach**: Access native video frames via platform channels

**Android (Kotlin)**:
```kotlin
// Access ExoPlayer frames
val player = exoPlayer
player.videoComponent?.setVideoFrameMetadataListener { ... }

// Or from SurfaceTexture
val surfaceTexture = SurfaceTexture(textureId)
surfaceTexture.setOnFrameAvailableListener { ... }
```

**iOS (Swift)**:
```swift
// Access AVPlayer frames
let output = AVPlayerItemVideoOutput()
let pixelBuffer = output.copyPixelBuffer(
    forItemTime: time,
    itemTimeForDisplay: nil
)
```

**Pros**:
- Direct frame access
- Better performance than screenshots
- Full control over frame processing

**Cons**:
- Complex implementation
- Platform-specific code
- Maintenance burden
- Still requires CPU/GPU transfer

### Solution 4: Custom Shader Approach (Advanced)

**Approach**: Use Flutter's shader support to apply equirectangular projection

```dart
// Load custom fragment shader
final shader = await FragmentProgram.fromAsset('shaders/equirectangular.frag');

// Apply to texture
CustomPaint(
  painter: EquirectangularPainter(
    shader: shader,
    textureId: videoController.textureId,
  ),
)
```

**Pros**:
- GPU-accelerated
- High performance
- Native texture support

**Cons**:
- Requires GLSL knowledge
- Complex shader development
- May not work with flutter_cube

## Performance Considerations

### Frame Rate Requirements

**360° Video Playback**:
- Minimum: 30 FPS
- Recommended: 60 FPS
- Touch response: <16ms (60 FPS)

### Performance Comparison

| Approach | FPS | CPU Usage | GPU Usage | Complexity |
|----------|-----|-----------|-----------|------------|
| Texture + Shader | 60 | Low | Medium | High |
| Screenshot | 10-15 | Very High | High | Low |
| Platform Channels | 30-45 | High | Medium | Very High |
| flutter_cube + ui.Image | 30-60 | Medium | Medium | Medium |

### Memory Usage

**Static Image**: ~10-20 MB (4K equirectangular)
**Video Playback**: 
- Decoder buffer: ~50-100 MB
- Frame cache: ~30-60 MB
- Total: ~100-200 MB

## Recommended Approach for Phase 2

### Strategy: Hybrid Architecture

**For Video Files (video_player)**:

1. **Use Texture Widget Directly**:
   - Access `controller.textureId`
   - Display with `Texture` widget
   - Apply equirectangular projection via shader or CustomPaint

2. **Fallback to flutter_cube**:
   - If shader approach too complex
   - Use screenshot method for prototyping
   - Optimize later with platform channels

**For WebRTC (flutter_webrtc)**:

1. **Use RTCVideoView with Texture**:
   - Access `renderer.textureId`
   - Similar approach to video_player

2. **Platform-Specific Optimization**:
   - Android: SurfaceTextureRenderer
   - iOS: CVPixelBuffer access
   - Implement if performance insufficient

### Implementation Plan

**Phase 2.1**: Create texture provider abstraction
```dart
abstract class PanoramaTextureProvider {
  int? get textureId;  // For Texture widget approach
  Future<ui.Image?> getCurrentFrame();  // For flutter_cube approach
  void addListener(VoidCallback listener);
  void dispose();
}
```

**Phase 2.2**: Implement video provider
```dart
class VideoTextureProvider implements PanoramaTextureProvider {
  final VideoPlayerController controller;
  
  @override
  int? get textureId => controller.textureId;
  
  @override
  Future<ui.Image?> getCurrentFrame() async {
    // Screenshot fallback if needed
    return await captureFrame();
  }
}
```

**Phase 2.3**: Modify PanoramaViewer
- Add `textureId` parameter
- Support both `ui.Image` and `Texture` rendering
- Detect which approach to use

## Alternative: Simpler Approach

### Use Existing Video Player Packages

Instead of integrating video into panorama_viewer, create a wrapper:

```dart
class VideoPanoramaViewer extends StatelessWidget {
  final VideoPlayerController controller;
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Standard video player
        VideoPlayer(controller),
        
        // Overlay with 360° controls
        PanoramaControls(
          onPan: (dx, dy) => adjustView(dx, dy),
          onZoom: (scale) => adjustZoom(scale),
        ),
      ],
    );
  }
}
```

**Pros**:
- Much simpler
- Faster to implement (1 week vs 3-4 weeks)
- Leverages existing video infrastructure

**Cons**:
- Not true 360° projection
- Limited to flat video with pan/zoom
- Doesn't use equirectangular mapping

## Key Findings Summary

### ✅ What We Learned

1. **video_player exposes textureId**:
   - Can access native video texture
   - Use with `Texture` widget
   - High performance

2. **flutter_webrtc has similar architecture**:
   - Also uses texture-based rendering
   - RTCVideoRenderer has textureId
   - Platform-specific implementations

3. **Texture → ui.Image conversion is expensive**:
   - No direct API
   - Screenshot approach too slow
   - Platform channels complex

4. **Shader-based approach most promising**:
   - GPU-accelerated
   - Native texture support
   - Requires GLSL knowledge

### ⚠️ Challenges Identified

1. **flutter_cube DOES accept ui.Image**:
   - `mesh.texture = ui.Image` (line 347)
   - `scene.texture = ui.Image` (line 351)
   - `scene.updateTexture()` updates GPU texture
   - This means we CAN update the texture dynamically!

2. **Frame extraction performance**:
   - Screenshot: Too slow (10-15 FPS)
   - Platform channels: Complex
   - Direct texture: Requires shader

3. **Cross-platform consistency**:
   - iOS and Android have different APIs
   - WebRTC adds another layer
   - Need abstraction layer

### 🎯 Recommended Path Forward - CORRECTED

**IMPORTANT REALIZATION**: flutter_cube DOES support dynamic texture updates!

Looking at the code:
```dart
void _updateTexture(ImageInfo imageInfo, bool synchronousCall) {
  surface?.mesh.texture = imageInfo.image;  // ui.Image
  scene!.texture = imageInfo.image;         // ui.Image
  scene!.updateTexture();                   // Updates GPU
}
```

This means we CAN use flutter_cube with video! We just need to:
1. Extract video frames as `ui.Image`
2. Call `surface.mesh.texture = newFrame`
3. Call `scene.updateTexture()`
4. Do this every frame (30-60 FPS)

**Revised Options:**

**Option A: Keep flutter_cube + Extract Frames (RECOMMENDED)**
- Keep existing flutter_cube architecture
- Extract video frames as ui.Image
- Update mesh.texture each frame
- Call scene.updateTexture() in animation loop
- Minimal architecture changes
- 2-3 weeks

**Option B: Custom Shader Approach**
- Replace flutter_cube entirely
- Use Texture widget + GLSL shader
- More complex but potentially better performance
- 3-4 weeks

**Option C: Simple Wrapper**
- Don't modify panorama_viewer core
- Create separate video panorama widget
- Not true 360° projection
- 1 week

## Next Steps (Phase 2)

Based on CORRECTED research, recommend:

1. **Go with Option A (Keep flutter_cube + Extract Frames)**:
   - flutter_cube ALREADY supports dynamic texture updates
   - Just need to extract video frames as ui.Image
   - Update texture in existing animation loop
   - Minimal architecture changes

2. **The key challenge is frame extraction**:
   - Screenshot approach: Simple but slow (10-15 FPS)
   - Platform channels: Complex but faster (30-60 FPS)
   - Start with screenshot for prototype
   - Optimize with platform channels if needed

3. **Implementation approach**:
   ```dart
   void _updateView() {
     // Existing animation logic...
     
     // NEW: Update video frame
     if (textureProvider is VideoTextureProvider) {
       final frame = await textureProvider.getCurrentFrame();
       if (frame != null) {
         surface.mesh.texture = frame;
         scene.texture = frame;
         scene.updateTexture();
       }
     }
     
     // Existing rendering...
   }
   ```

## Files for Phase 2

Will need to create:
- `lib/src/texture_provider.dart` - Abstraction layer
- `lib/src/video_texture_provider.dart` - Video implementation
- `lib/src/webrtc_texture_provider.dart` - WebRTC implementation
- `lib/src/image_texture_provider.dart` - Existing image logic

## Phase 1.3 Complete ✅

Ready to proceed to Phase 2: Core Architecture Changes
