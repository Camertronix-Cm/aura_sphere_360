## 2.1.0
* **NEW: Video Support** - Added support for 360° video panoramas
  * Play local video files, network URLs, and asset videos
  * Smooth 30 FPS video playback optimized for 360° viewing
  * Full touch controls (pan, zoom, rotate) work with videos
  * Sensor controls (gyroscope) work with videos
  * Auto-scaling for videos larger than 1920x1080
  * New `videoPlayerController` parameter for PanoramaViewer
* **Architecture**: Clean texture provider abstraction
  * Separate providers for images and videos
  * Easy to extend for future sources (WebRTC, etc.)
* **Dependencies**: Added video_player ^2.9.2
* **Backward Compatible**: All existing image panorama code works unchanged
* **Documentation**: Comprehensive guides and examples
* **Tested**: iOS device tested and working, Android should work identically

## 2.0.7
* Fixed black screen issue introduced in v2.0.6.  
* Corrected scene initialization check (`surface == null`) to restore compatibility.

## 2.0.6
* Minor format updates

## 2.0.5
* Minor updates to the code
* Merge #PR22 thank you to @StefanosKouzounis
    * Updated the description in pubspec.yaml to fix Failed report section
    * Follow Dart file conventions in pub.dev
    * Implemented null-aware operators and added null checks to prevent potential runtime crashes.

## 2.0.4 
* Merge #PR19, #PR20. Use of controller instead of flags thank you to @Henk-Keijzer
* Minor updates to the code

## 2.0.3
* update dchs_motion_sensors to 2.0.1 for latest version of Flutter (3.29.0)

## 2.0.2
* Reintroduced sensor controls for iOS and Android.

## 2.0.1
* Added initial web support without sensors (since dchs_motion_sensors is not implemented for the web).
* Works well on macOS, Windows, and iOS. However, on some Android devices, WebGL errors may occur if the panorama image is too large.

## 2.0.0
* update dchs-motion sensor to 2.0.0
* update sdk environment to 3.5.*
* update flutter_lints to 5.0.0
* change build gradle for recommended plugin usage
* update gradle to 8.3

## 1.0.6
* Fixed an issue where re-rendering the Panorama resulted in a blank screen. Thanks to @ewanAtPropertyMe for the fix.

## 1.0.5
* updated dchs_motion_sensors to 1.1.0
* updated examples

## 1.0.4
* updates to make the movement smooth thank you to @Henk-Keijzer 
* added setAnimSpeed(double newSpeed) thank you to @Henk-Keijzer 

## 1.0.3
* separate examples. simple, simple with transparent app bar, full, and one with external controls
* added two new methods to control zoom and position with external buttons and slided. Added also an example on how to use
* solve the Longitude and latitude initialization #2 (porting from PRs in original repo)


## 1.0.2

* bug fixing for iOS, updated dependencies (dchs_motion_sensors 1.0.2) 

## 1.0.1

* initial release from https://github.com/zesage/panorama
