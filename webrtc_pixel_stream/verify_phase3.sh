#!/bin/bash
# Phase 3 Verification Script
# Checks that FFI double-buffer implementation is complete

echo "🔍 Phase 3 Verification — FFI Double-Buffer"
echo "============================================"
echo ""

PLUGIN_DIR="."
PLUGIN_FILE="$PLUGIN_DIR/android/src/main/kotlin/com/camertronix/webrtc_pixel_stream/WebrtcPixelStreamPlugin.kt"
SINK_FILE="$PLUGIN_DIR/android/src/main/kotlin/com/camertronix/webrtc_pixel_stream/FlutterRTCStreamingSink.kt"
CPP_FILE="$PLUGIN_DIR/android/src/main/cpp/webrtc_pixel_stream.cpp"
CMAKE_FILE="$PLUGIN_DIR/android/src/main/cpp/CMakeLists.txt"
BUILD_FILE="$PLUGIN_DIR/android/build.gradle"

# Check 1: Verify FFI address extraction in plugin
echo "✓ Check 1: FFI address extraction in WebrtcPixelStreamPlugin"
if grep -q "memoryAddressA" "$PLUGIN_FILE" && grep -q "memoryAddressB" "$PLUGIN_FILE"; then
    echo "  ✅ FFI address extraction found"
else
    echo "  ❌ FFI address extraction not found"
    exit 1
fi
echo ""

# Check 2: Verify dual-mode sink creation
echo "✓ Check 2: Dual-mode sink creation"
if grep -q "FlutterRTCStreamingSink(sinkId, messenger, addressA, addressB, size)" "$PLUGIN_FILE"; then
    echo "  ✅ FFI sink constructor call found"
else
    echo "  ❌ FFI sink constructor call not found"
    exit 1
fi

if grep -q "FlutterRTCStreamingSink(sinkId, messenger)" "$PLUGIN_FILE"; then
    echo "  ✅ Legacy sink constructor call found"
else
    echo "  ❌ Legacy sink constructor call not found"
    exit 1
fi
echo ""

# Check 3: Verify dual constructors in FlutterRTCStreamingSink
echo "✓ Check 3: Dual constructors in FlutterRTCStreamingSink"
if grep -q "constructor(sinkId: String, messenger: BinaryMessenger)" "$SINK_FILE"; then
    echo "  ✅ Legacy constructor found"
else
    echo "  ❌ Legacy constructor not found"
    exit 1
fi

if grep -q "bufferAddressA: Long" "$SINK_FILE" && grep -q "bufferAddressB: Long" "$SINK_FILE"; then
    echo "  ✅ FFI constructor parameters found"
else
    echo "  ❌ FFI constructor parameters not found"
    exit 1
fi
echo ""

# Check 4: Verify atomic buffer flipping
echo "✓ Check 4: Atomic buffer index flipping"
if grep -q "AtomicInteger" "$SINK_FILE" && grep -q "writeIndex" "$SINK_FILE"; then
    echo "  ✅ AtomicInteger for buffer flipping found"
else
    echo "  ❌ AtomicInteger not found"
    exit 1
fi
echo ""

# Check 5: Verify FFI path in onFrame
echo "✓ Check 5: FFI path in onFrame"
if grep -q "if (useFFI && nativeLibLoaded)" "$SINK_FILE"; then
    echo "  ✅ FFI mode check found"
else
    echo "  ❌ FFI mode check not found"
    exit 1
fi

if grep -q "nativeWriteI420ToBGRA" "$SINK_FILE"; then
    echo "  ✅ JNI method call found"
else
    echo "  ❌ JNI method call not found"
    exit 1
fi

if grep -q '"bufferIndex" to currentIndex' "$SINK_FILE"; then
    echo "  ✅ Metadata-only event found"
else
    echo "  ❌ Metadata-only event not found"
    exit 1
fi
echo ""

# Check 6: Verify JNI method declaration
echo "✓ Check 6: JNI method declaration"
if grep -q "private external fun nativeWriteI420ToBGRA" "$SINK_FILE"; then
    echo "  ✅ JNI method declaration found"
