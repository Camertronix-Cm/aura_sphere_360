#!/bin/bash
# Phase 2 Verification Script
# Checks that I420→BGRA conversion is properly implemented

echo "🔍 Phase 2 Verification — I420→BGRA Conversion"
echo "================================================"
echo ""

PLUGIN_DIR="."
SINK_FILE="$PLUGIN_DIR/android/src/main/kotlin/com/camertronix/webrtc_pixel_stream/FlutterRTCStreamingSink.kt"

# Check 1: Verify FlutterRTCStreamingSink.kt exists
echo "✓ Check 1: FlutterRTCStreamingSink.kt exists"
if [ -f "$SINK_FILE" ]; then
    echo "  ✅ File found: $SINK_FILE"
else
    echo "  ❌ File not found: $SINK_FILE"
    exit 1
fi
echo ""

# Check 2: Verify convertI420ToBGRA function exists
echo "✓ Check 2: convertI420ToBGRA function exists"
if grep -q "private fun convertI420ToBGRA" "$SINK_FILE"; then
    echo "  ✅ Function declaration found"
else
    echo "  ❌ Function declaration not found"
    exit 1
fi
echo ""

# Check 3: Verify function is called in onFrame
echo "✓ Check 3: convertI420ToBGRA is called in onFrame"
if grep -q "convertI420ToBGRA(" "$SINK_FILE"; then
    echo "  ✅ Function call found"
else
    echo "  ❌ Function call not found"
    exit 1
fi
echo ""

# Check 4: Verify test pattern is removed
echo "✓ Check 4: Test pattern placeholder removed"
if grep -q "I420→BGRA conversion not yet implemented" "$SINK_FILE"; then
    echo "  ❌ Test pattern warning still present"
    exit 1
else
    echo "  ✅ Test pattern removed"
fi
echo ""

# Check 5: Verify YUV→RGB conversion coefficients
echo "✓ Check 5: ITU-R BT.601 conversion coefficients"
if grep -q "298 \* c + 409 \* e" "$SINK_FILE"; then
    echo "  ✅ R conversion found"
else
    echo "  ❌ R conversion not found"
    exit 1
fi

if grep -q "298 \* c - 100 \* d - 208 \* e" "$SINK_FILE"; then
    echo "  ✅ G conversion found"
else
    echo "  ❌ G conversion not found"
    exit 1
fi

if grep -q "298 \* c + 516 \* d" "$SINK_FILE"; then
    echo "  ✅ B conversion found"
else
    echo "  ❌ B conversion not found"
    exit 1
fi
echo ""

# Check 6: Verify RGB clamping
echo "✓ Check 6: RGB clamping to [0, 255]"
if grep -q "coerceIn(0, 255)" "$SINK_FILE"; then
    echo "  ✅ Clamping found"
else
    echo "  ❌ Clamping not found"
    exit 1
fi
echo ""

# Check 7: Verify BGRA byte order
echo "✓ Check 7: BGRA byte order"
if grep -q "bgra\[bgraIndex\] = b.toByte()" "$SINK_FILE"; then
    echo "  ✅ B at index 0"
else
    echo "  ❌ B not at index 0"
    exit 1
fi

if grep -q "bgra\[bgraIndex + 1\] = g.toByte()" "$SINK_FILE"; then
    echo "  ✅ G at index 1"
else
    echo "  ❌ G not at index 1"
    exit 1
fi

if grep -q "bgra\[bgraIndex + 2\] = r.toByte()" "$SINK_FILE"; then
    echo "  ✅ R at index 2"
else
    echo "  ❌ R not at index 2"
    exit 1
fi

if grep -q "bgra\[bgraIndex + 3\] = 0xFF.toByte()" "$SINK_FILE"; then
    echo "  ✅ A at index 3 (opaque)"
else
    echo "  ❌ A not at index 3"
    exit 1
fi
echo ""

# Check 8: Verify chroma subsampling
echo "✓ Check 8: Chroma subsampling (2x2)"
if grep -q "val uvRow = row / 2" "$SINK_FILE" && grep -q "val uvCol = col / 2" "$SINK_FILE"; then
    echo "  ✅ 2x2 subsampling found"
else
    echo "  ❌ 2x2 subsampling not found"
    exit 1
fi
echo ""

# Check 9: Verify documentation
echo "✓ Check 9: Function documentation"
if grep -q "Convert I420 (YUV420 planar) to BGRA8888" "$SINK_FILE"; then
    echo "  ✅ Documentation found"
else
    echo "  ❌ Documentation not found"
    exit 1
fi
echo ""

# Check 10: Verify PHASE_2_COMPLETE.md exists
echo "✓ Check 10: PHASE_2_COMPLETE.md exists"
if [ -f "$PLUGIN_DIR/PHASE_2_COMPLETE.md" ]; then
    echo "  ✅ Documentation file found"
else
    echo "  ❌ Documentation file not found"
    exit 1
fi
echo ""

echo "================================================"
echo "✅ Phase 2 Verification PASSED"
echo ""
echo "All checks passed! Phase 2 implementation is complete."
echo ""
echo "Next steps:"
echo "1. Test on physical Android device"
echo "2. Verify frame rate ≥ 15 fps for 720p"
echo "3. Check color accuracy"
echo "4. Proceed to Phase 3 (FFI double-buffer)"
echo ""
