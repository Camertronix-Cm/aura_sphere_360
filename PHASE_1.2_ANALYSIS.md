# Phase 1.2: Analyze Current Implementation

## Widget Architecture Analysis

### PanoramaViewer Widget Structure

```dart
PanoramaViewer (StatefulWidget)
  └─ PanoramaState (State with SingleTickerProviderStateMixin)
      ├─ AnimationController (_controller)
      ├─ Scene (from flutter_cube)
      ├─ Object (surface with sphere mesh)
      └─ GestureDetector (for touch controls)
          └─ Stack
              ├─ Cube widget (3D rendering)
              └─ StreamBuilder (hotspots overlay)
```

### Key Properties

**Current Image Support:**
- `Image? child` - The only content source currently
- Extracts `ImageProvider` from the Image widget
- Resolves to `ImageStream` → `ImageInfo` → `ui.Image`

**Control Properties:**
- `latitude`, `longitude`, `zoom` - Initial view position
- `minLatitude`, `maxLatitude`, `minLongitude`, `maxLongitude` - View constraints
- `minZoom`, `maxZoom` - Zoom constraints
- `sensitivity` - Gesture sensitivity
- `animSpeed` - Auto-rotation speed
- `animReverse` - Reverse on boundary
- `interactive` - Enable/disable touch
- `sensorControl` - Gyroscope/orientation control

**Mesh Properties:**
- `latSegments` (default: 32) - Vertical sphere divisions
- `lonSegments` (default: 64) - Horizontal sphere divisions
- `croppedArea`, `croppedFullWidth`, `croppedFullHeight` - Partial sphere support

**Callbacks:**
- `onViewChanged(longitude, latitude, tilt)` - View updates
- `onTap(longitude, latitude, tilt)` - Tap events
- `onLongPressStart/MoveUpdate/End` - Long press events
- `onImageLoad()` - Texture loaded callback

**Advanced Features:**
- `hotspots` - List of positioned widgets in 3D space
- `panoramaController` - Programmatic control

## CustomPainter / Rendering Logic

### Rendering Pipeline (via flutter_cube)

The package doesn't use CustomPainter directly. Instead, it uses `flutter_cube`:

1. **Scene Setup** (`_onSceneCreated`):
   ```dart
   - Create Scene with camera settings
   - Generate sphere Mesh (vertices, texcoords, indices)
   - Create Object with mesh
   - Load texture from ImageProvider
   - Add object to scene.world
   ```

2. **Texture Loading** (`_loadTexture`, `_updateTexture`):
   ```dart
   - ImageProvider → ImageStream
   - Listen for ImageInfo
   - Extract ui.Image
   - Apply to mesh.texture
   - Call scene.updateTexture()
   ```

3. **Animation Loop** (`_updateView`):
   ```dart
   - Called by AnimationController (60 FPS)
   - Updates camera position/rotation
   - Applies damping to deltas
   - Handles sensor orientation
   - Calls scene.update()
   - Triggers StreamController for hotspots
   ```

4. **Rendering**:
   - `Cube` widget from flutter_cube handles actual rendering
   - Uses OpenGL/Metal under the hood
   - Renders scene to canvas

### Sphere Mesh Generation

`generateSphereMesh()` creates the 3D sphere:
- Generates vertices in spherical coordinates
- Creates texture coordinates (UV mapping)
- Builds triangle indices for faces
- Supports cropped equirectangular images
- Returns `Mesh` object with texture

**Key insight**: The mesh is static, only the texture and camera move.

## Equirectangular Projection

### Current Implementation

The projection is handled by:
1. **Mesh UV Mapping**: Texture coordinates map equirectangular image to sphere
2. **Sphere Geometry**: Standard sphere with configurable segments
3. **Camera Inside Sphere**: Camera at center looking outward
4. **Texture Wrapping**: Image wraps around sphere seamlessly

### Projection Math

```dart
// In generateSphereMesh():
for (int y = 0; y <= latSegments; ++y) {
  final double tv = y / latSegments;
  final double v = (croppedArea.top + croppedArea.height * tv) / croppedFullHeight;
  final double sv = sin(v * pi);
  final double cv = cos(v * pi);
  
  for (int x = 0; x <= lonSegments; ++x) {
    final double tu = x / lonSegments;
    final double u = (croppedArea.left + croppedArea.width * tu) / croppedFullWidth;
    
    // Vertex position
    vertices[i] = Vector3(
      radius * cos(u * pi * 2.0) * sv,
      radius * cv,
      radius * sin(u * pi * 2.0) * sv
    );
    
    // Texture coordinate
    texcoords[i] = Offset(tu, 1.0 - tv);
  }
}
```

**Key insight**: Projection is baked into mesh geometry, not computed per-frame.

## Touch/Sensor Control Implementation

