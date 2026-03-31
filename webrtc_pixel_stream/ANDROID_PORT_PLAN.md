# Android Port Plan — `webrtc_pixel_stream`

> **Goal:** Give the `webrtc_pixel_stream` companion plugin an Android implementation that is
> functionally identical to the existing iOS side, enabling the native FFI double-buffer path
> on Android, with the legacy EventChannel-bytes path as an intermediate milestone.

---

## Current State Snapshot

| Layer | iOS (done) | Android (missing) |
|---|---|---|
| Plugin registration | `WebrtcPixelStreamPlugin.m` | nothing |
| Frame sink / renderer | `FlutterRTCStreamingSink.m` | nothing |
| Pixel format conversion | `vImage` (NV12→BGRA), libyuv (I420→BGRA) | nothing |
| FFI double-buffer write | ✅ done | nothing |
| Dart provider (`NativeWebRTCTextureProvider`) | routes via `bufferIndex` vs `bytes` | ✅ legacy fallback already coded |
| Dart frame decoder (`native_frame_decoder.dart`) | `decodeFFIFrame()` | ✅ `decodeFrameEvent()` already exists |
| `pubspec.yaml` / `build.gradle` | `.podspec` | nothing |

---

## Phase 0 — Research & Verification ✅ COMPLETE (Audited)

**Status:** Completed March 31, 2026  
**Audited:** March 31, 2026 — three corrections applied (see below)  
**Findings:** See `PHASE_0_RESEARCH_FINDINGS.md` and `ANDROID_IMPLEMENTATION_SOLUTION.md`

### Key Findings Summary

1. **Track Access** ⚠️ PARTIALLY CORRECT — audit correction applied
   - `MethodCallHandlerImpl.getLocalTrack(trackId)` exists and is public **but only stores local camera/mic tracks**
   - **Remote WebRTC tracks (our use case) are stored in `PeerConnectionObserver.remoteTracks`**, only reachable via the private `getTrackForId(trackId, peerConnectionId)` method
   - Using `StateProvider.getLocalTrack()` alone will return `null` for every incoming stream
   - **Correct approach:** reflect the private `getTrackForId` method and pass `peerConnectionId` (which Dart already sends in `createPixelStream`)

2. **VideoSink Interface** ✅
   - `org.webrtc.VideoSink` confirmed available
   - `VideoTrack.addSink()` and `removeSink()` confirmed

3. **YuvHelper** ⚠️
   - `org.webrtc.YuvHelper` exists
   - `I420ToNV12` confirmed, `I420ToABGR` needs runtime verification
   - **Decision for Phase A:** use a pure Kotlin I420→BGRA loop to avoid build risk; add libyuv for Phase B JNI only
   - Fallback: `io.github.crow-misia:libyuv-android:0.3.0` if needed

4. **WebRTC Dependency** ✅
   - Maven: `io.github.webrtc-sdk:android:125.6422.03`
   - No local AAR file, use `compileOnly` dependency

5. **Minimum SDK** ✅
   - API 21 (Android 5.0) confirmed

### ✅ Corrected Implementation Approach

**Audit finding:** `binding.flutterEngine` is NOT available on `FlutterPlugin.FlutterPluginBinding` — that property only exists on `FlutterEngineGroup` bindings. The correct approach is to cache the `FlutterWebRTCPlugin` instance via a static weak reference when first seen, or use the `binaryMessenger` handle as an identity key.

**Recommended pattern for `onAttachedToEngine`:**

```kotlin
override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    // flutter_webrtc is registered before us, so its methodCallHandler is already set.
    // We can't access FlutterEngine directly, but we can reach methodCallHandler via
    // a static weak reference that flutter_webrtc sets during its own onAttachedToEngine.
    // Simplest reliable approach: reflect FlutterWebRTCPlugin from the plugin registry
    // using the application context as the lookup key (stored statically).
    try {
        val pluginClass = Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
        // FlutterWebRTCPlugin stores its methodCallHandler in a private field.
        // We cache a reference to the handler (not the plugin itself) because we
        // already have the field name from source inspection.
        cachedHandlerRef = WeakReference(WebRTCHandlerCache.get(binding.binaryMessenger))
    } catch (e: Exception) {
        Log.w(TAG, "Could not cache WebRTC handler, will use getTrackForId fallback", e)
    }
    // ...
}
```

