package com.camertronix.webrtc_pixel_stream

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.webrtc.VideoTrack

/**
 * WebrtcPixelStreamPlugin
 * 
 * A lightweight companion plugin that streams raw BGRA pixel data from a
 * WebRTC video track via EventChannel.
 * 
 * This plugin contains zero WebRTC code of its own. It depends on
 * flutter_webrtc and accesses its StateProvider to attach streaming
 * renderers to any video track.
 */
class WebrtcPixelStreamPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var messenger: BinaryMessenger
    
    // We cache the methodCallHandler instance to bypass the StateProvider limitation
    private var cachedHandler: Any? = null
    
    private val sinks = mutableMapOf<String, FlutterRTCStreamingSink>()
    private val videoTracks = mutableMapOf<String, VideoTrack>()
    private val sinkToPeerConnectionId = mutableMapOf<String, String?>()
    
    companion object {
        private const val TAG = "WebrtcPixelStream"
        private const val MAX_RETRIES = 20
        private const val RETRY_DELAY_MS = 100L
        private const val INITIAL_DELAY_MS = 150L
    }
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine called")
        
        // 1. We must retrieve the FlutterWebRTCPlugin instance.
        // FlutterPlugin.FlutterPluginBinding does not expose `flutterEngine` publicly.
        // We reflect its `flutterEngine` private field to get the plugin registry.
        try {
            var engine: Any? = null
            for (field in binding.javaClass.declaredFields) {
                if (field.type.name == "io.flutter.embedding.engine.FlutterEngine") {
                    field.isAccessible = true
                    engine = field.get(binding)
                    break
                }
            }

            if (engine != null) {
                // engine is io.flutter.embedding.engine.FlutterEngine
                // Call engine.getPlugins().get(FlutterWebRTCPlugin.class)
                val getPluginsMethod = engine.javaClass.getMethod("getPlugins")
                val pluginRegistry = getPluginsMethod.invoke(engine)

                val getMethod = pluginRegistry.javaClass.getMethod("get", Class::class.java)
                val webrtcPluginClass = Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
                val webrtcPlugin = getMethod.invoke(pluginRegistry, webrtcPluginClass)

                if (webrtcPlugin != null) {
                    val handlerField = webrtcPluginClass.getDeclaredField("methodCallHandler")
                    handlerField.isAccessible = true
                    // Cache the actual handler (MethodCallHandlerImpl) instead of StateProvider
                    cachedHandler = handlerField.get(webrtcPlugin)
                    Log.d(TAG, "✅ MethodCallHandlerImpl accessed successfully via reflection")
                } else {
                    Log.w(TAG, "⚠️ FlutterWebRTCPlugin not found in engine plugin registry")
                }
            } else {
                Log.w(TAG, "⚠️ Could not find FlutterEngine in FlutterPluginBinding")
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Reflection failed: Could not access WebRTC methodCallHandler: ${e.message}")
        }
        
        channel = MethodChannel(binding.binaryMessenger, "webrtc_pixel_stream/control")
        channel.setMethodCallHandler(this)
        messenger = binding.binaryMessenger
        
        Log.d(TAG, "Plugin initialized")
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine called")
        
        channel.setMethodCallHandler(null)
        
        // Clean up all sinks
        sinks.values.forEach { it.dispose() }
        sinks.clear()
        videoTracks.clear()
        sinkToPeerConnectionId.clear()
        
        Log.d(TAG, "Plugin detached")
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createPixelStream" -> handleCreatePixelStream(call.arguments as? Map<*, *>, result)
            "disposePixelStream" -> handleDisposePixelStream(call.arguments as? Map<*, *>, result)
            else -> result.notImplemented()
        }
    }
    
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
        
        val peerConnectionId = args["peerConnectionId"] as? String
        
        Log.d(TAG, "createPixelStream called - trackId: $trackId, sinkId: $sinkId, pcoId: $peerConnectionId")
        
        // Idempotency check
        if (sinks.containsKey(sinkId)) {
            Log.d(TAG, "Stream already exists for sink: $sinkId")
            result.success(mapOf("channelName" to "webrtc_pixel_stream/frames/$sinkId"))
            return
        }
        
        // Check if handler is available
        if (cachedHandler == null) {
            Log.e(TAG, "WebRTC handler not available - cannot access video tracks")
            result.error("NOT_READY", "WebRTC handler not ready. Ensure flutter_webrtc is initialized.", null)
            return
        }
        
        // Extract FFI buffer addresses (Phase B)
        val addressA = (args["memoryAddressA"] as? Number)?.toLong()
        val addressB = (args["memoryAddressB"] as? Number)?.toLong()
        val size = (args["memorySize"] as? Number)?.toLong()
        
        // Create sink with FFI support if addresses provided
        val sink = if (addressA != null && addressB != null && size != null) {
            Log.d(TAG, "Creating FFI sink - addressA: $addressA, addressB: $addressB, size: $size")
            FlutterRTCStreamingSink(sinkId, messenger, addressA, addressB, size)
        } else {
            Log.d(TAG, "Creating legacy sink (no FFI addresses)")
            FlutterRTCStreamingSink(sinkId, messenger)
        }
        
        sinks[sinkId] = sink
        // Ensure peerConnectionId is stored for tracking
        sinkToPeerConnectionId[sinkId] = peerConnectionId
        
        // Return channel name immediately so Dart can start listening
        result.success(mapOf("channelName" to "webrtc_pixel_stream/frames/$sinkId"))
        
        // Attach renderer asynchronously with retries (mirrors iOS behavior)
        Handler(Looper.getMainLooper()).postDelayed({
            attachRenderer(sink, trackId, peerConnectionId, sinkId, retryCount = 0)
        }, INITIAL_DELAY_MS)
    }
    
    private fun attachRenderer(
        sink: FlutterRTCStreamingSink,
        trackId: String,
        peerConnectionId: String?,
        sinkId: String,
        retryCount: Int
    ) {
        // Check if sink was disposed while waiting
        if (!sinks.containsKey(sinkId)) {
            Log.d(TAG, "Sink removed before attachment, aborting for sink: $sinkId")
            return
        }
        
        // Get track via reflection on MethodCallHandlerImpl.getTrackForId
        val track = getVideoTrack(trackId, peerConnectionId)
        
        if (track != null) {
            try {
                track.addSink(sink)
                videoTracks[sinkId] = track
                Log.d(TAG, "✅ Renderer attached to track: $trackId (sink: $sinkId)")
                return
            } catch (e: Exception) {
                Log.e(TAG, "❌ Exception attaching renderer to track: $trackId", e)
                sinks.remove(sinkId)
                return
            }
        }
        
        // Track not found yet — retry if we have attempts remaining
        if (retryCount < MAX_RETRIES) {
            Log.d(TAG, "Track not found (attempt ${retryCount + 1}/$MAX_RETRIES), retrying in ${RETRY_DELAY_MS}ms...")
            Handler(Looper.getMainLooper()).postDelayed({
                if (sinks.containsKey(sinkId)) {
                    attachRenderer(sink, trackId, peerConnectionId, sinkId, retryCount + 1)
                }
            }, RETRY_DELAY_MS)
        } else {
            Log.e(TAG, "❌ Gave up waiting for track: $trackId after $MAX_RETRIES attempts")
            sinks.remove(sinkId)
        }
    }
    
    // Private reflection helper to properly find remote and local tracks
    private fun getVideoTrack(trackId: String, peerConnectionId: String?): VideoTrack? {
        val handler = cachedHandler ?: return null
        return try {
            // Method signature: VideoTrack getTrackForId(String trackId, String peerConnectionId)
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
    
    private fun handleDisposePixelStream(args: Map<*, *>?, result: MethodChannel.Result) {
        val trackId = args?.get("trackId") as? String
        val sinkId = (args?.get("sinkId") as? String) ?: trackId
        
        Log.d(TAG, "disposePixelStream called - trackId: $trackId, sinkId: $sinkId")
        
        if (sinkId != null) {
            val sink = sinks.remove(sinkId)
            val track = videoTracks.remove(sinkId)
            
            if (sink != null && track != null) {
                try {
                    track.removeSink(sink)
                    Log.d(TAG, "✅ Renderer removed from track")
                } catch (e: Exception) {
                    Log.e(TAG, "Exception during removeSink: ${e.message}")
                }
                sink.dispose()
            }
        }
        
        result.success(null)
    }
}
