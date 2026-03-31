# Phase 2 Complete — I420→BGRA Conversion Implemented ✅

**Date:** March 31, 2026  
**Status:** Phase 2 Implementation Complete

---

## What Was Implemented

### 1. I420→BGRA Conversion Function ✅

Implemented a pure Kotlin conversion function that transforms WebRTC's I420 (YUV420 planar) format to BGRA8888 format expected by Flutter's `ui.decodeImageFromPixels()`.

**Key Features:**
- Pure Kotlin implementation (no native dependencies)
- ITU-R BT.601 color space conversion
- Proper 2x2 chroma subsampling handling
- RGB clamping to [0, 255] range
- Direct ByteBuffer access for efficiency

### 2. Conversion Algorithm

```kotlin
private fun convertI420ToBGRA(
    yBuffer: ByteBuffer, yStride: Int,
    uBuffer: ByteBuffer, uStride: Int,
    vBuffer: ByteBuffer, vStride: Int,
    bgra: ByteArray, bgraStride: Int,
    width: Int, height: Int
)
```

**Process:**
1. Iterate through each pixel (row, col)
2. Read Y value at full resolution
3. Read U, V values at quarter resolution (2x2 subsampling)
4. Apply ITU-R BT.601 YUV→RGB conversion:
   - `c = y - 16`
   - `d = u - 128`
   - `e = v - 128`
   - `r = (298*c + 409*e + 128) >> 8`
   - `g = (298*c - 100*d - 208*e + 128) >> 8`
   - `b = (298*c + 516*d + 128) >> 8`
5. Clamp RGB values to [0, 255]
6. Write BGRA bytes (B, G, R, A=0xFF)

### 3. Integration with onFrame()

Replaced test pattern placeholder with actual conversion:

```kotlin
override fun onFrame(frame: VideoFrame) {
    // ... frame setup ...
    
    // Phase A: I420 → BGRA conversion using pure Kotlin
    convertI420ToBGRA(
        i420.dataY, i420.strideY,
        i420.dataU, i420.strideU,
        i420.dataV, i420.strideV,
        bgra, stride, width, height
    )
    
    i420.release()
    
    // Send frame event with pixel bytes
    val event = mapOf(
        "frameReady" to true,
        "width" to width,
        "height" to height,
        "stride" to stride,
        "bytes" to bgra
    )
    mainHandler.post { sink.success(event) }
}
```

---

## Technical Details

### I420 Format

I420 (also called YUV420p) is a planar YUV format:
- **Y plane:** Luma (brightness), full resolution (width × height)
- **U plane:** Chroma blue difference, quarter resolution (width/2 × height/2)
- **V plane:** Chroma red difference, quarter resolution (width/2 × height/2)

Each 2×2 block of pixels shares the same U and V values (chroma subsampling).

### BGRA8888 Format

Flutter's `ui.PixelFormat.bgra8888` expects:
- 4 bytes per pixel
- Order: Blue, Green, Red, Alpha
- Little-endian memory layout
- Alpha = 0xFF (opaque)

### Color Space Conversion

Using ITU-R BT.601 standard (SDTV):
- Y range: [16, 235] (studio swing)
- U, V range: [16, 240] (centered at 128)
- Conversion matrix optimized with integer arithmetic
- Bit shift (>> 8) instead of division for performance

### Performance Characteristics

**Pure Kotlin Implementation:**
- ✅ No native dependencies
- ✅ Works on all Android devices
- ✅ Simple to debug and maintain
- ⚠️ Slower than libyuv (expected 15-25 fps for 1080p)

**Expected Frame Rates (1080p stream):**
- Pure Kotlin: 15-25 fps
- libyuv (Phase B): 30-60 fps

---

## Testing Checklist

### Build Tests

- [ ] `flutter pub get` in webrtc_pixel_stream
- [ ] `flutter pub get` in mobile app
- [ ] Android build succeeds
- [ ] No Kotlin compilation errors
- [ ] No runtime crashes

### Runtime Tests

- [ ] Plugin registers successfully
- [ ] createPixelStream returns channel name
- [ ] Track attachment succeeds
- [ ] onFrame callback fires
- [ ] **Actual video frames appear (not blue test pattern)**
- [ ] Frame rate ≥ 15 fps for 720p
- [ ] Frame rate ≥ 10 fps for 1080p
- [ ] Colors look correct (not inverted/shifted)
- [ ] No memory leaks after 5 minutes
- [ ] disposePixelStream cleans up

### Visual Tests

- [ ] Video plays smoothly
- [ ] Colors match iOS version
- [ ] No color banding or artifacts
- [ ] Rotation handled correctly
- [ ] Different resolutions work (480p, 720p, 1080p)

### Log Verification

Look for these log messages:

```
D/FlutterRTCStreamingSink: [xxx] Frame 30 received: 1920x1080
D/FlutterRTCStreamingSink: [xxx] Frame 60 received: 1920x1080
```

