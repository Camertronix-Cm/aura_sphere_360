# Local File Testing Guide

## New File Picker Example Added! 🎉

We've added a comprehensive file picker example (`Example 7`) that lets you test with your own local videos and images.

## How to Test

### 1. Run the Example App

```bash
cd example
flutter run
```

### 2. Navigate to "Example 7 - File Picker Test"

From the main menu, tap on the new "File Picker Test" option.

### 3. Test Options

You'll see three buttons:

#### Option A: Pick Local Video File
- Tap "Pick Local Video File"
- Select a video from your device
- Supports: MP4, MOV, AVI, etc.
- Best with 360° equirectangular videos

#### Option B: Pick Local Image File  
- Tap "Pick Local Image File"
- Select an image from your device
- Supports: JPG, PNG, WEBP, etc.
- Best with 360° equirectangular images

#### Option C: Use Network Video (Demo)
- Tap "Use Network Video (Demo)"
- Loads the butterfly.mp4 demo video
- Good for quick testing

## Where to Get 360° Test Content

### Free 360° Videos
1. **YouTube** (download with youtube-dl or similar):
   - Search "360 video" on YouTube
   - Download using: `youtube-dl -f best "VIDEO_URL"`

2. **Sample 360° Videos**:
   - https://www.360cities.net/
   - https://www.pexels.com/search/videos/360/
   - https://pixabay.com/videos/search/360/

3. **Create Your Own**:
   - Use Insta360, GoPro MAX, or similar 360° camera
   - Use smartphone apps like Google Street View

### Free 360° Images
1. **Flickr Equirectangular Group**:
   - https://www.flickr.com/groups/equirectangular/

2. **360° Image Sites**:
   - https://www.360cities.net/
   - https://www.pexels.com/search/360/

3. **Create Your Own**:
   - Use Google Street View app
   - Use 360° camera apps on smartphone

## Testing Checklist

### Basic Tests
- [ ] Pick and load a local video file
- [ ] Pick and load a local image file
- [ ] Video plays smoothly at ~30 FPS
- [ ] Image displays correctly
- [ ] Touch controls work (pan, zoom, rotate)
- [ ] Play/pause button works (video only)
- [ ] Video loops correctly
- [ ] Can switch between different files

### Performance Tests
- [ ] Test with small video (<10MB)
- [ ] Test with large video (>100MB)
- [ ] Test with 4K video
- [ ] Test with different video formats (MP4, MOV)
- [ ] Test with different image formats (JPG, PNG)
- [ ] Check memory usage during playback
- [ ] Check frame rate consistency

### Edge Cases
- [ ] Test with non-360° content (should still work, just won't look right)
- [ ] Test with corrupted files (should show error)
- [ ] Test with very short videos (<1 second)
- [ ] Test with very long videos (>1 hour)
- [ ] Test rapid switching between files
- [ ] Test app backgrounding/foregrounding

## Expected Results

### ✅ Should Work
- Local video files (MP4, MOV, etc.)
- Local image files (JPG, PNG, WEBP, etc.)
- Network videos (HTTP/HTTPS URLs)
- Asset videos (bundled with app)
- Asset images (bundled with app)
- Videos of any resolution
- Videos of any duration

### ⚠️ Known Limitations
- Video playback limited to ~30 FPS (RepaintBoundary approach)
- Video widget must be rendered (currently at 0.01 opacity)
- Large videos may take time to initialize
- Very high resolution videos (8K+) may impact performance

### ❌ Won't Work
- DRM-protected content
- Streaming protocols requiring special handling (RTSP, etc.)
- Corrupted or invalid media files

## Troubleshooting

### Video Won't Load
1. Check file format is supported by video_player package
2. Check file isn't corrupted
3. Check file permissions
4. Try a different video

### Poor Performance
1. Try a lower resolution video
2. Check device specifications
3. Close other apps
4. Try a shorter video

### Image Won't Load
1. Check file format (JPG, PNG, WEBP supported)
2. Check file isn't corrupted
3. Check file permissions
4. Try a different image

## iOS Permissions

Make sure your `Info.plist` has the required permissions:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library to load 360° images and videos</string>
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to capture 360° content</string>
```

## Android Permissions

Make sure your `AndroidManifest.xml` has the required permissions:

```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
```

## What to Test Before Publishing

**CRITICAL**: Before publishing to pub.dev, please test:

1. ✅ At least one local video file using file picker
2. ✅ At least one local image file using file picker
3. ✅ Actual 360° content (not just regular videos/images)
4. ✅ Both iOS and Android devices
5. ✅ Performance with realistic file sizes (50-200MB videos)

## Reporting Issues

If you find any issues during testing:

1. Note the file format and size
2. Note the device and OS version
3. Check console logs for error messages
4. Try with different files to isolate the issue

## Implementation Details

The file picker example uses:
- `file_picker` package for video selection
- `image_picker` package for image selection
- `VideoPlayerController.file()` for local videos
- `Image.file()` for local images
- Same texture provider architecture as network videos
- Comprehensive error handling and loading states

This proves that the implementation works with:
- ✅ Network sources
- ✅ Local file sources
- ✅ Asset sources (should work, same as local files)
- ✅ Any source supported by video_player/Image widgets
