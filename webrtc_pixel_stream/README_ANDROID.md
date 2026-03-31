# Android Implementation — webrtc_pixel_stream

**Status:** Phase 1 Complete ✅ | Phase 2 In Progress 🟡

---

## Overview

This is the Android implementation of the `webrtc_pixel_stream` Flutter plugin, which provides high-performance pixel streaming from WebRTC video tracks.

### Architecture

- **Phase A (Current):** Legacy EventChannel with pixel bytes
- **Phase B (Future):** FFI double-buffer with zero-copy streaming

---

## Implementation Status

| Phase | Status | Description |
|-------|--------|-------------|
| 0 | ✅ Complete | Research & API verification |
| 1 | ✅ Complete | Plugin scaffold & StateProvider access |
| 2 | 🟡 In Progress | I420→BGRA conversion implementation |
| 3 | ⏳ Pending | FFI double-buffer + JNI |
| 4 | ⏳ Pending | Dart platform guard |
| 5 | ⏳ Pending | Testing & benchmarking |
| 6 | ⏳ Pending | Documentation |

---

## Phase 1 Deliverables

### Files Created

```
android/
├── build.gradle                    # Gradle configuration
├── proguard-rules.pro             # R8 optimization rules
├── src/main/
│   ├── AndroidManifest.xml        # Minimal manifest
│   └── kotlin/com/camertronix/webrtc_pixel_stream/
│       ├── WebrtcPixelStreamPlugin.kt      # Main plugin (204 lines)
│       └── FlutterRTCStreamingSink.kt      # VideoSink impl (109 lines)
```

### Key Features Implemented

✅ **StateProvider Access** — Reflection-based access to flutter_webrtc's track registry  
✅ **Retry Logic** — 20 attempts with 100ms delay (mirrors iOS)  
✅ **Thread Safety** — All EventSink calls on main thread  
✅ **Comprehensive Logging** — Debug logs for every step  
✅ **Error Handling** — Graceful fallbacks and cleanup  
✅ **Proguard Rules** — Prevents R8 from stripping critical classes

---

## How It Works

### 1. Plugin Registration

```kotlin
class WebrtcPixelStreamPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Access flutter_webrtc's StateProvider via reflection
        val webrtcPlugin = binding.flutterEngine.plugins.get(
            Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
        )
        val handlerField = webrtcPlugin?.javaClass?.getDeclaredField("methodCallHandler")
        handlerField?.isAccessible = true
        stateProvider = handlerField?.get(webrtcPlugin) as? StateProvider
    }
}
```

### 2. Track Attachment

```kotlin
private fun attachRenderer(sink, trackId, sinkId, retryCount) {
    // Get track via StateProvider
    val track = stateProvider?.getLocalTrack(trackId) as? VideoTrack
    
    if (track != null) {
        track.addSink(sink)  // Attach our VideoSink
    } else if (retryCount < MAX_RETRIES) {
        // Retry after 100ms
        Handler(Looper.getMainLooper()).postDelayed({
            attachRenderer(sink, trackId, sinkId, retryCount + 1)
        }, 100)
    }
}
```

### 3. Frame Processing

```kotlin
class FlutterRTCStreamingSink : VideoSink {
    override fun onFrame(frame: VideoFrame) {
        val i420 = frame.buffer.toI420()
        
        // TODO: Convert I420 → BGRA (Phase 2)
        // Currently sends test pattern
        
        val event = mapOf(
            "frameReady" to true,
            "width" to width,
            "height" to height,
            "stride" to stride,
            "bytes" to bgra  // Pixel data
        )
        
        mainHandler.post { eventSink.success(event) }
    }
}
```

---

## Dependencies

### Compile-Time

```gradle
compileOnly 'io.github.webrtc-sdk:android:125.6422.03'
```

The WebRTC SDK is provided by `flutter_webrtc` at runtime. We use `compileOnly` to get class signatures without duplicating the runtime copy.

### Runtime

- `flutter_webrtc: ^0.11.7` (peer dependency)
- Kotlin stdlib

---

## Building

### From Plugin Directory

```bash
cd aura_sphere_360/webrtc_pixel_stream
./verify_phase1.sh  # Verify implementation
```

