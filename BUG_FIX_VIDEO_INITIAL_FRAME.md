# Bug Fix: Video Not Showing Until Play/Pause

## Issue
Video panoramas were not displaying until the user pressed pause and then play again. The panorama would show a black/empty sphere initially.

## Root Cause
The `VideoTextureProvider` was only starting frame extraction when the video was playing. The `_onVideoStateChanged` listener would stop frame extraction when the video was paused, which meant:

1. Video initializes (often in paused state)
2. Frame extraction never starts
3. No frames captured
4. Panorama shows nothing
5. User presses pause → play
6. Frame extraction starts
7. Frames captured
8. Panorama displays correctly

## Solution
Modified `VideoTextureProvider` to:

1. **Start frame extraction immediately** after initialization, regardless of play/pause state
2. **Keep frame extraction running** even when video is paused
3. **Extract first frame immediately** with a small delay to ensure video widget is rendered

### Code Changes

**Before:**
```dart
void _onVideoStateChanged() {
  if (controller.value.isPlaying && _frameTimer == null) {
    _startFrameExtraction();
  } else if (!controller.value.isPlaying && _frameTimer != null) {
    _stopFrameExtraction(); // ❌ This was the problem
  }
}
```

**After:**
```dart
@override
Future<void> initialize() async {
  if (!controller.value.isInitialized) {
    await controller.initialize();
  }
  _isInitialized = true;

  // Start frame extraction immediately ✅
  _startFrameExtraction();

  controller.addListener(_onVideoStateChanged);
  
  // Extract first frame immediately ✅
  await Future.delayed(const Duration(milliseconds: 100));
  _extractFrame();
}

void _onVideoStateChanged() {
  // Keep frame extraction running regardless of play/pause state ✅
  if (_frameTimer == null) {
    _startFrameExtraction();
  }
}
```

## Benefits

1. **Immediate Display**: Video panorama shows immediately after loading
2. **Paused Frames**: Can see video content even when paused
3. **Better UX**: No need to press play/pause to see content
4. **Consistent Behavior**: Works the same for network, local, and asset videos

## Performance Impact

Minimal - frame extraction continues at 30 FPS even when paused, but this is necessary to:
- Show the current frame when paused
- Update panorama when seeking
- Maintain consistent behavior

If performance is a concern, we could optimize by:
- Reducing frame rate when paused (e.g., 5 FPS)
- Stopping extraction after X seconds of pause
- Only extracting on demand when paused

But for now, continuous extraction provides the best user experience.

## Testing

Tested with:
- ✅ Network videos
- ✅ Local file videos
- ✅ Both play and pause states
- ✅ Seeking while paused
- ✅ iOS device

## Related Files
- `lib/src/video_texture_provider.dart`