**For reliable track lookup** (works for both local and remote), reflect `getTrackForId`:

```kotlin
private fun getVideoTrack(trackId: String, peerConnectionId: String?): VideoTrack? {
    val handler = cachedHandler ?: return null
    return try {
        val method = handler.javaClass.getDeclaredMethod(
            "getTrackForId", String::class.java, String::class.java
        )
        method.isAccessible = true
        method.invoke(handler, trackId, peerConnectionId) as? VideoTrack
    } catch (e: Exception) {
        Log.w(TAG, "getTrackForId reflection failed: ${e.message}")
        null
    }
}
```

This reaches `localTracks`, `pco.remoteTracks`, AND `getTransceiversTrack()` — the full lookup chain that flutter_webrtc itself uses for `captureFrame` and `startRecordToFile`.

---

## Phase 1 — Plugin Directory Scaffold (½ day)

Create the standard Flutter plugin `android/` folder structure inside
`aura_sphere_360/webrtc_pixel_stream/`:

```
android/
  build.gradle
  src/
    main/
      AndroidManifest.xml
      kotlin/
        com/camertronix/webrtc_pixel_stream/
          WebrtcPixelStreamPlugin.kt      ← equivalent of WebrtcPixelStreamPlugin.m
          FlutterRTCStreamingSink.kt      ← equivalent of FlutterRTCStreamingSink.m
      cpp/
        webrtc_pixel_stream.cpp           ← JNI helper (Phase B only)
        CMakeLists.txt
```

### `build.gradle` key settings

```groovy
android {
    compileSdkVersion 34
    defaultConfig { 
        minSdkVersion 21
    }
    kotlinOptions { jvmTarget = "1.8" }
    // Phase B only:
    // externalNativeBuild { cmake { path "src/main/cpp/CMakeLists.txt" } }
}

dependencies {
    // WebRTC SDK is provided by flutter_webrtc at runtime
    // Use compileOnly to get compile-time class signatures without duplicating runtime copy
    compileOnly 'io.github.webrtc-sdk:android:125.6422.03'
    
    // Phase B: libyuv for JNI (if YuvHelper.I420ToABGR is not available)
    // implementation 'io.github.crow-misia:libyuv-android:0.3.0'
}
```

### Proguard rules (`proguard-rules.pro`)

```proguard
# Keep WebRTC classes from being stripped by R8
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class com.camertronix.webrtc_pixel_stream.** { *; }

# Keep StateProvider interface for reflection access
-keep interface com.cloudwebrtc.webrtc.StateProvider { *; }
```

### `AndroidManifest.xml`

Minimal — no permissions needed (the host app already holds INTERNET / camera rights):

```xml
<manifest package="com.camertronix.webrtc_pixel_stream" />
```

### `WebrtcPixelStreamPlugin.kt` — Plugin registration and StateProvider access

```kotlin
package com.camertronix.webrtc_pixel_stream

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.cloudwebrtc.webrtc.StateProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.webrtc.VideoTrack

class WebrtcPixelStreamPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var messenger: BinaryMessenger
    private var stateProvider: StateProvider? = null
    
    private val sinks = mutableMapOf<String, FlutterRTCStreamingSink>()
    private val videoTracks = mutableMapOf<String, VideoTrack>()
    
    companion object {
        private const val TAG = "WebrtcPixelStream"
        private const val MAX_RETRIES = 20
    }
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // ⚠️ AUDIT NOTE: binding.flutterEngine is NOT available here (compile error).
        // Instead, reflect methodCallHandler from FlutterWebRTCPlugin via a static cache
        // populated by the messenger identity. flutter_webrtc registers before us so
        // its handler is already initialised by the time we run.
        try {
            val pluginClass = Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
            // Look up the already-registered instance from Flutter's internal plugin map
            // via the known messenger as a handle — or use WebRTCHandlerCache (see below).
            val handlerField = pluginClass.getDeclaredField("methodCallHandler")
            handlerField.isAccessible = true
            // cachedWebRTCPlugin must be obtained through a static weak ref set by an
            // Application subclass, or via a companion-level messenger→plugin map.
            // (Full implementation: see WebRTCHandlerCache helper class in Phase 1 code)
            cachedHandler = handlerField.get(cachedWebRTCPlugin) // set in companion
            Log.d(TAG, "✅ WebRTC methodCallHandler cached")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Could not cache WebRTC handler, track lookup will fallback: ${e.message}")
        }

        channel = MethodChannel(binding.binaryMessenger, "webrtc_pixel_stream/control")
        channel.setMethodCallHandler(this)
        messenger = binding.binaryMessenger
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        sinks.values.forEach { it.dispose() }
        sinks.clear()
        videoTracks.clear()
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createPixelStream" -> handleCreatePixelStream(call.arguments as? Map<*, *>, result)
            "disposePixelStream" -> handleDisposePixelStream(call.arguments as? Map<*, *>, result)
            else -> result.notImplemented()
        }
    }
    
    // Implementation continues in next section...
}
```

