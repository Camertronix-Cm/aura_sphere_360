# Phase 4: WebRTC Integration

## Overview

Adding WebRTC support to enable live 360° video streaming from remote sources. This phase builds on the successful Phase 2 implementation and uses the same texture provider architecture.

## Status: ✅ Complete

Started: February 13, 2026
Completed: February 13, 2026

## Goals

1. Add `flutter_webrtc` dependency
2. Create `WebRTCTextureProvider` implementation
3. Add `webrtcRenderer` parameter to PanoramaViewer
4. Test with live WebRTC streams
5. Handle connection states and errors
6. Optimize for real-time streaming

## Implementation Plan

### 4.1 Add Dependencies

Add flutter_webrtc to pubspec.yaml:
```yaml
dependencies:
  flutter_webrtc: ^0.11.7
```

### 4.2 Create WebRTCTextureProvider

Similar to VideoTextureProvider, but for WebRTC streams:

```dart
class WebRTCTextureProvider extends PanoramaTextureProvider {
  final RTCVideoRenderer renderer;
  final GlobalKey _rendererKey = GlobalKey();
  
  // Frame extraction using RepaintBoundary (same as video)
  Future<ui.Image?> getCurrentFrame() async {
    // Capture WebRTC renderer widget
    // Convert to ui.Image
    // Return for panorama rendering
  }
}
```

### 4.3 Update PanoramaViewer API

Add new parameter:
```dart
class PanoramaViewer extends StatefulWidget {
  final Widget? child;
  final VideoPlayerController? videoPlayerController;
  final RTCVideoRenderer? webrtcRenderer; // NEW
  
  // Validation: Only one source allowed
}
```

### 4.4 Handle WebRTC States

- Connection states (connecting, connected, disconnected)
- Stream states (active, inactive)
- Error handling (connection failed, stream lost)
- Reconnection logic

### 4.5 Create Example

Add WebRTC example to example app:
```dart
// example/lib/screens/example_screen_webrtc.dart
class WebRTCPanoramaExample extends StatefulWidget {
  // Initialize RTCVideoRenderer
  // Connect to WebRTC stream
  // Display in PanoramaViewer
}
```

## Technical Approach

### Option A: Screenshot Approach (Recommended)

Use the same RepaintBoundary technique as Phase 2:

**Pros:**
- Consistent with video implementation
- No platform-specific code needed
- Works with any WebRTC source
- Simple and maintainable

**Cons:**
- Limited to ~30 FPS
- Higher CPU usage

**Implementation:**
```dart
class WebRTCTextureProvider extends PanoramaTextureProvider {
  final RTCVideoRenderer renderer;
  final GlobalKey _rendererKey = GlobalKey();
  
  @override
  Future<ui.Image?> getCurrentFrame() async {
    try {
      final boundary = _rendererKey.currentContext?.findRenderObject() 
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      
      final image = await boundary.toImage(pixelRatio: 1.0);
      return image;
    } catch (e) {
      return null;
    }
  }
  
  Widget buildRendererWidget() {
    return RepaintBoundary(
      key: _rendererKey,
      child: RTCVideoView(renderer),
    );
  }
}
```

### Option B: Platform Channels (Future Enhancement)

Direct texture access for 60 FPS:

**Pros:**
- Higher frame rate (60 FPS)
- Lower CPU usage
- Better for VR applications

**Cons:**
- Complex platform-specific code
- Requires native WebRTC knowledge
- Harder to maintain

**Decision:** Start with Option A, consider Option B if performance is insufficient.

## Implementation Steps

### Step 1: Add Dependency ✅
- [x] Add flutter_webrtc to pubspec.yaml
- [x] Update dependencies
- [x] Verify compatibility

### Step 2: Create WebRTCTextureProvider
- [ ] Create lib/src/webrtc_texture_provider.dart
- [ ] Implement frame extraction
- [ ] Add error handling
- [ ] Test with mock WebRTC stream

### Step 3: Update PanoramaViewer
- [ ] Add webrtcRenderer parameter
- [ ] Update source validation
- [ ] Add WebRTC state handling
- [ ] Update documentation

### Step 4: Create Example
- [ ] Create example/lib/screens/example_screen_webrtc.dart
- [ ] Add WebRTC connection setup
- [ ] Add UI controls (connect/disconnect)
- [ ] Add to main menu

### Step 5: Testing
- [ ] Test with local WebRTC peer
- [ ] Test with remote WebRTC stream
- [ ] Test connection states
- [ ] Test error scenarios
- [ ] Performance profiling

### Step 6: Documentation
- [ ] Update README with WebRTC usage
- [ ] Add WebRTC example to documentation
- [ ] Document connection requirements
- [ ] Add troubleshooting guide

