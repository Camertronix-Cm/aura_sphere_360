## 0.2.0

- **BREAKING:** Migrated to FFI-based double-buffered shared memory for zero-copy pixel transfer
- **NEW:** Added support for software-decoded I420 frames (VP8/VP9) using RTCYUVHelper
- **PERFORMANCE:** Eliminated EventChannel serialization overhead (~80% CPU reduction for 4K streams)
- **NEW:** Double-buffering prevents frame tearing during high-framerate WebRTC streams
- **FIX:** Black screen issue with software-decoded codecs now resolved
- **NEW:** Full Android support via reflection-based WebRTC track lookup, integrating legacy EventChannel and native FFI double-buffered fallback paths.

## 0.1.1

- **FIX:** Corrected color channel order by using `I420ToARGB` instead of `I420ToBGRA` for `kCVPixelFormatType_32BGRA` pixel buffers
- Fixes red/blue channel swap that caused blue tint in rendered frames

## 0.1.0

- Initial release
- `FlutterRTCStreamingSink`: RTCVideoRenderer that converts I420→BGRA and streams via EventChannel
- `WebrtcPixelStreamPlugin`: Method channel handlers for `createPixelStream` / `disposePixelStream`
- Uses `FlutterWebRTCPlugin.sharedSingleton` for track lookup (no fork required)
- iOS support only