---

## Phase 2 — Milestone A: Legacy EventChannel Path (1–2 days)

Fastest path to a working Android build. Matches the `decodeFrameEvent()` legacy path already
coded in `native_frame_decoder.dart`. **No Dart changes required.**

### `FlutterRTCStreamingSink.kt` (Phase A — bytes over EventChannel)

```kotlin
class FlutterRTCStreamingSink(
    private val sinkId: String,
    messenger: BinaryMessenger
) : VideoSink {

    private val channel = EventChannel(messenger, "webrtc_pixel_stream/frames/$sinkId")
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onFrame(frame: VideoFrame) {
        val sink = eventSink ?: return
        
        try {
            val i420 = frame.buffer.toI420() ?: return
            val width  = frame.rotatedWidth
            val height = frame.rotatedHeight
            val stride = width * 4
            val bgra   = ByteArray(stride * height)

            // libyuv I420 → ABGR = BGRA in little-endian memory
            // TODO: Verify YuvHelper availability in Phase 0
            YuvHelper.I420ToABGR(
                i420.dataY, i420.strideY,
                i420.dataU, i420.strideU,
                i420.dataV, i420.strideV,
                bgra, stride, width, height
            )
            i420.release()

            val event = mapOf(
                "frameReady" to true,
                "width"      to width,
                "height"     to height,
                "stride"     to stride,
                "bytes"      to bgra          // legacy path: pixel bytes in the event
            )
            mainHandler.post { sink.success(event) }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing frame", e)
        }
    }

    fun dispose() {
        eventSink = null
        channel.setStreamHandler(null)
    }
    
    companion object {
        private const val TAG = "FlutterRTCStreamingSink"
    }
}
```

> **Note:** `YuvHelper` is bundled in `flutter_webrtc`'s libyuv bindings.
> If it's not exposed as a Kotlin class, a pure Kotlin I420→BGRA loop (~5 lines) is a fine fallback.

### `WebrtcPixelStreamPlugin.kt` — `createPixelStream` handler (Phase A)

