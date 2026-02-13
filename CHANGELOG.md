## 1.0.1 - Bug Fix Release
* **FIXED**: Video initial frame white screen bug
  * Fixed race condition where panorama rendered before first video frame was captured
  * Video now displays first frame immediately on playback start
  * Affects file picker videos, network videos, and asset videos
  * Added frame dimension validation and fallback dimensions
  * Added debug logging for troubleshooting

## 1.0.0 - Initial Release
* **NEW: Aura Sphere 360** - Complete 360° panorama and video viewer
  * Display 360° images with touch and sensor controls
  * Play 360° videos with smooth 30 FPS playback
  * Support for local files, network URLs, and asset videos
  * Full touch controls (pan, zoom, rotate)
  * Sensor controls (gyroscope) for immersive experience
  * Auto-scaling for videos larger than 1920x1080
  * Cross-platform support (iOS, Android, Web)
* **Architecture**: Clean texture provider abstraction
  * Separate providers for images and videos
  * Easy to extend for future sources
* **Dependencies**: Built on flutter_cube, dchs_motion_sensors, video_player
* **Documentation**: Comprehensive guides and examples
* **Tested**: iOS device tested and working

---

## Previous Versions (as panorama_viewer)

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
