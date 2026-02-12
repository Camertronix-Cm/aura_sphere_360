import 'package:flutter/material.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:video_player/video_player.dart';

class ExampleScreenVideo extends StatefulWidget {
  const ExampleScreenVideo({super.key, required this.title});
  final String title;

  @override
  ExampleScreenVideoState createState() => ExampleScreenVideoState();
}

class ExampleScreenVideoState extends State<ExampleScreenVideo> {
  late VideoPlayerController _videoController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    // Using a sample 360 video from the internet
    // Replace with your own 360 video URL or asset
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(
        'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
      ),
    );

    await _videoController.initialize();
    _videoController.setLooping(true);
    _videoController.play();

    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(
              _videoController.value.isPlaying ? Icons.pause : Icons.play_arrow,
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
          ? PanoramaViewer(
              animSpeed: 0.0,
              sensorControl: SensorControl.orientation,
              videoPlayerController: _videoController,
            )
          : const Center(
              child: CircularProgressIndicator(),
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
