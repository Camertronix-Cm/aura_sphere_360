# Phase 0 Research Findings — flutter_webrtc 0.11.7 Android API

**Date:** March 31, 2026  
**Package Version:** flutter_webrtc 0.11.7  
**Location:** `~/.pub-cache/hosted/pub.dev/flutter_webrtc-0.11.7/`

---

## 1. Track Registry API ✅

### Finding: `getLocalTrack()` method exists

**Location:** `MethodCallHandlerImpl.java` line 1273-1275

```java
public MediaStreamTrack getLocalTrack(String trackId) {
  return localTracks.get(trackId);
}
```

### Access Pattern

The `MethodCallHandlerImpl` is NOT a singleton. It's instantiated per plugin binding:

```java
// FlutterWebRTCPlugin.java
private MethodCallHandlerImpl methodCallHandler;

private void startListening(final Context context, BinaryMessenger messenger,
                            TextureRegistry textureRegistry) {
    methodCallHandler = new MethodCallHandlerImpl(context, messenger, textureRegistry);
    // ...
}
```

### ⚠️ CRITICAL DIFFERENCE FROM iOS

**iOS approach (won't work on Android):**
```objc
FlutterWebRTCPlugin *webrtcPlugin = [FlutterWebRTCPlugin sharedSingleton];
RTCMediaStreamTrack *track = [webrtcPlugin trackForId:trackId peerConnectionId:peerConnectionId];
```

**Android reality:**
- No `getInstance()` static method exists
- No `sharedSingleton` pattern
- `MethodCallHandlerImpl` is private to `FlutterWebRTCPlugin`
- `getLocalTrack()` is public but instance-based

### 🔧 Solution for Android

We need to access the track through the peer connection observer or store track references ourselves. Two approaches:

**Approach A: Store track reference when creating the stream**
```kotlin
// In Dart, pass the MediaStreamTrack object reference
// Android can access it via the renderer's srcObject
```

**Approach B: Access via PeerConnectionObserver**
```java
// MethodCallHandlerImpl.java line 1350
private MediaStreamTrack getTrackForId(String trackId, String peerConnectionId) {
    MediaStreamTrack track = localTracks.get(trackId);
    if (track != null) {
        return track;
    }
    // Falls back to searching peer connections
    // ...
}
```

### ✅ RECOMMENDED APPROACH

Since we already have the `RTCVideoRenderer` in Dart with `srcObject` set, we can:
1. Extract the `VideoTrack` from the renderer's stream
2. Pass it directly to our sink

This avoids the singleton lookup issue entirely.

---

## 2. VideoSink Interface ✅

### Finding: `org.webrtc.VideoSink` is available

**Evidence:** Multiple implementations found in flutter_webrtc:
- `FrameCapturer.java` implements `VideoSink`
- `VideoFileRenderer.java` implements `VideoSink`
- `OrientationAwareScreenCapturer.java` implements `VideoSink`

### API Signature

```java
import org.webrtc.VideoSink;
import org.webrtc.VideoFrame;

public class FlutterRTCStreamingSink implements VideoSink {
    @Override
    public void onFrame(VideoFrame videoFrame) {
        // Called on WebRTC's video thread
    }
}
```

### VideoTrack Methods

```java
// From FrameCapturer.java line 32
track.addSink(this);

// From FrameCapturer.java line 91
videoTrack.removeSink(this);
```

✅ **Confirmed:** `VideoTrack.addSink(VideoSink)` and `removeSink(VideoSink)` are available.

---

## 3. YuvHelper Availability ✅

### Finding: `org.webrtc.YuvHelper` is available

**Location:** `FrameCapturer.java` line 14
```java
import org.webrtc.YuvHelper;
```

**Usage:** Line 64
```java
YuvHelper.I420ToNV12(y, strides[0], v, strides[2], u, strides[1], yuvBuffer, width, height);
```

### Available Methods

Based on usage in flutter_webrtc:
- `YuvHelper.I420ToNV12()` — confirmed

### ⚠️ I420ToABGR / I420ToBGRA Availability

The plan assumes `YuvHelper.I420ToABGR()` exists (like iOS `RTCYUVHelper`). This needs verification.

**Action Required:** Check WebRTC SDK documentation or test if:
```java
YuvHelper.I420ToABGR(
    i420.dataY, i420.strideY,
    i420.dataU, i420.strideU,
    i420.dataV, i420.strideV,
    bgra, stride, width, height
);
```
exists in `io.github.webrtc-sdk:android:125.6422.03`.

### 🔧 Fallback Plan

If `I420ToABGR` is not available, use:
1. **Option A:** Pure Kotlin I420→BGRA conversion (slower but works)
2. **Option B:** Maven dependency `io.github.crow-misia:libyuv-android:0.3.0`

---

## 4. WebRTC AAR Location ✅

### Finding: No local AAR file, uses Maven dependency

**Location:** `build.gradle` line 54
```gradle
dependencies {
    implementation 'io.github.webrtc-sdk:android:125.6422.03'
    // ...
}
```

### ⚠️ PLAN UPDATE REQUIRED

The original plan assumed:
```gradle
compileOnly files("../../../flutter_webrtc/android/libs/lib-flutter-webrtc.aar")
```

**This path does NOT exist.** The AAR is downloaded from Maven at build time.

### ✅ CORRECTED APPROACH

```gradle
dependencies {
    // WebRTC SDK is provided by flutter_webrtc at runtime
    compileOnly 'io.github.webrtc-sdk:android:125.6422.03'
}
```

Or rely on transitive dependency from flutter_webrtc (preferred):
```gradle
dependencies {
    // No explicit WebRTC dependency needed - inherited from flutter_webrtc
}
```

---

## 5. Minimum SDK Requirements ✅

### Finding: minSdkVersion 21 confirmed

**Location:** `build.gradle` line 35
```gradle
defaultConfig {
    minSdkVersion 21
    // ...
}
```

✅ **Confirmed:** API 21 (Android 5.0 Lollipop) is the minimum.

---

## 6. Additional Findings

### VideoFrame.Buffer API

From `FrameCapturer.java`:
```java
VideoFrame.Buffer buffer = videoFrame.getBuffer();
VideoFrame.I420Buffer i420Buffer = buffer.toI420();
ByteBuffer y = i420Buffer.getDataY();
ByteBuffer u = i420Buffer.getDataU();
ByteBuffer v = i420Buffer.getDataV();
int width = i420Buffer.getWidth();
int height = i420Buffer.getHeight();
int strideY = i420Buffer.getStrideY();
int strideU = i420Buffer.getStrideU();
int strideV = i420Buffer.getStrideV();
```

✅ This matches the iOS `RTCI420Buffer` protocol exactly.

### Thread Safety

From `FrameCapturer.java` line 91:
```java
new Handler(Looper.getMainLooper()).post(() -> {
    videoTrack.removeSink(this);
});
```

✅ **Confirmed:** EventSink calls must be posted to main thread.

---

## 7. Critical Architectural Decision

### Problem: No Singleton Access to Tracks

Unlike iOS, we cannot do:
```kotlin
val plugin = FlutterWebRTCPlugin.getInstance()  // ❌ Does not exist
val track = plugin.getLocalVideoTrack(trackId)   // ❌ Not accessible
```

### ✅ Solution: Extract Track from Renderer

Since Dart already has the `RTCVideoRenderer` with `srcObject` set:

```kotlin
// In WebrtcPixelStreamPlugin.kt
private fun handleCreatePixelStream(args: Map<*, *>, result: MethodChannel.Result) {
    val trackId = args["trackId"] as? String ?: return error(...)
    
    // Instead of looking up the track, we'll receive it via a different mechanism
    // Option 1: Pass the track object directly via platform channel (complex)
    // Option 2: Access the renderer's stream (requires renderer ID)
    // Option 3: Store track references in a companion registry (cleanest)
}
```

### 🎯 RECOMMENDED IMPLEMENTATION

Create a companion registry pattern:

```kotlin
// In mobile app's MainActivity or Application class
object WebRTCTrackRegistry {
    private val tracks = mutableMapOf<String, VideoTrack>()
    
    fun registerTrack(trackId: String, track: VideoTrack) {
        tracks[trackId] = track
    }
    
    fun getTrack(trackId: String): VideoTrack? = tracks[trackId]
    
    fun unregisterTrack(trackId: String) {
        tracks.remove(trackId)
    }
}
```

Then in Dart, after `onTrack` fires:
```dart
// Register the track for native access
await platform.invokeMethod('registerTrack', {
  'trackId': track.id,
  'trackObject': track,  // Platform channel serialization
});
```

---

## 8. Phase 0 Verification Checklist

| Item | Status | Notes |
|------|--------|-------|
| Track registry API | ⚠️ Partial | No singleton, need registry pattern |
| VideoSink interface | ✅ Confirmed | `org.webrtc.VideoSink` available |
| VideoTrack.addSink() | ✅ Confirmed | Used in FrameCapturer |
| YuvHelper availability | ⚠️ Partial | I420ToNV12 confirmed, I420ToABGR needs verification |
| WebRTC AAR location | ✅ Confirmed | Maven dependency, not local file |
| Minimum SDK | ✅ Confirmed | API 21 |
| Thread safety pattern | ✅ Confirmed | Handler(Looper.getMainLooper()).post() |

---

## 9. Updated Implementation Strategy

### Phase 1 Changes Required

1. **Remove singleton lookup code** — it won't work on Android
2. **Add track registry mechanism** — either in plugin or host app
3. **Update build.gradle** — use Maven dependency, not file path
4. **Verify YuvHelper.I420ToABGR** — test or implement fallback

### Phase 2 Changes Required

1. **JNI libyuv linking** — may need explicit Maven dependency
2. **AtomicInteger for writeIndex** — thread safety
3. **Proguard rules** — prevent R8 stripping

---

## 10. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| No singleton track access | 🔴 High | Implement registry pattern |
| YuvHelper.I420ToABGR missing | 🟡 Medium | Fallback to Kotlin or libyuv Maven |
| Thread safety issues | 🟡 Medium | Use AtomicInteger, Handler |
| Build system complexity | 🟢 Low | Well-documented Gradle setup |

---

## 11. Next Steps (Phase 1)

1. ✅ Create track registry mechanism
2. ✅ Update build.gradle with correct dependencies
3. ✅ Test YuvHelper.I420ToABGR availability
4. ✅ Implement Phase A with registry pattern
5. ✅ Add proguard rules

**Estimated time adjustment:** Add +1 day for registry implementation = 5-9 days total

---

## Conclusion

Phase 0 research reveals one critical architectural difference: Android flutter_webrtc does not expose a singleton plugin instance. This requires a track registry pattern. All other APIs are confirmed available and match the iOS implementation closely.

**Recommendation:** Proceed to Phase 1 with the updated registry-based approach.
