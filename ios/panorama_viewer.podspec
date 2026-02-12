#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint panorama_viewer.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'panorama_viewer'
  s.version          = '2.0.8'
  s.summary          = 'A 360-degree panorama viewer with video support'
  s.description      = <<-DESC
A Flutter plugin for displaying 360-degree panoramas with support for images and videos.
                       DESC
  s.homepage         = 'https://github.com/Camertronix-Cm/panorama_viewer'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Camertronix' => 'gwagsiglenn@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