### Touch Gestures

**Scale Gesture** (pan + pinch):
```dart
_handleScaleStart(details):
  - Store initial focal point
  - Reset zoom reference

_handleScaleUpdate(details):
  - Calculate offset delta
  - Update latitudeDelta (vertical pan)
  - Update longitudeDelta (horizontal pan)
  - Update zoomDelta (pinch)
  - Start animation controller
```

**Tap Gestures**:
```dart
_handleTapUp(details):
  - Convert screen position to lat/lon
  - Call onTap callback

_handleLongPress*:
  - Similar to tap but for long press events
```

**Position to Lat/Lon Conversion**:
```dart
positionToLatLon(x, y):
  1. Transform viewport coords to NDC (-1 to 1)
  2. Create projection matrix
  3. Apply inverse projection
  4. Apply perspective division
  5. Get rotation from vectors
  6. Extract euler angles
```

### Sensor Control

**Orientation Modes**:
1. `SensorControl.none` - No sensors
2. `SensorControl.orientation` - Gyroscope + accelerometer
3. `SensorControl.absoluteOrientation` - Magnetometer + accelerometer (north-aligned)

**Implementation**:
```dart
_updateSensorControl():
  - Subscribe to motion sensor streams (60 FPS)
  - Update orientation Vector3 (yaw, pitch, roll)
  - Apply to camera in _updateView()
  - Handle screen rotation
```

**Sensor Integration in _updateView()**:
```dart
- Create quaternion from screen orientation
- Apply device orientation quaternion
- Rotate to latitude zero
- Clamp to min/max bounds
- Apply manual rotation deltas
- Update camera target and up vectors
```

### Damping & Animation

**Smooth Motion**:
```dart
_dampingFactor = 0.05

latitudeRad += latitudeDelta * _dampingFactor * sensitivity
latitudeDelta *= 1 - _dampingFactor * sensitivity
```

**Auto-rotation**:
```dart
longitudeDelta += 0.001 * _animSpeed
```

**Animation Controller**:
- 60 second duration (effectively infinite)
- Repeats continuously when needed
- Stops when deltas < 0.001 and no auto-rotation

## State Management

### State Variables

**View State**:
- `latitudeRad`, `longitudeRad` - Current view direction
- `latitudeDelta`, `longitudeDelta`, `zoomDelta` - Motion deltas
- `_lastFocalPoint`, `_lastZoom` - Gesture tracking

**3D Objects**:
- `scene` - flutter_cube Scene
- `surface` - Object with sphere mesh

**Sensors**:
- `orientation` - Vector3 from sensors
- `screenOrientationRad` - Device rotation
- `_orientationSubscription`, `_screenOrientSubscription` - Stream subscriptions

**Animation**:
- `_controller` - AnimationController
- `_animSpeed` - Current rotation speed
- `_animateDirection` - Rotation direction (1 or -1)

**Texture**:
- `_imageStream` - ImageStream from ImageProvider
- `_streamController` - For hotspot updates

### Lifecycle

**initState()**:
1. Initialize view angles from props
2. Create stream controller
3. Setup sensor control
4. Create animation controller
5. Start animation if needed

**dispose()**:
1. Remove image listener
2. Cancel sensor subscriptions
3. Dispose animation controller
4. Close stream controller

**didUpdateWidget()**:
1. Regenerate mesh if segments/crop changed
2. Reload texture if image changed
3. Update sensor control if changed

## PanoramaController

### API

**Setters** (trigger notifyListeners):
- `setZoom(double zoom)` - Animate to zoom level
- `setView(double latitude, double longitude)` - Animate to position
- `setAnimSpeed(double speed)` - Change rotation speed

**Getters** (read current state):
- `getZoom()` - Current zoom level
- `getLatitude()` - Current latitude
- `getLongitude()` - Current longitude

### Implementation Pattern

```dart
// Controller stores command
void setZoom(double zoom) {
  _zoom = zoom;
  _type = _SetType._setZoom;
  notifyListeners();
}

// State listens and executes
void _panoramaControllerFunctions() {
  switch (controller._type) {
    case _SetType._setZoom:
      _setZoom(controller._zoom);
      break;
    // ...
  }
}

// Execution updates deltas
void _setZoom(double zoomLevel) {
  zoomDelta = zoomLevel - scene.camera.zoom;
  if (!_controller.isAnimating) {
    _controller.reset();
    _controller.repeat();
  }
}
```

## Dependencies Analysis

### flutter_cube (v0.1.1)

**What it provides**:
- `Cube` widget - 3D rendering widget
- `Scene` - 3D scene with camera
- `Object` - 3D object with mesh
- `Mesh` - Geometry (vertices, texcoords, indices, texture)
- `Vector3`, `Vector4`, `Matrix4`, `Quaternion` - Math utilities

