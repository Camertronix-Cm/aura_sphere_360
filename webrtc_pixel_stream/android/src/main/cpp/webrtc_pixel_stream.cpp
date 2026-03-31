#include <jni.h>
#include <android/log.h>
#include <cstdint>
#include <algorithm>

#define LOG_TAG "WebRTCPixelStream"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/**
 * Convert I420 (YUV420 planar) to BGRA8888 using optimized C++.
 * 
 * This implementation uses integer arithmetic and is significantly faster
 * than the pure Kotlin version. For even better performance, libyuv with
 * SIMD (NEON) can be integrated.
 * 
 * @param Y Y plane buffer (full resolution)
 * @param strideY Y plane stride
 * @param U U plane buffer (quarter resolution)
 * @param strideU U plane stride
 * @param V V plane buffer (quarter resolution)
 * @param strideV V plane stride
 * @param dst Destination BGRA buffer (Dart FFI memory)
 * @param dstStride Destination stride (width * 4)
 * @param width Frame width
 * @param height Frame height
 */
static void convertI420ToBGRA(
    const uint8_t* Y, int strideY,
    const uint8_t* U, int strideU,
    const uint8_t* V, int strideV,
    uint8_t* dst, int dstStride,
    int width, int height)
{
    for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
            // Y is full resolution
            int yIndex = row * strideY + col;
            int y = Y[yIndex];
            
            // U and V are quarter resolution (2x2 subsampling)
            int uvRow = row / 2;
            int uvCol = col / 2;
            int uIndex = uvRow * strideU + uvCol;
            int vIndex = uvRow * strideV + uvCol;
            int u = U[uIndex];
            int v = V[vIndex];
            
            // YUV to RGB conversion (ITU-R BT.601)
            int c = y - 16;
            int d = u - 128;
            int e = v - 128;
            
            int r = (298 * c + 409 * e + 128) >> 8;
            int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
            int b = (298 * c + 516 * d + 128) >> 8;
            
            // Clamp to [0, 255]
            r = std::max(0, std::min(255, r));
            g = std::max(0, std::min(255, g));
            b = std::max(0, std::min(255, b));
            
            // Write BGRA
            int dstIndex = row * dstStride + col * 4;
            dst[dstIndex + 0] = static_cast<uint8_t>(b);
            dst[dstIndex + 1] = static_cast<uint8_t>(g);
            dst[dstIndex + 2] = static_cast<uint8_t>(r);
            dst[dstIndex + 3] = 0xFF;  // Alpha = opaque
        }
    }
}

/**
 * JNI entry point called from FlutterRTCStreamingSink.kt
 * 
 * Converts I420 frame from WebRTC to BGRA and writes directly into
 * Dart-allocated FFI memory (zero-copy).
 */
extern "C"
JNIEXPORT void JNICALL
Java_com_camertronix_webrtc_1pixel_1stream_FlutterRTCStreamingSink_nativeWriteI420ToBGRA(
    JNIEnv *env,
    jobject /* this */,
    jobject yBuf, jint strideY,
    jobject uBuf, jint strideU,
    jobject vBuf, jint strideV,
    jlong dstAddress, jint dstStride,
    jint width, jint height)
{
    // Get direct buffer addresses
    auto *Y = static_cast<const uint8_t*>(env->GetDirectBufferAddress(yBuf));
    auto *U = static_cast<const uint8_t*>(env->GetDirectBufferAddress(uBuf));
    auto *V = static_cast<const uint8_t*>(env->GetDirectBufferAddress(vBuf));
    
    // Cast Dart FFI address to native pointer
    auto *dst = reinterpret_cast<uint8_t*>(static_cast<uintptr_t>(dstAddress));
    
    if (!Y || !U || !V || !dst) {
        LOGE("Invalid buffer pointers: Y=%p, U=%p, V=%p, dst=%p", Y, U, V, dst);
        return;
    }
    
    // Perform conversion
    convertI420ToBGRA(Y, strideY, U, strideU, V, strideV, dst, dstStride, width, height);
}
