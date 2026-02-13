import 'dart:io';
import 'package:flutter/material.dart';
import 'package:aura_sphere_360/aura_sphere_360.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class ExampleScreenFilePicker extends StatefulWidget {
  const ExampleScreenFilePicker({super.key, required this.title});
  final String title;

  @override
  ExampleScreenFilePickerState createState() => ExampleScreenFilePickerState();
}

class ExampleScreenFilePickerState extends State<ExampleScreenFilePicker>
    with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  File? _imageFile;
  bool _isInitialized = false;
  bool _isVideo = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.pause();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialized || !_isVideo || _videoController == null) return;

    if (state == AppLifecycleState.paused) {
      // App going to background - pause video
      _videoController!.pause();
    } else if (state == AppLifecycleState.resumed) {
      // App returning to foreground - optionally resume playback
      // Uncomment if you want auto-resume:
      // _videoController!.play();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // Handle hot reload - pause video to prevent background playback
    if (_isInitialized && _isVideo && _videoController != null) {
      _videoController!.pause();
    }
  }

  Future<void> _pickVideo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        // Clean up previous resources
        _videoController?.dispose();
        _videoController = null;
        _imageFile = null;

        File file = File(result.files.single.path!);
        debugPrint('🎥 Selected video: ${file.path}');
        debugPrint('🎥 File size: ${await file.length()} bytes');

        _videoController = VideoPlayerController.file(file);

        debugPrint('🎥 Initializing video controller...');
        await _videoController!.initialize();
        debugPrint('🎥 Video initialized successfully');
        debugPrint('🎥 Video size: ${_videoController!.value.size}');
        debugPrint('🎥 Video duration: ${_videoController!.value.duration}');

        _videoController!.setLooping(true);
        _videoController!.play();

        setState(() {
          _isInitialized = true;
          _isVideo = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading video: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Error loading video: $e';
        _isLoading = false;
        _isInitialized = false;
      });
    }
  }

  Future<void> _pickImage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        // Clean up previous resources
        _videoController?.dispose();
        _videoController = null;

        File file = File(image.path);
        debugPrint('🖼️ Selected image: ${file.path}');
        debugPrint('🖼️ File size: ${await file.length()} bytes');

        setState(() {
          _imageFile = file;
          _isInitialized = true;
          _isVideo = false;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading image: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Error loading image: $e';
        _isLoading = false;
        _isInitialized = false;
      });
    }
  }

  Future<void> _useNetworkVideo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Clean up previous resources
      _videoController?.dispose();
      _videoController = null;
      _imageFile = null;

      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(
          'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
        ),
      );

      debugPrint('🎥 Initializing network video...');
      await _videoController!.initialize();
      debugPrint('🎥 Network video initialized');

      _videoController!.setLooping(true);
      _videoController!.play();

      setState(() {
        _isInitialized = true;
        _isVideo = true;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading network video: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Error loading network video: $e';
        _isLoading = false;
        _isInitialized = false;
      });
    }
  }

  void _clear() {
    _videoController?.dispose();
    setState(() {
      _videoController = null;
      _imageFile = null;
      _isInitialized = false;
      _isVideo = false;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_isInitialized && _isVideo && _videoController != null)
            IconButton(
              icon: Icon(
                _videoController!.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              onPressed: () {
                setState(() {
                  if (_videoController!.value.isPlaying) {
                    _videoController!.pause();
                  } else {
                    _videoController!.play();
                  }
                });
              },
            ),
          if (_isInitialized)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clear,
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _isInitialized && _isVideo
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'restart',
                  onPressed: () {
                    _videoController?.seekTo(Duration.zero);
                    _videoController?.play();
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
                          'Duration: ${_videoController?.value.duration}\n'
                          'Position: ${_videoController?.value.position}\n'
                          'Size: ${_videoController?.value.size}\n'
                          'Playing: ${_videoController?.value.isPlaying}',
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
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _clear,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isInitialized) {
      if (_isVideo && _videoController != null) {
        return PanoramaViewer(
          animSpeed: 0.0,
          sensorControl: SensorControl.none,
          videoPlayerController: _videoController,
        );
      } else if (!_isVideo && _imageFile != null) {
        return PanoramaViewer(
          animSpeed: 0.0,
          sensorControl: SensorControl.none,
          child: Image.file(_imageFile!),
        );
      }
    }

    // Show picker options
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.panorama, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Test Aura Sphere 360',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Choose a 360° video or image to test',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.video_library),
                label: const Text('Pick Local Video File'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image),
                label: const Text('Pick Local Image File'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _useNetworkVideo,
                icon: const Icon(Icons.cloud_download),
                label: const Text('Use Network Video (Demo)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Tips:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Use 360° equirectangular images/videos\n'
              '• Supports MP4, MOV, JPG, PNG formats\n'
              '• Touch to pan, pinch to zoom\n'
              '• Videos play at ~30 FPS',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
