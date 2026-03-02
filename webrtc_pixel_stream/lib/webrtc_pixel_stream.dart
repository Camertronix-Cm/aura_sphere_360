/// A lightweight companion plugin that streams raw BGRA pixel data from a
/// WebRTC video track via EventChannel.
///
/// This plugin contains zero WebRTC code of its own. It depends on
/// `flutter_webrtc` via CocoaPods so it can access the already-registered
/// `FlutterWebRTCPlugin` singleton and attach a streaming renderer to any
/// video track.
///
/// Usage from Dart is via method/event channels — see
/// `NativeWebRTCTextureProvider` in `aura_sphere_360` for the Dart wrapper.
library webrtc_pixel_stream;
