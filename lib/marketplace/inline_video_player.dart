import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_application_1/widgets/animations/smooth_animations.dart';
import 'video_viewer_screen.dart';

/// 🎯 OPTIMIZED Inline Video Player
/// 
/// CRITICAL FIXES:
/// ✅ Controller initialized ONCE
/// ✅ Optimized listener updates
/// ✅ Smooth playback
/// ✅ AutomaticKeepAliveClientMixin for scroll performance
class InlineVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final double height;
  final VoidCallback? onTap;
  final bool autoPlay;

  const InlineVideoPlayer({
    super.key,
    required this.videoUrl,
    this.height = 250,
    this.onTap,
    this.autoPlay = false,
  });

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> 
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      String url = widget.videoUrl;
      
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      
      await controller.initialize();
      
      if (!mounted) {
        await controller.dispose();
        return;
      }

      controller.addListener(_videoListener);
      
      // Mute for inline playback
      await controller.setVolume(0);
      
      setState(() {
        _controller = controller;
        _isInitialized = true;
        _isLoading = false;
        _hasError = false;
      });

      // Auto play if enabled
      if (widget.autoPlay) {
        await controller.play();
        setState(() {
          _isPlaying = true;
        });
      }
    } catch (e) {
      debugPrint('❌ [InlineVideoPlayer] Init error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  // ✅ OPTIMIZED: Only update when playing state changes
  void _videoListener() {
    if (mounted && _controller != null) {
      final isPlaying = _controller!.value.isPlaying;
      if (isPlaying != _isPlaying) {
        setState(() {
          _isPlaying = isPlaying;
        });
      }
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    
    setState(() {
      if (_isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      _isPlaying = !_isPlaying;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: widget.onTap ?? _openFullscreen,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              : _hasError
                  ? _buildErrorWidget(theme)
                  : _isInitialized && _controller != null
                      ? _buildVideoPlayer(theme)
                      : const SizedBox(),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(ThemeData theme) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video player
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),

        // Gradient overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.4),
              ],
            ),
          ),
        ),

        // Play button overlay
        if (!_isPlaying)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.play_fill,
                size: 32,
                color: Colors.white,
              ),
            ),
          ),

        // Video duration badge (bottom left)
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.videocam_fill,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDuration(_controller!.value.duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Fullscreen hint (top right)
        if (widget.onTap != null)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                CupertinoIcons.fullscreen,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  void _openFullscreen() {
    Navigator.push(
      context,
      SmoothPageRoute(
        page: VideoViewerScreen(
          videoUrl: widget.videoUrl,
          title: 'Video',
        ),
      ),
    );
  }

  Widget _buildErrorWidget(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 32,
            color: theme.colorScheme.error.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Không thể tải video',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
