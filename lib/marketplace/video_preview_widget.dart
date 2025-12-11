import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import '../auth/api_client.dart';

/// Widget to display video preview with thumbnail and play button
/// Supports both local file and network URL
class VideoPreviewWidget extends StatefulWidget {
  final String? videoPath; // Local file path
  final String? videoUrl; // Network URL
  final VoidCallback? onTap; // Called when user taps to view full screen
  final VoidCallback? onDelete; // Called when user taps delete button
  final double? width;
  final double? height;
  final BoxFit fit;

  const VideoPreviewWidget({
    super.key,
    this.videoPath,
    this.videoUrl,
    this.onTap,
    this.onDelete,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  }) : assert(videoPath != null || videoUrl != null, 'Either videoPath or videoUrl must be provided');

  @override
  State<VideoPreviewWidget> createState() => _VideoPreviewWidgetState();
}

class _VideoPreviewWidgetState extends State<VideoPreviewWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoPath != null) {
      _initializeLocalVideo();
    } else if (widget.videoUrl != null) {
      _initializeNetworkVideo();
    } else {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _initializeLocalVideo() async {
    try {
      final controller = VideoPlayerController.file(File(widget.videoPath!));
      await controller.initialize();
      
      if (mounted) {
        setState(() {
          _controller = controller;
          _isInitialized = true;
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _initializeNetworkVideo() async {
    try {
      String videoUrl = widget.videoUrl!;
      
      // Skip ImageKit videos - ImageKit is out of storage and blocking requests
      if (_isImageKitUrl(videoUrl)) {
        debugPrint('⚠️ [VideoPreview] Skipping ImageKit video (out of storage): $videoUrl');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
        return;
      }
      
      // Use database video URL directly
      videoUrl = videoUrl.startsWith('http://') || videoUrl.startsWith('https://')
          ? videoUrl
          : 'https://$videoUrl';
      
      // Create controller with httpHeaders for better timeout handling
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        httpHeaders: {
          'Connection': 'keep-alive',
        },
      );
      
      // Initialize with timeout and retry logic
      await _initializeWithRetry(controller, maxRetries: 2);
      
      if (mounted) {
        setState(() {
          _controller = controller;
          _isInitialized = true;
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _initializeWithRetry(VideoPlayerController controller, {int maxRetries = 2}) async {
    int retryCount = 0;
    while (retryCount <= maxRetries) {
      try {
        // Use timeout wrapper to handle long loading times
        await controller.initialize().timeout(
          const Duration(seconds: 60), // 60 seconds timeout for initialization
          onTimeout: () {
            throw TimeoutException('Video initialization timeout after 60 seconds');
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = widget.width ?? double.infinity;
    final height = widget.height ?? 200.0;

    return Stack(
      children: [
        // Video thumbnail or first frame
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
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
                : _isInitialized && _controller != null && !_hasError
                    ? Stack(
                        children: [
                          // Video player (showing first frame)
                          SizedBox.expand(
                            child: FittedBox(
                              fit: widget.fit,
                              child: SizedBox(
                                width: _controller!.value.size.width,
                                height: _controller!.value.size.height,
                                child: VideoPlayer(_controller!),
                              ),
                            ),
                          ),
                          // Dark overlay for better contrast
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.3),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : _hasError
                        ? _buildErrorWidget(theme)
                        : _buildVideoPlaceholder(theme),
          ),
        ),

        // Play button overlay
        if (widget.onTap != null)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.play_circle_fill,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Delete button
        if (widget.onDelete != null)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.xmark,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),

        // Video duration badge (bottom left)
        if (_isInitialized && _controller != null)
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
                    CupertinoIcons.videocam,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(_controller!.value.duration),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVideoPlaceholder(ThemeData theme) {
    // Show a placeholder while video is loading or if initialization failed
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.videocam_circle_fill,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              'Video',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Nhấn để xem',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(ThemeData theme) {
    final isImageKit = widget.videoUrl != null && _isImageKitUrl(widget.videoUrl!);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 48,
            color: theme.colorScheme.error.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            isImageKit 
                ? 'Video ImageKit không khả dụng'
                : 'Không thể tải video',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
}

