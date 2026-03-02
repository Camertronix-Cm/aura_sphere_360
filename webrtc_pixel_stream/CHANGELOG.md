## 0.1.0

- Initial release
- `FlutterRTCStreamingSink`: RTCVideoRenderer that converts I420→BGRA and streams via EventChannel
- `WebrtcPixelStreamPlugin`: Method channel handlers for `createPixelStream` / `disposePixelStream`
- Uses `FlutterWebRTCPlugin.sharedSingleton` for track lookup (no fork required)
- iOS support only