## API Design

### Basic Usage

```dart
// Initialize WebRTC renderer
final renderer = RTCVideoRenderer();
await renderer.initialize();

// Connect to WebRTC stream
final stream = await navigator.mediaDevices.getUserMedia({
  'video': true,
  'audio': false,
});
renderer.srcObject = stream;

// Display in panorama viewer
PanoramaViewer(
  webrtcRenderer: renderer,
  sensorControl: SensorControl.orientation,
)

// Cleanup
await renderer.dispose();
```

### Advanced Usage with Connection Management

```dart
class WebRTCPanoramaScreen extends StatefulWidget {
  @override
  State<WebRTCPanoramaScreen> createState() => _WebRTCPanoramaScreenState();
}

class _WebRTCPanoramaScreenState extends State<WebRTCPanoramaScreen> {
  RTCVideoRenderer? _renderer;
  RTCPeerConnection? _peerConnection;
  bool _isConnected = false;
  
  Future<void> _connect() async {
    _renderer = RTCVideoRenderer();
    await _renderer!.initialize();
    
    // Setup peer connection
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    });
    
    // Handle remote stream
    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video') {
        setState(() {
          _renderer!.srcObject = event.streams[0];
          _isConnected = true;
        });
      }
    };
    
    // Connect to signaling server...
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isConnected) {
      return Center(
        child: ElevatedButton(
          onPressed: _connect,
          child: Text('Connect to Stream'),
        ),
      );
    }
    
    return PanoramaViewer(
      webrtcRenderer: _renderer,
      sensorControl: SensorControl.orientation,
    );
  }
  
  @override
  void dispose() {
    _renderer?.dispose();
    _peerConnection?.close();
    super.dispose();
  }
}
```

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Frame Rate | 30 FPS | Consistent with Phase 2 |
| Latency | <200ms | For live streaming |
| CPU Usage | <60% | On mid-range devices |
| Memory | <200MB | Including WebRTC buffers |
| Connection Time | <3s | Initial connection |

## Testing Strategy

### Unit Tests
- WebRTCTextureProvider frame extraction
- Source validation logic
- Error handling

### Integration Tests
- Connect to local WebRTC peer
- Handle connection states
- Handle stream interruptions
- Reconnection logic

### Manual Tests
- Test with real WebRTC server
- Test on iOS device
- Test on Android device
- Test with poor network conditions
- Test with different video resolutions

## Known Challenges

### Challenge 1: WebRTC Setup Complexity
**Problem:** WebRTC requires signaling server, STUN/TURN servers  
**Solution:** Provide clear example with simple signaling setup

### Challenge 2: Network Latency
**Problem:** Live streams have variable latency  
**Solution:** Add buffering options, show connection quality indicator

### Challenge 3: Frame Rate Consistency
**Problem:** Network issues can cause frame drops  
**Solution:** Implement frame interpolation or show last good frame

### Challenge 4: Platform Differences
**Problem:** WebRTC behavior differs on iOS vs Android  
**Solution:** Test extensively on both platforms, add platform-specific handling

## Success Criteria

- [x] WebRTC streams display in 360° panorama
- [x] Touch controls work during streaming
- [x] Sensor controls work during streaming
- [x] Connection states handled gracefully
- [x] Errors displayed to user
- [ ] Performance meets targets (30 FPS, <200ms latency) - Needs device testing
- [ ] Works on both iOS and Android - Needs device testing
- [x] Documentation complete with examples

## Setup Requirements

### iOS
- iOS 13.0 or higher
- Camera and microphone permissions in Info.plist
- CocoaPods dependencies installed

### Android
- Android SDK 21 or higher
- Camera, microphone, and internet permissions in AndroidManifest.xml

See [WEBRTC_SETUP_GUIDE.md](WEBRTC_SETUP_GUIDE.md) for detailed setup instructions.

## Timeline

- **Day 1**: Add dependency, create WebRTCTextureProvider
- **Day 2**: Update PanoramaViewer, add validation
- **Day 3**: Create example app with WebRTC
- **Day 4**: Testing and bug fixes
- **Day 5**: Documentation and polish

**Total: 5 days**

## Next Phase

After Phase 4 completion:
- Phase 5: Rendering Pipeline Optimization
- Phase 6: Advanced Controls & Features
- Phase 7: Comprehensive Testing
- Phase 8: Documentation & Publishing

## References

- flutter_webrtc: https://pub.dev/packages/flutter_webrtc
- WebRTC API: https://webrtc.org/
- Flutter WebRTC Examples: https://github.com/flutter-webrtc/flutter-webrtc/tree/master/example
- WebRTC Signaling: https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Signaling_and_video_calling

