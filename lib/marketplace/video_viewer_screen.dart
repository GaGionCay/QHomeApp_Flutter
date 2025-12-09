import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart';
import '../auth/api_client.dart';

/// Full screen video viewer screen
/// Supports both local file and network URL
class VideoViewerScreen extends StatefulWidget {
  final String? videoPath; // Local file path
  final String? videoUrl; // Network URL
  final String? title;

  const VideoViewerScreen({
    super.key,
    this.videoPath,
    this.videoUrl,
    this.title,
  }) : assert(videoPath != null || videoUrl != null, 'Either videoPath or videoUrl must be provided');

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Timer? _hideControlsTimer;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      VideoPlayerController controller;
      
      if (widget.videoPath != null) {
        // Local file
        controller = VideoPlayerController.file(File(widget.videoPath!));
      } else if (widget.videoUrl != null) {
        // Network URL - check if it's ImageKit URL and use proxy if needed
        String videoUrl = widget.videoUrl!;
        
        // Check if URL is from ImageKit (ik.imagekit.io)
        if (_isImageKitUrl(videoUrl)) {
          // Use proxy endpoint to avoid 403 errors
          final encodedUrl = Uri.encodeComponent(videoUrl);
          videoUrl = '${ApiClient.activeBaseUrl}/marketplace/media/video?url=$encodedUrl';
          debugPrint('📹 [VideoViewer] Using proxy URL for ImageKit video: $videoUrl');
        } else {
          // For non-ImageKit URLs, use directly
          videoUrl = videoUrl.startsWith('http://') || videoUrl.startsWith('https://')
              ? videoUrl
              : 'https://$videoUrl';
        }
        
        controller = VideoPlayerController.networkUrl(
          Uri.parse(videoUrl),
          httpHeaders: {
            'Connection': 'keep-alive',
          },
        );
      } else {
        setState(() {
          _errorMessage = 'Không có video để phát';
          _isLoading = false;
        });
        return;
      }

      // Initialize with timeout and retry logic
      await _initializeWithRetry(controller, maxRetries: 2);
      
      if (!mounted) {
        await controller.dispose();
        return;
      }

      controller.addListener(_videoListener);
      
      setState(() {
        _controller = controller;
        _isInitialized = true;
        _isLoading = false;
        _duration = controller.value.duration;
        _position = controller.value.position;
      });

      // Auto play
      await controller.play();
      setState(() {
        _isPlaying = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Lỗi khi tải video: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeWithRetry(VideoPlayerController controller, {int maxRetries = 2}) async {
    int retryCount = 0;
    while (retryCount <= maxRetries) {
      try {
        // Use timeout wrapper to handle long loading times
        await controller.initialize().timeout(
          const Duration(seconds: 90), // 90 seconds timeout for initialization
          onTimeout: () {
            throw TimeoutException('Video initialization timeout after 90 seconds');
          },
        );
        return; // Success, exit retry loop
      } catch (e) {
        retryCount++;
        if (retryCount > maxRetries) {
          // Dispose controller if all retries failed
          await controller.dispose();
          rethrow;
        }
        // Wait before retry (exponential backoff)
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }
  }

  void _videoListener() {
    if (_controller != null && mounted) {
      setState(() {
        _position = _controller!.value.position;
        _isPlaying = _controller!.value.isPlaying;
        if (_controller!.value.position >= _controller!.value.duration) {
          _isPlaying = false;
        }
      });
    }
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    
    if (_isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
    _resetHideControlsTimer();
  }

  void _seekTo(Duration position) {
    if (_controller == null) return;
    _controller!.seekTo(position);
    _resetHideControlsTimer();
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    setState(() {
      _showControls = true;
    });
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  /// Check if URL is from ImageKit
  bool _isImageKitUrl(String url) {
    if (url.isEmpty) return false;
    return url.contains('ik.imagekit.io') || url.contains('imagekit.io');
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: widget.title != null
            ? Text(
                widget.title!,
                style: const TextStyle(color: Colors.white),
              )
            : null,
      ),
      body: GestureDetector(
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
          if (_showControls) {
            _resetHideControlsTimer();
          }
        },
        child: Stack(
          children: [
            // Video player
            Center(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.exclamationmark_triangle,
                                size: 64,
                                color: Colors.white70,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : _isInitialized && _controller != null
                          ? AspectRatio(
                              aspectRatio: _controller!.value.aspectRatio,
                              child: VideoPlayer(_controller!),
                            )
                          : const SizedBox(),
            ),

            // Controls overlay
            if (_showControls && _isInitialized && _controller != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black26,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Play/Pause button
                      IconButton(
                        onPressed: _togglePlayPause,
                        icon: Icon(
                          _isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill,
                          size: 64,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Progress bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            // Time indicators
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(_position),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  _formatDuration(_duration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Slider
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white38,
                                thumbColor: Colors.white,
                                overlayColor: Colors.white24,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              ),
                              child: Slider(
                                value: _duration.inMilliseconds > 0
                                    ? _position.inMilliseconds.toDouble()
                                    : 0.0,
                                max: _duration.inMilliseconds > 0
                                    ? _duration.inMilliseconds.toDouble()
                                    : 1.0,
                                onChanged: (value) {
                                  _seekTo(Duration(milliseconds: value.toInt()));
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
