package com.camertronix.webrtc_pixel_stream

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import org.webrtc.VideoFrame
import org.webrtc.VideoSink

/**
 * FlutterRTCStreamingSink
 * 
 * An implementation of org.webrtc.VideoSink that converts WebRTC frames to BGRA
 * and streams them via EventChannel.
 * 
 * Phase A: Sends pixel bytes over EventChannel (legacy path)
 * Phase B: Writes to FFI double-buffer and sends metadata only (zero-copy)
 */
class FlutterRTCStreamingSink : VideoSink {
    
    private val sinkId: String
    private val channel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    
    // FFI double-buffer support (Phase B)
    private val bufferAddressA: Long
    private val bufferAddressB: Long
    private val bufferSize: Long
    private val useFFI: Boolean
    private val writeIndex = java.util.concurrent.atomic.AtomicInteger(0)
    
    private var frameCount = 0

    // Legacy constructor (Phase A)
    constructor(sinkId: String, messenger: BinaryMessenger) : this(sinkId, messenger, 0L, 0L, 0L)
    
    // FFI constructor (Phase B)
    constructor(
        sinkId: String,
        messenger: BinaryMessenger,
        bufferAddressA: Long,
        bufferAddressB: Long,
        bufferSize: Long
    ) {
        this.sinkId = sinkId
        this.bufferAddressA = bufferAddressA
        this.bufferAddressB = bufferAddressB
        this.bufferSize = bufferSize
        this.useFFI = bufferAddressA != 0L && bufferAddressB != 0L && bufferSize > 0L
        
        this.channel = EventChannel(messenger, "webrtc_pixel_stream/frames/$sinkId")
        
        if (useFFI) {
            Log.d(TAG, "[$sinkId] FFI mode enabled - addressA: $bufferAddressA, addressB: $bufferAddressB, size: $bufferSize")
            // Load native library for JNI
            try {
                loadNativeIfNeeded()
            } catch (e: Exception) {
                Log.e(TAG, "[$sinkId] Failed to load native library, falling back to legacy mode: ${e.message}")
            }
        } else {
            Log.d(TAG, "[$sinkId] Legacy mode (EventChannel bytes)")
        }
        
        channel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                Log.d(TAG, "[$sinkId] onListen called, setting up eventSink")
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "[$sinkId] onCancel called, removing eventSink")
                eventSink = null
            }
        })
    }

    override fun onFrame(frame: VideoFrame) {
        val sink = eventSink ?: return
        
        frameCount++
        if (frameCount % 30 == 0) {
            Log.d(TAG, "[$sinkId] Frame $frameCount received: ${frame.rotatedWidth}x${frame.rotatedHeight}")
        }
        
        try {
            // Convert frame to I420
            val i420 = frame.buffer.toI420() ?: run {
                Log.w(TAG, "[$sinkId] Failed to convert frame to I420")
                return
            }
            
            val width = frame.rotatedWidth
            val height = frame.rotatedHeight
            val stride = width * 4
            
            if (useFFI && nativeLibLoaded) {
                // Phase B: FFI double-buffer path (zero-copy)
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
                    "frameReady" to true,
                    "bufferIndex" to currentIndex,
                    "width" to width,
                    "height" to height,
                    "stride" to stride
                )
                
                mainHandler.post { sink.success(event) }
                
            } else {
                // Phase A: Legacy EventChannel bytes path
                val bgra = ByteArray(stride * height)
                
                // I420 → BGRA conversion using pure Kotlin
                convertI420ToBGRA(
                    i420.dataY, i420.strideY,
                    i420.dataU, i420.strideU,
                    i420.dataV, i420.strideV,
                    bgra, stride, width, height
                )
                
                i420.release()
                
                val event = mapOf(
                    "frameReady" to true,
                    "width" to width,
                    "height" to height,
                    "stride" to stride,
                    "bytes" to bgra  // legacy path: pixel bytes in the event
                )
                
                mainHandler.post { sink.success(event) }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "[$sinkId] Error processing frame", e)
        }
    }

    fun dispose() {
        Log.d(TAG, "[$sinkId] Disposing sink")
        eventSink = null
        channel.setStreamHandler(null)
    }
    
    /**
     * Convert I420 (YUV420 planar) to BGRA8888.
     * 
     * This is a pure Kotlin implementation that's slower than libyuv but requires
     * no additional dependencies. For Phase B (FFI), we'll use libyuv via JNI.
     * 
     * I420 format:
     * - Y plane: full resolution (width x height)
     * - U plane: quarter resolution (width/2 x height/2)
     * - V plane: quarter resolution (width/2 x height/2)
     * 
     * BGRA format: 4 bytes per pixel (B, G, R, A)
     */
    private fun convertI420ToBGRA(
        yBuffer: java.nio.ByteBuffer, yStride: Int,
        uBuffer: java.nio.ByteBuffer, uStride: Int,
        vBuffer: java.nio.ByteBuffer, vStride: Int,
        bgra: ByteArray, bgraStride: Int,
        width: Int, height: Int
    ) {
        for (row in 0 until height) {
            for (col in 0 until width) {
                // Y is full resolution
                val yIndex = row * yStride + col
                val y = yBuffer.get(yIndex).toInt() and 0xFF
                
                // U and V are quarter resolution (2x2 subsampling)
                val uvRow = row / 2
                val uvCol = col / 2
                val uIndex = uvRow * uStride + uvCol
                val vIndex = uvRow * vStride + uvCol
                val u = uBuffer.get(uIndex).toInt() and 0xFF
                val v = vBuffer.get(vIndex).toInt() and 0xFF
                
                // YUV to RGB conversion (ITU-R BT.601)
                val c = y - 16
                val d = u - 128
                val e = v - 128
                
                var r = (298 * c + 409 * e + 128) shr 8
                var g = (298 * c - 100 * d - 208 * e + 128) shr 8
                var b = (298 * c + 516 * d + 128) shr 8
                
                // Clamp to [0, 255]
                r = r.coerceIn(0, 255)
                g = g.coerceIn(0, 255)
                b = b.coerceIn(0, 255)
                
                // Write BGRA
                val bgraIndex = row * bgraStride + col * 4
                bgra[bgraIndex] = b.toByte()
                bgra[bgraIndex + 1] = g.toByte()
                bgra[bgraIndex + 2] = r.toByte()
                bgra[bgraIndex + 3] = 0xFF.toByte()  // Alpha = opaque
            }
        }
    }
    
    /**
     * JNI method to write I420 frame directly to Dart FFI memory.
     * Implemented in webrtc_pixel_stream.cpp (Phase B).
     */
    private external fun nativeWriteI420ToBGRA(
        yBuf: java.nio.ByteBuffer, strideY: Int,
        uBuf: java.nio.ByteBuffer, strideU: Int,
        vBuf: java.nio.ByteBuffer, strideV: Int,
        dstAddress: Long, dstStride: Int,
        width: Int, height: Int
    )
    
    companion object {
        private const val TAG = "FlutterRTCStreamingSink"
        
        @Volatile
        private var nativeLibLoaded = false
        
        /**
         * Load native library for FFI support.
         * Uses lazy loading to avoid crashes when .so doesn't exist (Phase A builds).
         */
        fun loadNativeIfNeeded() {
            if (!nativeLibLoaded) {
                synchronized(this) {
                    if (!nativeLibLoaded) {
                        try {
                            System.loadLibrary("webrtc_pixel_stream")
                            nativeLibLoaded = true
                            Log.d(TAG, "✅ Native library loaded successfully")
                        } catch (e: UnsatisfiedLinkError) {
                            Log.w(TAG, "⚠️ Native library not available (Phase A build): ${e.message}")
                            throw e
                        }
                    }
                }
            }
        }
    }
}