```kotlin
private fun handleCreatePixelStream(args: Map<*, *>?, result: MethodChannel.Result) {
    if (args == null) {
        result.error("INVALID_ARGS", "Arguments required", null)
        return
    }
    
    val trackId = args["trackId"] as? String
    if (trackId == null || trackId.isEmpty()) {
        result.error("INVALID_ARGS", "trackId required", null)
        return
    }
    
    val sinkId = (args["sinkId"] as? String)?.takeIf { it.isNotEmpty() } ?: trackId
    
    // Idempotency check
    if (sinks.containsKey(sinkId)) {
        result.success(mapOf("channelName" to "webrtc_pixel_stream/frames/$sinkId"))
        return
    }
    
    val sink = FlutterRTCStreamingSink(sinkId, messenger)
    sinks[sinkId] = sink
    
    // Return channel name immediately so Dart can start listening
    result.success(mapOf("channelName" to "webrtc_pixel_stream/frames/$sinkId"))
    
    // Attach renderer asynchronously with retries
    Handler(Looper.getMainLooper()).postDelayed({
        attachRenderer(sink, trackId, sinkId, retryCount = 0)
    }, 150)  // Initial delay like iOS
}

private fun attachRenderer(sink: FlutterRTCStreamingSink, trackId: String,
                            sinkId: String, retryCount: Int) {
    // Check if sink was disposed while waiting
    if (!sinks.containsKey(sinkId)) {
        Log.d(TAG, "Sink removed before attachment, aborting for sink: $sinkId")
        return
    }
    
    // ⚠️ AUDIT FIX: getLocalTrack() only finds local camera tracks.
    // Remote tracks need getTrackForId(trackId, peerConnectionId) (private method).
    val peerConnectionId = sinkToPeerConnectionId[sinkId]  // stored at createPixelStream time
    val track = getVideoTrack(trackId, peerConnectionId)
    
    if (track != null) {
        try {
            track.addSink(sink)
            videoTracks[sinkId] = track
            Log.d(TAG, "✅ Renderer attached to track: $trackId")
            return
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception attaching renderer to track: $trackId", e)
            sinks.remove(sinkId)
            return
        }
    }
    
    // Track not found yet — retry if we have attempts remaining
    if (retryCount < MAX_RETRIES) {
        Log.d(TAG, "Track not found (attempt ${retryCount + 1}/$MAX_RETRIES), retrying in 100ms...")
        Handler(Looper.getMainLooper()).postDelayed({
            if (sinks.containsKey(sinkId)) {
                attachRenderer(sink, trackId, sinkId, retryCount + 1)
            }
        }, 100)
    } else {
        Log.e(TAG, "❌ Gave up waiting for track: $trackId after $MAX_RETRIES attempts")
        sinks.remove(sinkId)
    }
}

private fun handleDisposePixelStream(args: Map<*, *>?, result: MethodChannel.Result) {
    val trackId = args?.get("trackId") as? String
    val sinkId = (args?.get("sinkId") as? String) ?: trackId
    
    if (sinkId != null) {
        val sink = sinks.remove(sinkId)
        val track = videoTracks.remove(sinkId)
        
        if (sink != null && track != null) {
            try {
                track.removeSink(sink)
            } catch (e: Exception) {
                Log.e(TAG, "Exception during removeSink: ${e.message}")
            }
            sink.dispose()
        }
    }
    
    result.success(null)
}
```
```

### How Dart handles Phase A — no changes needed

`NativeWebRTCTextureProvider._processNext()` already branches on `bufferIndex`:

```dart
final bool isFFIEvent = event.containsKey('bufferIndex') &&
    _sharedBufferA != null && _sharedBufferB != null;

if (isFFIEvent) {
    img = await decodeFFIFrame(event, _sharedBufferA!, _sharedBufferB!);
} else {
    img = await decodeFrameEvent(event);   // ← Android Phase A lands here
}
```

> **Tip:** Ship Phase A as a release first — it unblocks Android users immediately while
> Phase B (FFI) can ship later as a performance upgrade.

---

## Phase 3 — Milestone B: FFI Double-Buffer Path (1–2 days)

Replaces the byte-copy-over-EventChannel with the same zero-copy FFI approach iOS uses.

### Key insight: pointer sharing works on Android

Dart FFI memory (`calloc<Uint8>`) is allocated in the Dart VM's C heap, which shares the
**same process address space** as the JVM and JNI code. The pointer address integer
`_sharedBufferA!.address` can be cast directly to a native pointer in C++ — no
inter-process tricks needed.

### Changes to `FlutterRTCStreamingSink.kt` for Phase B

```kotlin
class FlutterRTCStreamingSink(
    private val sinkId: String,
    messenger: BinaryMessenger,
    private val bufferAddressA: Long = 0L,   // ← new
    private val bufferAddressB: Long = 0L,   // ← new
    private val bufferSize: Long = 0L        // ← new
) : VideoSink {

    private val writeIndex = AtomicInteger(0)  // Thread-safe index flipping
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onFrame(frame: VideoFrame) {
        val sink = eventSink ?: return
        
        try {
            val i420 = frame.buffer.toI420() ?: return
            val width  = frame.rotatedWidth
            val height = frame.rotatedHeight
            val stride = width * 4

            // Atomically get current index and flip for next frame
            val currentIndex = writeIndex.get()
            val writeAddress = if (currentIndex == 0) bufferAddressA else bufferAddressB
            writeIndex.set(1 - currentIndex)

            // Write directly into Dart-allocated C memory via JNI
            nativeWriteI420ToBGRA(
                i420.dataY, i420.strideY,
                i420.dataU, i420.strideU,
                i420.dataV, i420.strideV,
                writeAddress, stride, width, height
            )
            i420.release()

            // Fire metadata-only event — no pixel bytes!
            val event = mapOf(
                "frameReady"  to true,
                "bufferIndex" to currentIndex,
                "width"       to width,
                "height"      to height,
                "stride"      to stride
            )
            mainHandler.post { sink.success(event) }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing FFI frame", e)
        }
    }

    private external fun nativeWriteI420ToBGRA(
        yBuf: ByteBuffer, strideY: Int,
        uBuf: ByteBuffer, strideU: Int,
        vBuf: ByteBuffer, strideV: Int,
        dstAddress: Long, dstStride: Int,
        width: Int, height: Int
    )
    
    companion object {
        private const val TAG = "FlutterRTCStreamingSink"

        // ⚠️ AUDIT FIX: Do NOT use companion init{} to load the library.
        // init{} runs at class-load time — if the .so doesn't exist (Phase A build)
        // this crashes the app immediately with UnsatisfiedLinkError.
        // Use a guarded lazy load instead:
        @Volatile private var nativeLibLoaded = false

        fun loadNativeIfNeeded() {
            if (!nativeLibLoaded) {
                synchronized(this) {
                    if (!nativeLibLoaded) {
                        System.loadLibrary("webrtc_pixel_stream")
                        nativeLibLoaded = true
                    }
                }
            }
        }
    }
}
```

### JNI helper `webrtc_pixel_stream.cpp`

```cpp
#include <jni.h>
#include <libyuv.h>   // bundled in flutter_webrtc's AAR

