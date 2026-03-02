import 'package:flutter/material.dart';
import 'package:aura_sphere_360/aura_sphere_360.dart';
import 'package:video_player/video_player.dart';

class ExampleScreenVideo extends StatefulWidget {
  const ExampleScreenVideo({super.key, required this.title});
  final String title;

  @override
  ExampleScreenVideoState createState() => ExampleScreenVideoState();
}

class ExampleScreenVideoState extends State<ExampleScreenVideo>
    with WidgetsBindingObserver {
  /// The video URL — passed to both the native extractor and (optionally)
  /// a VideoPlayerController for UI controls.
  static const String _videoUrl =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

  /// Optional: keep a VideoPlayerController only for UI state (position, duration).
  /// The native extractor creates its own AVPlayer on a background thread.
  late VideoPlayerController _videoController;
  bool _isInitialized = false;

  /// Toggle between native extraction and legacy screenshot path.
  bool _useNativeExtraction = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(_videoUrl),
      );

      await _videoController.initialize();
      _videoController.setLooping(true);
      _videoController.play();

      setState(() {
        _isInitialized = true;
      });
    } catch (e, stackTrace) {
      debugPrint('Error initializing video: $e\n$stackTrace');
      setState(() {
        _isInitialized = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController.pause();
    _videoController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialized) return;
    if (state == AppLifecycleState.paused) {
      _videoController.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // Toggle native vs legacy extraction
          IconButton(
            icon: Icon(_useNativeExtraction ? Icons.bolt : Icons.screenshot),
            tooltip: _useNativeExtraction
                ? 'Native extraction (fast)'
                : 'Legacy screenshot (slow)',
            onPressed: () {
              setState(() {
                _useNativeExtraction = !_useNativeExtraction;
              });
            },
          ),
          if (_isInitialized)
            IconButton(
              icon: Icon(
                _videoController.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              onPressed: () {
                setState(() {
                  if (_videoController.value.isPlaying) {
                    _videoController.pause();
                  } else {
                    _videoController.play();
                  }
                });
              },
            ),
        ],
      ),
      body: _isInitialized
          ? _useNativeExtraction
              // ── Native path: passes videoUrl directly ──────────────────
              ? PanoramaViewer(
                  animSpeed: 0.0,
                  sensorControl: SensorControl.none,
                  videoUrl: _videoUrl,
                  useNativeExtraction: true,
                )
              // ── Legacy path: uses VideoPlayerController + screenshot ───
              : PanoramaViewer(
                  animSpeed: 0.0,
                  sensorControl: SensorControl.none,
                  videoPlayerController: _videoController,
                  useNativeExtraction: false,
                )
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading video...'),
                ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'restart',
            onPressed: () {
              _videoController.seekTo(Duration.zero);
              _videoController.play();
            },
            child: const Icon(Icons.replay),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'info',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Video Info'),
                  content: Text(
                    'Mode: ${_useNativeExtraction ? "Native extraction" : "Legacy screenshot"}\n'
                    'Duration: ${_videoController.value.duration}\n'
                    'Position: ${_videoController.value.position}\n'
                    'Size: ${_videoController.value.size}\n'
                    'Playing: ${_videoController.value.isPlaying}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
            child: const Icon(Icons.info),
          ),
        ],
      ),
    );
  }
}
