// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:aura_sphere_360/aura_sphere_360.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Example screen demonstrating WebRTC live streaming in 360° panorama
///
/// This example shows how to:
/// 1. Initialize RTCVideoRenderer
/// 2. Get local camera stream (for demo purposes)
/// 3. Display the stream in a 360° panorama viewer
/// 4. Handle connection states
///
/// Note: In a real application, you would connect to a remote WebRTC peer
/// instead of using the local camera.
class ExampleScreenWebRTC extends StatefulWidget {
  const ExampleScreenWebRTC({super.key, required this.title});

  final String title;

  @override
  State<ExampleScreenWebRTC> createState() => _ExampleScreenWebRTCState();
}

class _ExampleScreenWebRTCState extends State<ExampleScreenWebRTC> {
  RTCVideoRenderer? _renderer;
  MediaStream? _localStream;
  bool _isInitialized = false;
  bool _isConnecting = false;
  String _statusMessage = 'Not connected';

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
  }

  Future<void> _initializeRenderer() async {
    try {
      _renderer = RTCVideoRenderer();
      await _renderer!.initialize();
      setState(() {
        _isInitialized = true;
        _statusMessage = 'Ready to connect';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Initialization failed: $e';
      });
      print('Error initializing renderer: $e');
    }
  }

  Future<void> _startLocalStream() async {
    if (_renderer == null || !_isInitialized) return;

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to camera...';
    });

    try {
      // Get local camera stream (for demo purposes)
      // In a real app, you would connect to a remote WebRTC peer
      final Map<String, dynamic> mediaConstraints = {
        'audio': false,
        'video': {
          'facingMode': 'environment', // Use back camera if available
          'width': {'ideal': 1920, 'min': 640},
          'height': {'ideal': 1080, 'min': 480},
        }
      };

      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _renderer!.srcObject = _localStream;

      setState(() {
        _isConnecting = false;
        _statusMessage = 'Connected - Local camera stream';
      });

      print('Local stream started successfully');
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Connection failed: $e';
      });
      print('Error starting local stream: $e');
    }
  }

  Future<void> _stopStream() async {
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        track.stop();
      });
      _localStream!.dispose();
      _localStream = null;
    }

    if (_renderer != null) {
      _renderer!.srcObject = null;
    }

    setState(() {
      _statusMessage = 'Disconnected';
    });
  }

  @override
  void dispose() {
    _stopStream();
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black.withOpacity(0.5),
      ),
      body: Stack(
        children: [
          // Panorama viewer with WebRTC stream
          if (_renderer != null && _localStream != null)
            PanoramaViewer(
              webrtcRenderer: _renderer,
              sensorControl: SensorControl.orientation,
              animSpeed: 0.5,
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isConnecting ? Icons.hourglass_empty : Icons.videocam_off,
                    size: 64,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  if (_isConnecting)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
            ),

          // Status overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _localStream != null ? Icons.circle : Icons.circle_outlined,
                    color: _localStream != null ? Colors.green : Colors.grey,
                    size: 12,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Control buttons
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: _localStream == null
                  ? ElevatedButton.icon(
                      onPressed: _isInitialized && !_isConnecting
                          ? _startLocalStream
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Camera Stream'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _stopStream,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Stream'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
            ),
          ),

          // Instructions
          if (_localStream == null && !_isConnecting)
            Positioned(
              bottom: 120,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'WebRTC Live Streaming Demo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This demo uses your device camera as a WebRTC stream source. '
                      'In a real application, you would connect to a remote WebRTC peer '
                      'to stream live 360° video.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• Tap "Start Camera Stream" to begin\n'
                      '• Use touch gestures to pan and zoom\n'
                      '• Enable device orientation for gyroscope control',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