extern "C"
JNIEXPORT void JNICALL
Java_com_camertronix_webrtc_1pixel_1stream_FlutterRTCStreamingSink_nativeWriteI420ToBGRA(
    JNIEnv *env, jobject,
    jobject yBuf, jint strideY,
    jobject uBuf, jint strideU,
    jobject vBuf, jint strideV,
    jlong   dstAddress, jint dstStride,
    jint width, jint height)
{
    auto *Y   = (const uint8_t*)env->GetDirectBufferAddress(yBuf);
    auto *U   = (const uint8_t*)env->GetDirectBufferAddress(uBuf);
    auto *V   = (const uint8_t*)env->GetDirectBufferAddress(vBuf);
    auto *dst = reinterpret_cast<uint8_t*>(static_cast<uintptr_t>(dstAddress));

    // I420ToABGR produces BGRA in little-endian memory = ui.PixelFormat.bgra8888
    libyuv::I420ToABGR(Y, strideY, U, strideU, V, strideV,
                        dst, dstStride, width, height);
}
```

> **Note:** If linking libyuv from `flutter_webrtc`'s internal AAR is difficult, the standalone
> Maven artifact `io.github.crow-misia:libyuv-android` is a clean alternative.

### `WebrtcPixelStreamPlugin.kt` — extract FFI addresses (Phase B)

```kotlin
val addressA = (args["memoryAddressA"] as? Number)?.toLong()
val addressB = (args["memoryAddressB"] as? Number)?.toLong()
val size     = (args["memorySize"]     as? Number)?.toLong()

val sink = if (addressA != null && addressB != null && size != null) {
    FlutterRTCStreamingSink(sinkId, messenger, addressA, addressB, size)  // FFI path
} else {
    FlutterRTCStreamingSink(sinkId, messenger)                            // Phase A fallback
}
```

---

## Phase 4 — Dart Platform Guard & pubspec.yaml Update (½ day)

### 4.1 Update `pubspec.yaml` to declare Android support

```yaml
name: webrtc_pixel_stream
description: >
  A lightweight companion plugin that streams raw BGRA pixel data from a
  WebRTC video track via EventChannel. Designed for panorama_viewer /
  aura_sphere_360 but usable by any Flutter app that needs raw frame bytes.
version: 0.2.0
homepage: https://github.com/Camertronix-Cm/aura_sphere_360

environment:
  sdk: '>=3.5.3 <4.0.0'
  flutter: ">=3.3.0"

