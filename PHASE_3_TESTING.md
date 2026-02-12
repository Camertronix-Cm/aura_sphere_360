# Phase 3 Testing Guide

## Overview

Phase 3 implements native platform channels for 60 FPS video frame extraction. This guide explains how to test the implementation.

## What to Test

### 1. Platform Channel Activation

The app will automatically try to use platform channels when playing video. Check the console logs:

**Success (Platform Channels Working):**
```
🔧 Attempting PlatformVideoTextureProvider (60 FPS)...
🔌 Registering video player ID: 123
📱 iOS: Registering video player with player ID: 123
✅ Platform channels working! Using 60 FPS native frame extraction
```

**Fallback (Phase 2):**
```
🔧 Attempting PlatformVideoTextureProvider (60 FPS)...
⚠️ Platform channels not available: [error details]
🔧 Falling back to VideoTextureProvider (30 FPS)...
✅ Using screenshot-based approach at 30 FPS
```

### 2. Performance Comparison

| Metric | Phase 2 (Screenshot) | Phase 3 (Platform Channels) |
|--------|---------------------|----------------------------|
| Frame Rate | ~30 FPS | 60 FPS |
| CPU Usage | High | Medium |
| Memory | ~150 MB | ~100 MB |
| Video Widget | Visible (low opacity) | Not needed |

### 3. Visual Quality

Both approaches should show:
- ✅ Smooth 360° panorama
- ✅ Responsive touch controls
- ✅ Proper video playback
- ✅ No visual artifacts

Phase 3 should additionally show:
- ✅ Smoother motion (60 FPS vs 30 FPS)
- ✅ Lower latency
- ✅ No visible video widget in corner

## Testing Steps

### Step 1: Run the Example App

```bash
cd example
flutter run
```

### Step 2: Navigate to Video Example

Tap "Example 6 - Video Panorama" in the menu

### Step 3: Check Console Logs

Look for the initialization logs to see which provider is being used:
- Platform channels: "✅ Platform channels working!"
- Fallback: "✅ Using screenshot-based approach"

### Step 4: Test Functionality

1. **Video Playback**: Video should play automatically
2. **Touch Controls**: Drag to pan around the 360° view
3. **Pinch Zoom**: Pinch to zoom in/out
4. **Play/Pause**: Tap the button to pause/play
5. **Sensor Control**: Enable gyroscope and move device

### Step 5: Performance Profiling

Use Flutter DevTools to check:

```bash
flutter run --profile
# Open DevTools and check:
# - Frame rate (should be 60 FPS with Phase 3)
# - Memory usage (should be lower with Phase 3)
# - CPU usage (should be lower with Phase 3)
```

## Known Issues & Troubleshooting

### Issue: Platform Channels Not Working

**Symptoms:**
- Logs show "⚠️ Platform channels not available"
- Falls back to Phase 2 (30 FPS)

**Possible Causes:**

1. **AVPlayer Access Failed**
   - The iOS code uses reflection to access AVPlayer from video_player plugin
   - If video_player plugin structure changed, this may fail
   - Check logs for: "⚠️ iOS: Could not find AVPlayer for player ID"

2. **Player Not Initialized**
   - VideoPlayerController must be initialized before registration
   - Check that `controller.value.isInitialized` is true

3. **Plugin Not Registered**
   - Ensure plugin is properly registered in pubspec.yaml
   - Try: `flutter clean && flutter pub get`

**Solutions:**

1. **Check video_player version**
   ```bash
   flutter pub deps | grep video_player
   # Should show: video_player 2.9.2 or compatible
   ```

2. **Verify plugin registration**
   ```bash
   # iOS
   cd example/ios
   pod install
   
   # Android
   cd example/android
   ./gradlew clean
   ```

3. **Enable verbose logging**
   - Check Xcode console for detailed iOS logs
   - Check Android Studio logcat for Android logs

### Issue: Video Shows in Corner

**Symptoms:**
- Small video widget visible in bottom-left corner

**Cause:**
- Platform channels not working, using Phase 2 fallback

**Solution:**
- This is expected behavior for Phase 2
- Phase 3 doesn't need the video widget
- Check why platform channels aren't working (see above)

### Issue: Low Frame Rate

**Symptoms:**
- Choppy video playback
- Frame rate below 30 FPS

**Possible Causes:**

1. **Large Video Resolution**
   - Videos larger than 1920x1080 are automatically scaled
   - 4K videos may still be too large

2. **Device Performance**
   - Older devices may struggle with real-time frame extraction

**Solutions:**

1. **Use smaller videos**
   - Recommended: 1920x1080 or lower
   - Test with: 1280x720 for best performance

2. **Check device specs**
   - iPhone 8 or newer recommended
   - Android: Snapdragon 660 or better

## Success Criteria

Phase 3 is working correctly if:

- ✅ Console shows "Platform channels working!"
- ✅ Frame rate is 60 FPS (check DevTools)
- ✅ No video widget visible in corner
- ✅ Smooth 360° panorama playback
- ✅ Touch and sensor controls work
- ✅ Lower CPU/memory usage than Phase 2

## Next Steps After Testing

### If Platform Channels Work:
1. Test with different video formats (MP4, MOV, etc.)
2. Test with different resolutions (720p, 1080p, 4K)
3. Profile memory usage over time
4. Test on multiple devices
5. Complete Android implementation

### If Platform Channels Don't Work:
1. Document the error messages
2. Check video_player plugin version compatibility
3. Consider alternative approaches:
   - Fork video_player to expose AVPlayer
   - Use custom video player plugin
   - Accept Phase 2 as production solution

## Reporting Issues

When reporting issues, include:

1. **Device Info**
   - Device model (e.g., iPhone 13)
   - OS version (e.g., iOS 17.2)
   - Flutter version

2. **Console Logs**
   - Full initialization logs
   - Any error messages
   - Native platform logs (Xcode/Android Studio)

3. **Video Info**
   - Video resolution
   - Video format
   - Video duration
   - File size

4. **Performance Data**
   - Frame rate (from DevTools)
   - Memory usage
   - CPU usage

## Additional Resources

- [PHASE_3_PLATFORM_CHANNELS.md](PHASE_3_PLATFORM_CHANNELS.md) - Technical details
- [PROJECT_STATUS.md](PROJECT_STATUS.md) - Overall project status
- [TESTING_GUIDE.md](TESTING_GUIDE.md) - General testing guide
- [Flutter Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [video_player plugin](https://pub.dev/packages/video_player)

## Contact

For questions or issues:
- Repository: https://github.com/Camertronix-Cm/panorama_viewer
- Branch: `feature/video-support`
