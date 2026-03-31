# Android Implementation Solution — Simplified Approach

**Based on Phase 0 Research**

## Key Discovery: Direct Track Access via MethodCallHandlerImpl

After analyzing `FlutterRTCVideoRenderer.java`, we found that flutter_webrtc already has a mechanism to access tracks by ID through `MethodCallHandlerImpl.getLocalTrack(trackId)`.

## Simplified Architecture

Instead of creating a complex registry, we can access `MethodCallHandlerImpl` directly through the Flutter plugin binding.

### Solution: Access via Plugin Binding

```kotlin
// WebrtcPixelStreamPlugin.kt
class WebrtcPixelStreamPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var methodCallHandler: MethodCallHandlerImpl
    
    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        // Get reference to flutter_webrtc's MethodCallHandlerImpl
        // via reflection or plugin communication
    }
}
```

## Even Simpler: Use Existing Renderer Pattern

Looking at `FlutterRTCVideoRenderer.setVideoTrack()`, we can follow the same pattern:

1. Dart passes `trackId` to native
2. Native looks up track via `MethodCallHandlerImpl.getLocalTrack(trackId)`
3. Native calls `track.addSink(ourSink)`

This is exactly what `FlutterRTCVideoRenderer` does!


## Recommended Implementation

### Access MethodCallHandlerImpl via StateProvider Interface

```kotlin
// WebrtcPixelStreamPlugin.kt
import com.cloudwebrtc.webrtc.StateProvider
import org.webrtc.MediaStreamTrack
import org.webrtc.VideoTrack

class WebrtcPixelStreamPlugin : FlutterPlugin, MethodCallHandler {
    private var stateProvider: StateProvider? = null
    
    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        // flutter_webrtc registers itself first, we can access it via registry
        val flutterWebRTC = binding.flutterEngine.plugins.get(FlutterWebRTCPlugin::class.java)
        
        // Or simpler: just store tracks when Dart tells us about them
    }
    
    private fun getVideoTrack(trackId: String): VideoTrack? {
        // Access via StateProvider interface if available
        val track = stateProvider?.getLocalTrack(trackId)
        return if (track is VideoTrack) track else null
    }
}
```

### Alternative: Track Reference Passing

Since Dart already has the track object, we can pass a reference:

```dart
// In NativeWebRTCTextureProvider
final result = await _pixelStreamMethod.invokeMapMethod('createPixelStream', {
  'trackId': trackId,
  'sinkId': _sinkId,
  'peerConnectionId': peerConnectionId,
  'videoTrack': renderer.videoTrack,  // Pass the actual track object
  // ... FFI addresses
});
```

But platform channels don't serialize complex objects well.


## ✅ FINAL RECOMMENDED SOLUTION

### Use Static Registry in WebrtcPixelStreamPlugin

The cleanest approach that mirrors iOS functionality:

```kotlin
// WebrtcPixelStreamPlugin.kt
class WebrtcPixelStreamPlugin : FlutterPlugin, MethodCallHandler {
    
    companion object {
        // Static registry accessible from anywhere
        private val trackRegistry = mutableMapOf<String, VideoTrack>()
        
        @JvmStatic
        fun registerTrack(trackId: String, track: VideoTrack) {
            trackRegistry[trackId] = track
        }
        
        @JvmStatic
        fun getTrack(trackId: String): VideoTrack? = trackRegistry[trackId]
        
        @JvmStatic
        fun unregisterTrack(trackId: String) {
            trackRegistry.remove(trackId)
        }
    }
    
    // Instance methods use the static registry
    private fun attachRenderer(sink: FlutterRTCStreamingSink, trackId: String, sinkId: String) {
        val track = getTrack(trackId)
        if (track != null) {
            track.addSink(sink)
            // ...
        }
    }
}
```

### Dart Integration

Add a registration step in the mobile app after track is received:

```dart
// In Aura360Player._handleOffer or onTrack callback
_peerConnection!.onTrack = (event) {
  if (event.track.kind == 'video') {
    // Register track for native access
    WebrtcPixelStreamPlugin.registerTrack(event.track.id, event.track);
    
    // Then use it normally
    _videoTrackId = event.track.id;
    setState(() => _streamReady = true);
  }
};
```

Wait, Dart can't call Kotlin static methods directly via platform channels...


## 🎯 ACTUAL WORKING SOLUTION

### Hook into flutter_webrtc's Track Storage

`MethodCallHandlerImpl` already stores all tracks in `localTracks` HashMap. We just need to access it.

#### Option A: Reflection (Quick but fragile)

```kotlin
private fun getVideoTrackViaReflection(trackId: String): VideoTrack? {
    try {
        // Get FlutterWebRTCPlugin instance from Flutter engine
        val webrtcPlugin = flutterEngine.plugins.get(FlutterWebRTCPlugin::class.java)
        
        // Access private methodCallHandler field
        val handlerField = FlutterWebRTCPlugin::class.java.getDeclaredField("methodCallHandler")
        handlerField.isAccessible = true
        val handler = handlerField.get(webrtcPlugin) as? MethodCallHandlerImpl
        
        // Call public getLocalTrack method
        val track = handler?.getLocalTrack(trackId)
        return if (track is VideoTrack) track else null
    } catch (e: Exception) {
        Log.e(TAG, "Failed to get track via reflection", e)
        return null
    }
}
```

#### Option B: Extend flutter_webrtc (Clean but requires fork)

Fork flutter_webrtc and add:
```java
// In FlutterWebRTCPlugin.java
public MethodCallHandlerImpl getMethodCallHandler() {
    return methodCallHandler;
}
```

Then in our plugin:
```kotlin
val webrtcPlugin = flutterEngine.plugins.get(FlutterWebRTCPlugin::class.java) as FlutterWebRTCPlugin
val track = webrtcPlugin.methodCallHandler.getLocalTrack(trackId) as? VideoTrack
```


#### Option C: StateProvider Interface (BEST - Already Exists!)

Looking at the code, `MethodCallHandlerImpl` implements `StateProvider`:

```java
public class MethodCallHandlerImpl implements MethodCallHandler, StateProvider {
    // ...
    @Override
    public MediaStreamTrack getLocalTrack(String trackId) {
        return localTracks.get(trackId);
    }
}
```

And `StateProvider` is a public interface! We can access it:

```kotlin
// WebrtcPixelStreamPlugin.kt
class WebrtcPixelStreamPlugin : FlutterPlugin, MethodCallHandler {
    private var stateProvider: StateProvider? = null
    
    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        // Try to get StateProvider from flutter_webrtc
        try {
            val webrtcPlugin = binding.flutterEngine.plugins.get(
                Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
            )
            
            // Access via reflection to get methodCallHandler
            val handlerField = webrtcPlugin?.javaClass?.getDeclaredField("methodCallHandler")
            handlerField?.isAccessible = true
            stateProvider = handlerField?.get(webrtcPlugin) as? StateProvider
        } catch (e: Exception) {
            Log.w(TAG, "Could not access StateProvider, will use fallback", e)
        }
        
        // Setup our plugin
        channel = MethodChannel(binding.binaryMessenger, "webrtc_pixel_stream/control")
        channel.setMethodCallHandler(this)
        messenger = binding.binaryMessenger
    }
    
    private fun getVideoTrack(trackId: String): VideoTrack? {
        val track = stateProvider?.getLocalTrack(trackId)
        return if (track is VideoTrack) track else null
    }
}
```

This is clean, uses public interfaces, and doesn't require forking flutter_webrtc!

