/// Aura Sphere 360 - Immersive 360° panorama and video viewer for Flutter
///
/// This library provides widgets for displaying 360° panoramic images and videos
/// with touch controls, sensor controls, and smooth video playback.
///
/// ## Features
/// - Display 360° images
/// - Play 360° videos at 30 FPS
/// - Stream live 360° video via WebRTC
/// - Touch controls (pan, zoom, rotate)
/// - Sensor controls (gyroscope)
/// - Cross-platform support
///
/// ## Usage
///
/// ### Image Panoramas
/// ```dart
/// AuraSphere(
///   child: Image.asset('assets/panorama.jpg'),
/// )
/// ```
///
/// ### Video Panoramas
/// ```dart
/// final controller = VideoPlayerController.file(File('video.mp4'));
/// await controller.initialize();
///
/// AuraSphere(
///   videoPlayerController: controller,
///   sensorControl: SensorControl.orientation,
/// )
/// ```
///
/// ### WebRTC Live Streaming
/// ```dart
/// final renderer = RTCVideoRenderer();
/// await renderer.initialize();
/// renderer.srcObject = stream;
///
/// AuraSphere(
///   webrtcRenderer: renderer,
///   sensorControl: SensorControl.orientation,
/// )
/// ```
library;

// Export all public APIs
export 'panorama_viewer.dart'
    show
        PanoramaViewer,
        PanoramaState,
        PanoramaController,
        Hotspot,
        SensorControl;

// Re-export flutter_webrtc for convenience
export 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoRenderer;

// Import for typedef
import 'panorama_viewer.dart' show PanoramaViewer;

// Create an alias for better naming
/// AuraSphere widget for displaying 360° panoramas and videos
///
/// This is an alias for [PanoramaViewer] with a more brand-friendly name.
typedef AuraSphere = PanoramaViewer;