### From Mobile App

```bash
cd mobile
flutter pub get
flutter build apk --debug
```

### Expected Logs

```
D/WebrtcPixelStream: onAttachedToEngine called
D/WebrtcPixelStream: ✅ StateProvider accessed successfully
D/WebrtcPixelStream: Plugin initialized
D/WebrtcPixelStream: createPixelStream called - trackId: xxx
D/WebrtcPixelStream: ✅ Renderer attached to track: xxx
D/FlutterRTCStreamingSink: [xxx] Frame 30 received: 1920x1080
```

---

## Known Issues

### 1. Test Pattern Only (Expected)

**Issue:** Frames show blue test pattern instead of actual video  
**Cause:** I420→BGRA conversion not yet implemented  
**Status:** Phase 2 work  
**Workaround:** None - this is expected for Phase 1

### 2. YuvHelper Availability Unknown

**Issue:** Don't know if `YuvHelper.I420ToABGR` exists  
**Status:** Will verify in Phase 2  
**Fallback:** Use `io.github.crow-misia:libyuv-android` if needed

---

## Testing

### Phase 1 Verification

```bash
./verify_phase1.sh
```

Should output:
```
✅ Phase 1 verification PASSED!
Results: 15 passed, 0 failed
```

### Manual Testing

1. Build the mobile app
2. Connect to Aura360 device
3. Start WebRTC stream
4. Check logs for StateProvider access
5. Verify track attachment
6. Confirm onFrame callbacks fire

---

## Troubleshooting

### StateProvider Not Found

**Symptom:** `⚠️ FlutterWebRTCPlugin not found in engine`

**Causes:**
- flutter_webrtc not initialized yet
- Plugin load order issue

**Fix:**
- Ensure flutter_webrtc is in pubspec.yaml
- Check plugin initialization order

### Track Not Found After 20 Retries

**Symptom:** `❌ Gave up waiting for track: xxx after 20 attempts`

**Causes:**
- Track ID incorrect
- Track not registered in flutter_webrtc yet
- WebRTC connection not established

**Fix:**
- Verify track ID from Dart side
- Ensure WebRTC connection is established
- Check flutter_webrtc logs

### Proguard Stripping Classes

**Symptom:** ClassNotFoundException in release build

**Fix:**
- Verify proguard-rules.pro is applied
- Check build.gradle has `consumerProguardFiles`
- Add specific keep rules if needed

---

## Performance Targets

### Phase A (Legacy EventChannel)

- **Target FPS:** ≥20fps at 1080p
- **Memory:** <100MB for frame buffers
- **Latency:** <50ms per frame

### Phase B (FFI Double-Buffer)

- **Target FPS:** ≥30fps at 1080p
- **Memory:** 64MB for double-buffer (fixed)
- **Latency:** <30ms per frame

---

## Next Steps

### Phase 2: I420→BGRA Conversion

1. Verify `YuvHelper.I420ToABGR` availability
2. Implement conversion in `FlutterRTCStreamingSink.onFrame()`
3. Test with real video frames
4. Measure performance (FPS, memory)
5. Handle edge cases (rotation, stride, etc.)

### Phase 3: FFI Double-Buffer

1. Add CMakeLists.txt for JNI
2. Implement native I420→BGRA with libyuv
3. Write to Dart FFI memory directly
4. Send metadata-only events
5. Benchmark zero-copy performance

---

## Resources

- [Phase 0 Research Findings](PHASE_0_RESEARCH_FINDINGS.md)
- [Phase 1 Complete Summary](PHASE_1_COMPLETE.md)
- [Android Port Plan](ANDROID_PORT_PLAN.md)
- [Implementation Solution](ANDROID_IMPLEMENTATION_SOLUTION.md)

---

## Contributing

When working on this plugin:

1. Follow the phase plan in `ANDROID_PORT_PLAN.md`
2. Run `./verify_phase1.sh` before committing
3. Add comprehensive logging for debugging
4. Update this README with any changes
5. Document any deviations from the plan

---

**Last Updated:** March 31, 2026  
**Phase 1 Completed By:** Kiro AI Assistant  
**Next Phase:** Phase 2 - I420→BGRA Conversion
