## 0.1.1

- **FIX:** Corrected color channel order by using `I420ToARGB` instead of `I420ToBGRA` for `kCVPixelFormatType_32BGRA` pixel buffers
- Fixes red/blue channel swap that caused blue tint in rendered frames

## 0.1.0

- Initial release
- `FlutterRTCStreamingSink`: RTCVideoRenderer that converts I420→BGRA and streams via EventChannel
- `WebrtcPixelStreamPlugin`: Method channel handlers for `createPixelStream` / `disposePixelStream`
- Uses `FlutterWebRTCPlugin.sharedSingleton` for track lookup (no fork required)
- iOS support only
