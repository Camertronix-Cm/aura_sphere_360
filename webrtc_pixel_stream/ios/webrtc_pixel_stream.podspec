Pod::Spec.new do |s|
  s.name             = 'webrtc_pixel_stream'
  s.version          = '0.1.0'
  s.summary          = 'Streams raw BGRA pixel data from WebRTC video tracks.'
  s.description      = <<-DESC
Lightweight companion plugin for panorama_viewer / aura_sphere_360.
Attaches a secondary RTCVideoRenderer to a WebRTC video track and forwards
raw BGRA frame bytes over a FlutterEventChannel. No WebRTC code of its own —
depends on the existing flutter_webrtc plugin for track access.
                       DESC
  s.homepage         = 'https://github.com/Camertronix-Cm/aura_sphere_360'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Camertronix' => 'gwagsiglenn@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'flutter_webrtc'          # imports FlutterWebRTCPlugin.h, RTCVideoTrack, etc.
  s.dependency 'WebRTC-SDK', '125.6422.04'  # same version flutter_webrtc 0.11.7 uses
  s.platform         = :ios, '13.0'
  s.static_framework = true

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
