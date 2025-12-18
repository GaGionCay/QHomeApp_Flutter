import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:video_player/video_player.dart';

/// 🎯 OPTIMIZED Fullscreen video viewer
/// 
/// CRITICAL FIXES for seek/lag issues:
/// ✅ _isDragging flag prevents setState during seek
/// ✅ Pause video during seek to prevent MediaCodec lag
/// ✅ Optimized video listener (only update when changed >100ms)
/// ✅ Single setState after seek completes
/// ✅ Stable AspectRatio
/// ✅ Controls at bottom
class VideoViewerScreen extends StatefulWidget {
  final String? videoPath;
  final String? videoUrl;
  final String? title;

  const VideoViewerScreen({
    super.key,
    this.videoPath,
    this.videoUrl,
    this.title,
  }) : assert(videoPath != null || videoUrl != null);

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isDragging = false; // ✅ CRITICAL: Prevent setState during seek
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
        controller = VideoPlayerController.file(File(widget.videoPath!));
      } else if (widget.videoUrl != null) {
        String videoUrl = widget.videoUrl!;
        videoUrl = videoUrl.startsWith('http://') || videoUrl.startsWith('https://')
            ? videoUrl
            : 'https://$videoUrl';
        
        controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      } else {
        setState(() {
          _errorMessage = 'Không có video để phát';
          _isLoading = false;
        });
        return;
      }

      await controller.initialize();
      
      if (!mounted) {
        await controller.dispose();
        return;
      }

      controller.addListener(_videoListener);
      await controller.setLooping(false);
      
      setState(() {
        _controller = controller;
        _isInitialized = true;
        _isLoading = false;
        _duration = controller.value.duration;
        _position = controller.value.position;
      });

      // Auto play with buffer delay
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        await controller.play();
        setState(() {
          _isPlaying = true;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Lỗi khi tải video: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ✅ OPTIMIZED: Only update when values actually changed
  void _videoListener() {
    if (mounted && !_isDragging && _controller != null) {
      final newPlaying = _controller!.value.isPlaying;
      final newPosition = _controller!.value.position;
      final newDuration = _controller!.value.duration;
      
      // Only setState if changed significantly (>100ms for position)
      if (newPlaying != _isPlaying || 
          (newPosition - _position).abs() > const Duration(milliseconds: 100) ||
          newDuration != _duration) {
        setState(() {
          _isPlaying = newPlaying;
          _duration = newDuration;
          _position = newPosition;
        });
      }
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

  // ✅ CRITICAL FIX: Pause → Seek → Resume to prevent MediaCodec lag
  Future<void> _seekTo(Duration position) async {
    if (_controller == null || !mounted) return;
    
    try {
      // Pause during seek to prevent lag
      final wasPlaying = _isPlaying;
      if (wasPlaying) {
        await _controller!.pause();
      }
      
      // Perform seek
      await _controller!.seekTo(position);
      
      // Resume if was playing
      if (wasPlaying && mounted) {
        await _controller!.play();
      }
      
      // Single setState after complete
      if (mounted) {
        setState(() {
          _position = position;
          _isPlaying = wasPlaying;
        });
      }
    } catch (e) {
      debugPrint('❌ Seek error: $e');
    }
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

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _resetHideControlsTimer();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
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
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Video player
            Center(
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : _errorMessage != null
                      ? _buildErrorWidget()
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
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      // Center play/pause
                      Expanded(
                        child: Center(
                          child: IconButton(
                            onPressed: _togglePlayPause,
                            icon: Icon(
                              _isPlaying 
                                ? CupertinoIcons.pause_circle_fill 
                                : CupertinoIcons.play_circle_fill,
                              size: 72,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                      
                      // Bottom controls
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress bar
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white38,
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.white24,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                  trackHeight: 3,
                                ),
                                child: Slider(
                                  value: _position.inMilliseconds.toDouble(),
                                  max: _duration.inMilliseconds > 0
                                      ? _duration.inMilliseconds.toDouble()
                                      : 1.0,
                                  onChangeStart: (value) {
                                    // ✅ Stop listener, keep controls visible
                                    _hideControlsTimer?.cancel();
                                    setState(() {
                                      _isDragging = true;
                                      _showControls = true;
                                    });
                                  },
                                  onChanged: (value) {
                                    // ✅ Update position during drag
                                    if (mounted) {
                                      setState(() {
                                        _position = Duration(milliseconds: value.toInt());
                                      });
                                    }
                                  },
                                  onChangeEnd: (value) async {
                                    // ✅ Seek after drag completes
                                    await _seekTo(Duration(milliseconds: value.toInt()));
                                    if (mounted) {
                                      setState(() {
                                        _isDragging = false;
                                      });
                                      _resetHideControlsTimer();
                                    }
                                  },
                                ),
                              ),
                              
                              // Time indicators
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(_position),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(_duration),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
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
    );
  }
}