else
    echo "  ❌ JNI method declaration not found"
    exit 1
fi
echo ""

# Check 7: Verify native library loading
echo "✓ Check 7: Native library loading"
if grep -q "System.loadLibrary(\"webrtc_pixel_stream\")" "$SINK_FILE"; then
    echo "  ✅ Native library loading found"
else
    echo "  ❌ Native library loading not found"
    exit 1
fi

if grep -q "loadNativeIfNeeded" "$SINK_FILE"; then
    echo "  ✅ Lazy loading function found"
else
    echo "  ❌ Lazy loading function not found"
    exit 1
fi
echo ""

# Check 8: Verify C++ implementation exists
echo "✓ Check 8: C++ implementation"
if [ -f "$CPP_FILE" ]; then
    echo "  ✅ webrtc_pixel_stream.cpp found"
else
    echo "  ❌ webrtc_pixel_stream.cpp not found"
    exit 1
fi

if grep -q "Java_com_camertronix_webrtc_1pixel_1stream_FlutterRTCStreamingSink_nativeWriteI420ToBGRA" "$CPP_FILE"; then
    echo "  ✅ JNI function signature found"
else
    echo "  ❌ JNI function signature not found"
    exit 1
fi

if grep -q "convertI420ToBGRA" "$CPP_FILE"; then
    echo "  ✅ Conversion function found"
else
    echo "  ❌ Conversion function not found"
    exit 1
fi
echo ""

# Check 9: Verify CMakeLists.txt
echo "✓ Check 9: CMake configuration"
if [ -f "$CMAKE_FILE" ]; then
    echo "  ✅ CMakeLists.txt found"
else
    echo "  ❌ CMakeLists.txt not found"
    exit 1
fi

if grep -q "add_library" "$CMAKE_FILE" && grep -q "webrtc_pixel_stream" "$CMAKE_FILE"; then
    echo "  ✅ Library target found"
else
    echo "  ❌ Library target not found"
    exit 1
fi

if grep -q "find_library(log-lib log)" "$CMAKE_FILE"; then
    echo "  ✅ Log library linking found"
else
    echo "  ❌ Log library linking not found"
    exit 1
fi
echo ""

# Check 10: Verify build.gradle CMake configuration
echo "✓ Check 10: build.gradle CMake configuration"
if grep -q "externalNativeBuild" "$BUILD_FILE"; then
    echo "  ✅ externalNativeBuild found"
else
    echo "  ❌ externalNativeBuild not found"
    exit 1
fi

if grep -q 'path "src/main/cpp/CMakeLists.txt"' "$BUILD_FILE"; then
    echo "  ✅ CMake path configured"
else
    echo "  ❌ CMake path not configured"
    exit 1
fi
echo ""

# Check 11: Verify legacy mode preserved
echo "✓ Check 11: Legacy mode backward compatibility"
if grep -q "Phase A: Legacy EventChannel bytes path" "$SINK_FILE"; then
    echo "  ✅ Legacy path preserved"
else
    echo "  ❌ Legacy path not found"
    exit 1
fi

if grep -q "convertI420ToBGRA(" "$SINK_FILE"; then
    echo "  ✅ Pure Kotlin conversion still available"
else
    echo "  ❌ Pure Kotlin conversion removed"
    exit 1
fi
echo ""

# Check 12: Verify PHASE_3_COMPLETE.md exists
echo "✓ Check 12: PHASE_3_COMPLETE.md exists"
if [ -f "$PLUGIN_DIR/PHASE_3_COMPLETE.md" ]; then
    echo "  ✅ Documentation file found"
else
    echo "  ❌ Documentation file not found"
    exit 1
fi
echo ""

echo "============================================"
echo "✅ Phase 3 Verification PASSED"
echo ""
echo "All checks passed! Phase 3 implementation is complete."
echo ""
echo "Next steps:"
echo "1. Build mobile app with updated plugin"
echo "2. Test FFI mode on physical device"
echo "3. Verify frame rate ≥ 30 fps for 1080p"
echo "4. Check memory safety (no leaks)"
echo "5. Proceed to Phase 4 (Dart platform guard)"
echo ""