**How it's used**:
- Renders the 3D sphere
- Handles texture mapping
- Provides camera controls
- Manages 3D transformations

**Limitations for video**:
- Designed for static textures
- No built-in frame update mechanism
- May need to call `scene.updateTexture()` frequently

### dchs_motion_sensors (v2.0.1)

**What it provides**:
- `motionSensors.orientation` - Gyroscope + accelerometer
- `motionSensors.absoluteOrientation` - Magnetometer + accelerometer
- `motionSensors.screenOrientation` - Device rotation
- Update interval control

**How it's used**:
- Provides device orientation data
- Updates at 60 FPS
- Converts to yaw/pitch/roll

**Video impact**:
- Should work unchanged with video
- No modifications needed

## Example Usage Patterns

### Minimal Example
```dart
PanoramaViewer(
  child: Image.asset('assets/panorama.jpg'),
)
```

### With Controls
```dart
PanoramaViewer(
  animSpeed: 0.1,
  sensorControl: SensorControl.orientation,
  child: Image.asset('assets/panorama.jpg'),
)
```

### With Hotspots
```dart
PanoramaViewer(
  hotspots: [
    Hotspot(
      latitude: -15.0,
      longitude: -129.0,
      width: 90,
      height: 80,
      widget: MyButton(),
    ),
  ],
  child: Image.asset('assets/panorama.jpg'),
)
```

### With Controller
```dart
final controller = PanoramaController();

PanoramaViewer(
  panoramaController: controller,
  child: Image.asset('assets/panorama.jpg'),
)

// Later:
controller.setZoom(2.0);
controller.setView(45.0, 90.0);
```

## Key Findings for Video Integration

### ✅ What Works Well

1. **Animation Loop Already Exists**:
   - `_updateView()` runs at 60 FPS
   - Perfect for video frame updates
   - Just need to update texture each frame

2. **Texture Update Mechanism**:
   - `_updateTexture()` already handles texture changes
   - `scene.updateTexture()` updates GPU texture
   - Can be called repeatedly

3. **Touch/Sensor Controls**:
   - Completely independent of texture source
   - Will work unchanged with video
   - Well-implemented and smooth

4. **State Management**:
   - Clean separation of concerns
   - Easy to add new texture sources
   - Controller pattern works well

### ⚠️ Challenges Identified

1. **Static Texture Assumption**:
   - Current: Load once, render forever
   - Video: Load every frame (30-60 FPS)
   - Need continuous texture updates

2. **ImageProvider Dependency**:
   - Tightly coupled to Flutter's Image widget
   - VideoPlayerController doesn't provide ImageProvider
   - Need abstraction layer

3. **Frame Extraction**:
   - `video_player` doesn't expose raw frames
   - May need platform channels
   - Performance critical (30-60 FPS)

4. **Memory Management**:
   - Static image: One texture in memory
   - Video: Continuous frame allocation
   - Need frame pooling/recycling

5. **flutter_cube Limitations**:
   - Not designed for dynamic textures
   - May have performance issues
   - Need to test texture update frequency

### 🎯 Recommended Approach

**Phase 2 Strategy**:

1. **Create Texture Provider Abstraction**:
   ```dart
   abstract class PanoramaTextureProvider {
     Future<ui.Image?> getCurrentFrame();
     void addListener(VoidCallback listener);
     void removeListener(VoidCallback listener);
     void dispose();
   }
   ```

2. **Implement Providers**:
   - `ImageTextureProvider` - Wrap existing image logic
   - `VideoTextureProvider` - Extract frames from video
   - `WebRTCTextureProvider` - Extract frames from WebRTC

3. **Modify PanoramaViewer**:
   - Add new parameters (videoController, webrtcRenderer)
   - Detect source type
   - Use appropriate provider
   - Update texture in animation loop

4. **Frame Update Strategy**:
   ```dart
   void _updateView() {
     // Existing animation logic...
     
     // NEW: Update video frame
     if (textureProvider is VideoTextureProvider) {
       textureProvider.getCurrentFrame().then((frame) {
         if (frame != null) {
           surface.mesh.texture = frame;
           scene.updateTexture();
         }
       });
     }
     
     // Existing rendering...
   }
   ```

## Next Steps (Phase 1.3)

1. **Research video_player frame extraction**:
   - Test if texture ID can be accessed
   - Measure frame extraction performance
   - Determine if platform channels needed

2. **Research flutter_webrtc texture access**:
   - Check RTCVideoRenderer API
   - Test texture extraction
   - Evaluate platform channel requirements

3. **Prototype texture provider**:
   - Build simple abstraction
   - Test with static image
   - Validate architecture

## Files Modified in Phase 1.2

- None (analysis only)

## Phase 1.2 Complete ✅

Ready to proceed to Phase 1.3: Research Video Integration
