#!/bin/bash
# Phase 1 Verification Script

echo "🔍 Verifying Phase 1 Implementation..."
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✅${NC} $1"
        ((PASS++))
    else
        echo -e "${RED}❌${NC} $1 (missing)"
        ((FAIL++))
    fi
}

check_dir() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✅${NC} $1/"
        ((PASS++))
    else
        echo -e "${RED}❌${NC} $1/ (missing)"
        ((FAIL++))
    fi
}

echo "📁 Directory Structure:"
check_dir "android"
check_dir "android/src"
check_dir "android/src/main"
check_dir "android/src/main/kotlin"
check_dir "android/src/main/kotlin/com/camertronix/webrtc_pixel_stream"

echo ""
echo "📄 Required Files:"
check_file "android/build.gradle"
check_file "android/proguard-rules.pro"
check_file "android/src/main/AndroidManifest.xml"
check_file "android/src/main/kotlin/com/camertronix/webrtc_pixel_stream/WebrtcPixelStreamPlugin.kt"
check_file "android/src/main/kotlin/com/camertronix/webrtc_pixel_stream/FlutterRTCStreamingSink.kt"

echo ""
echo "🔧 Configuration Files:"
check_file "pubspec.yaml"

echo ""
echo "📊 Code Statistics:"
echo -e "${YELLOW}Lines of Kotlin code:${NC}"
wc -l android/src/main/kotlin/com/camertronix/webrtc_pixel_stream/*.kt 2>/dev/null || echo "  (files not found)"

echo ""
echo "🔍 Checking pubspec.yaml for Android platform..."
if grep -q "android:" pubspec.yaml; then
    echo -e "${GREEN}✅${NC} Android platform declared in pubspec.yaml"
    ((PASS++))
else
    echo -e "${RED}❌${NC} Android platform not declared in pubspec.yaml"
    ((FAIL++))
fi

echo ""
echo "🔍 Checking build.gradle for required dependencies..."
if grep -q "io.github.webrtc-sdk:android" android/build.gradle 2>/dev/null; then
    echo -e "${GREEN}✅${NC} WebRTC SDK dependency found"
    ((PASS++))
else
    echo -e "${RED}❌${NC} WebRTC SDK dependency missing"
    ((FAIL++))
fi

if grep -q "minSdkVersion 21" android/build.gradle 2>/dev/null; then
    echo -e "${GREEN}✅${NC} minSdkVersion 21 configured"
    ((PASS++))
else
    echo -e "${RED}❌${NC} minSdkVersion not set to 21"
    ((FAIL++))
fi

echo ""
echo "🔍 Checking proguard rules..."
if grep -q "StateProvider" android/proguard-rules.pro 2>/dev/null; then
    echo -e "${GREEN}✅${NC} StateProvider proguard rule found"
    ((PASS++))
else
    echo -e "${RED}❌${NC} StateProvider proguard rule missing"
    ((FAIL++))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✅ Phase 1 verification PASSED!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. cd to mobile app directory"
    echo "  2. Run: flutter pub get"
    echo "  3. Run: flutter build apk --debug"
    echo "  4. Check logs for: 'StateProvider accessed successfully'"
    exit 0
else
    echo -e "${RED}❌ Phase 1 verification FAILED!${NC}"
    echo "Please fix the issues above before proceeding."
    exit 1
fi