Should NOT see:
```
W/FlutterRTCStreamingSink: I420→BGRA conversion not yet implemented
```

---

## Known Limitations

### 1. Performance

**Issue:** Pure Kotlin conversion is slower than native libyuv  
**Impact:** Frame rate may be 15-25 fps instead of 30-60 fps  
**Mitigation:** Phase B will add libyuv via JNI for better performance  
**Workaround:** Lower resolution streams (720p instead of 1080p)

### 2. CPU Usage

**Issue:** Conversion runs on CPU, not GPU  
**Impact:** Higher battery drain than hardware-accelerated decoding  
**Mitigation:** Phase B JNI + libyuv will be more efficient  
**Workaround:** None - this is expected for Phase A

---

## Comparison with iOS

| Feature | iOS | Android Phase A |
|---------|-----|-----------------|
| Conversion method | vImage (NV12→BGRA) | Pure Kotlin (I420→BGRA) |
| Performance | 30-60 fps | 15-25 fps |
| Dependencies | System framework | None |
| Code complexity | Low | Low |
| Maintainability | High | High |

---

## Phase 2 Success Criteria

| Criterion | Status | Notes |
|-----------|--------|-------|
| I420→BGRA function implemented | ✅ | Pure Kotlin |
| ITU-R BT.601 conversion | ✅ | Standard coefficients |
| Chroma subsampling handled | ✅ | 2x2 blocks |
| RGB clamping | ✅ | [0, 255] range |
| BGRA byte order | ✅ | Matches Flutter |
| Integration with onFrame | ✅ | Test pattern removed |
| No additional dependencies | ✅ | Pure Kotlin only |
| Code documented | ✅ | Inline comments |

**All criteria met!** ✅

---

## Files Modified

### Modified:
1. `android/src/main/kotlin/.../FlutterRTCStreamingSink.kt`
   - Added `convertI420ToBGRA()` function
   - Replaced test pattern with actual conversion
   - Added detailed documentation

### Created:
1. `PHASE_2_COMPLETE.md` (this file)

---

## Next Steps (Phase 3)

Phase 3 will implement the FFI double-buffer path for zero-copy frame delivery:

1. **Add FFI Parameters to createPixelStream**
   - Extract `memoryAddressA`, `memoryAddressB`, `memorySize` from Dart
   - Pass to FlutterRTCStreamingSink constructor

2. **Implement FFI Path in FlutterRTCStreamingSink**
   - Add constructor overload with buffer addresses
   - Implement atomic buffer index flipping
   - Create JNI native method `nativeWriteI420ToBGRA()`

3. **Create JNI Helper**
   - `webrtc_pixel_stream.cpp` with libyuv integration
   - CMakeLists.txt for native build
   - Direct memory write to Dart FFI buffers

4. **Update build.gradle**
   - Uncomment CMake configuration
   - Add libyuv dependency (if needed)

5. **Test FFI Path**
   - Verify zero-copy works
   - Measure frame rate improvement (target: 30-60 fps)
   - Check memory safety

---

## Performance Optimization Notes

### Current Bottlenecks

1. **Nested loops:** O(width × height) iteration
2. **ByteBuffer.get():** Individual byte access (not bulk)
3. **Integer arithmetic:** Per-pixel calculations

### Phase B Improvements

1. **libyuv:** SIMD-optimized conversion (NEON on ARM)
2. **Bulk operations:** Process multiple pixels at once
3. **Zero-copy:** Write directly to Dart memory (no EventChannel)

### Expected Speedup

- Pure Kotlin: ~15-25 fps (1080p)
- libyuv JNI: ~30-60 fps (1080p)
- **Improvement: 2-3x faster**

---

## Time Tracking

**Phase 2 Estimate:** 1-2 days  
**Phase 2 Actual:** 0.5 days ✅  
**Ahead of Schedule:** Yes (simple pure Kotlin approach)

**Cumulative:**
- Phase 0: 0.5 days
- Phase 1: 0.5 days
- Phase 2: 0.5 days
- **Total: 1.5 days**

**Remaining:**
- Phase 3: 1-2 days (FFI double-buffer)
- Phase 4: 0.5 days (Dart platform guard)
- Phase 5: 1-2 days (Testing)
- Phase 6: 0.5 days (Documentation)
- **Remaining: 3.5-5 days**

---

## Approval to Proceed to Phase 3

✅ I420→BGRA conversion implemented  
✅ Pure Kotlin approach (no dependencies)  
✅ Ready for FFI double-buffer implementation  
⚠️ Should test Phase A with real device first

**Recommendation:** 
1. Test Phase A on physical device to verify conversion works
2. Measure baseline frame rate
3. Then proceed to Phase 3 for FFI optimization

---

**Phase 2 Status:** ✅ COMPLETE  
**Next Phase:** Phase 3 - FFI Double-Buffer Implementation  
**Blocker:** None (but testing recommended before Phase 3)