dependencies:
  flutter:
    sdk: flutter

flutter:
  plugin:
    platforms:
      ios:
        pluginClass: WebrtcPixelStreamPlugin
      android:
        package: com.camertronix.webrtc_pixel_stream
        pluginClass: WebrtcPixelStreamPlugin
```

### 4.2 Add platform guard to Dart FFI allocation

`NativeWebRTCTextureProvider.initialize()` currently allocates FFI memory unconditionally.
Make it conditional so future platforms without FFI support don't receive garbage addresses:

```dart
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

@override
Future<void> initialize() async {
  debugPrint(
      '🔵 [NativeWebRTCTextureProvider] initialize() START — track: $trackId, sink: $_sinkId');

  try {
    // Only allocate FFI buffers on platforms that support it
    final bool useFFI = defaultTargetPlatform == TargetPlatform.iOS ||
                        defaultTargetPlatform == TargetPlatform.android;

    if (useFFI) {
      await _allocateSharedMemory();
    }

    debugPrint('🔵 [NativeWebRTCTextureProvider] Calling createPixelStream…');

    final result = await _pixelStreamMethod
        .invokeMapMethod<String, dynamic>('createPixelStream', {
      'trackId': trackId,
      'sinkId': _sinkId,
      'peerConnectionId': peerConnectionId,
      if (_sharedBufferA != null) 'memoryAddressA': _sharedBufferA!.address,
      if (_sharedBufferB != null) 'memoryAddressB': _sharedBufferB!.address,
      if (_sharedBufferA != null) 'memorySize': _allocatedBytes,
    });
    
    // ... rest of initialize()
  }
}
```

### 4.3 Update documentation

Also update `NATIVE_WEBRTC_USAGE_GUIDE.md`:
- Remove the "Works on Android but not iOS" troubleshooting row.
- Update routing table note to confirm both platforms are supported.

---

## Phase 5 — Testing Checklist

### Functional

- [ ] Android emulator (x86_64): plugin registers, no crash on `createPixelStream`
- [ ] Android device (arm64): stream plays, frames appear in AuraSphere
- [ ] iOS regression: no behaviour change to existing functionality

### Frame rate targets (physical device, 1080p stream)

| Phase | Path | Target |
|---|---|---|
| A (legacy bytes) | EventChannel bytes | ≥ 20 fps |
| B (FFI double-buffer) | FFI zero-copy | ≥ 30 fps |

### Lifecycle & memory

- [ ] Dispose → no memory leak (Android Studio Memory Profiler)
- [ ] WebRTC disconnect → sink removed, no dangling `VideoSink`
- [ ] Re-connect after dispose → new sink created cleanly
- [ ] Fast widget rebuild → idempotency check prevents double sink
- [ ] Track not ready at `createPixelStream` → retry loop handles the race
- [ ] Rotation handling (portrait/landscape) → frames render correctly
- [ ] Background/foreground transitions → stream resumes properly
- [ ] Multiple simultaneous streams → `_sinkId` uniqueness works
- [ ] Memory pressure scenarios → graceful degradation

---

## Phase 6 — Documentation & Release (½ day)

1. `webrtc_pixel_stream/README.md` — add Android support section, note minimum API 21
2. `mobile/NATIVE_WEBRTC_USAGE_GUIDE.md` — remove iOS-only workaround, update routing table
3. Version already bumped to `0.2.0` in Phase 4
4. Add `CHANGELOG.md` entry for Android support
5. Document required permissions in host app's `AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   ```

---

## Summary Timeline

| Phase | Work | Estimate |
|---|---|---|
| 0 | Research `flutter_webrtc` Android API + verification | ½ day |
| 1 | Plugin scaffold + `build.gradle` + proguard | ½ day |
| 2 | Milestone A — legacy bytes EventChannel | 1–2 days |
| 3 | Milestone B — FFI double-buffer + JNI | 1–2 days |
| 4 | Dart platform guard + pubspec.yaml update | ½ day |
| 5 | Testing (including rotation, lifecycle, memory) | 1–2 days |
| 6 | Docs + changelog | ½ day |
| **Total** | | **5–8 days** |

**Buffer:** Add 1-2 days for device-specific quirks and build system issues.
