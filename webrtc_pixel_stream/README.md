# webrtc_pixel_stream

A lightweight Flutter plugin that streams raw BGRA pixel data from WebRTC video tracks via `EventChannel`.

This plugin contains **zero WebRTC code** of its own. It depends on `flutter_webrtc` via CocoaPods to access the already-registered `FlutterWebRTCPlugin` singleton, then attaches a secondary `RTCVideoRenderer` to any video track to extract raw frames.

## Usage

This plugin is used internally by [aura_sphere_360](https://pub.dev/packages/aura_sphere_360) for native WebRTC pixel extraction. You typically don't need to use it directly.

### How it works

1. Dart calls `createPixelStream` on the `webrtc_pixel_stream/control` method channel
2. Native code looks up the video track via `FlutterWebRTCPlugin.sharedSingleton`
3. A `FlutterRTCStreamingSink` (RTCVideoRenderer) is attached to the track
4. I420 frames are converted to BGRA and streamed over `webrtc_pixel_stream/frames/{trackId}`

## Platform support

| Platform | Status |
|----------|--------|
| iOS      | ✅     |
| Android  | 🚧 Planned |
| Web      | ❌ N/A |

## Requirements

- `flutter_webrtc` must be initialized before calling `createPixelStream`
- iOS 13.0+
