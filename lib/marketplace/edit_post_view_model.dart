import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'marketplace_service.dart';
import '../auth/token_storage.dart';
import '../models/marketplace_post.dart';
import '../models/marketplace_category.dart';

class EditPostViewModel extends ChangeNotifier {
  final MarketplaceService _service;

  EditPostViewModel(this._service, TokenStorage _);

  // State
  List<MarketplaceCategory> _categories = [];
  String? _selectedCategory;
  List<MarketplacePostImage> _existingImages = [];
  List<XFile> _newImages = [];
  List<String> _imagesToDelete = [];
  MarketplacePostImage? _existingVideo;
  XFile? _newVideo;
  String? _videoToDelete;
  bool _isSubmitting = false;
  String? _error;
  bool _showPhone = true;
  bool _showEmail = false;

  // Getters
  List<MarketplaceCategory> get categories => _categories;
  String? get selectedCategory => _selectedCategory;
  List<MarketplacePostImage> get existingImages => _existingImages;
  List<XFile> get newImages => _newImages;
  List<String> get imagesToDelete => _imagesToDelete;
  MarketplacePostImage? get existingVideo => _existingVideo;
  XFile? get newVideo => _newVideo;
  String? get videoToDelete => _videoToDelete;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  bool get showPhone => _showPhone;
  bool get showEmail => _showEmail;

  void setShowPhone(bool value) {
    _showPhone = value;
    notifyListeners();
  }

  void setShowEmail(bool value) {
    _showEmail = value;
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      _categories = await _service.getCategories();
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi khi tải danh mục: ${e.toString()}';
      notifyListeners();
    }
  }

  void setCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setExistingImages(List<MarketplacePostImage> images) {
    _existingImages = images;
    notifyListeners();
  }

  void setExistingVideo(MarketplacePostImage? video) {
    _existingVideo = video;
    notifyListeners();
  }

  void toggleImageDelete(String imageId) {
    if (_imagesToDelete.contains(imageId)) {
      // Unmark for deletion - remove from delete list
      _imagesToDelete.remove(imageId);
    } else {
      // Mark for deletion - add to delete list
      _imagesToDelete.add(imageId);
    }
    notifyListeners();
  }

  /// Delete image immediately (called after confirmation)
  void deleteImage(String imageId) {
    // Add to delete list
    if (!_imagesToDelete.contains(imageId)) {
      _imagesToDelete.add(imageId);
    }
    // Remove from existing images list immediately
    _existingImages.removeWhere((img) => img.id == imageId);
    notifyListeners();
  }

  void addNewImages(List<XFile> images) {
    _newImages.addAll(images);
    notifyListeners();
  }

  void removeNewImage(int index) {
    if (index >= 0 && index < _newImages.length) {
      _newImages.removeAt(index);
      notifyListeners();
    }
  }

  Future<void> pickVideo({bool clearImages = false}) async {
    try {
      // Only clear images if explicitly requested (for create post behavior)
      if (clearImages) {
        if (_newImages.isNotEmpty) {
          _newImages.clear();
        }
        if (_existingImages.isNotEmpty) {
          // Mark all existing images for deletion if video is selected
          for (var image in _existingImages) {
            if (!_imagesToDelete.contains(image.id)) {
              _imagesToDelete.add(image.id);
            }
          }
          _existingImages.clear();
        }
      }
      
      final picker = ImagePicker();
      final pickedVideo = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 20),
      );

      if (pickedVideo != null) {
        // Validate video duration (max 20 seconds)
        final videoFile = File(pickedVideo.path);
        final videoPlayerController = VideoPlayerController.file(videoFile);
        await videoPlayerController.initialize();
        
        final duration = videoPlayerController.value.duration;
        await videoPlayerController.dispose();

        if (duration.inSeconds > 20) {
          _error = 'Video không được dài quá 20 giây. Video hiện tại có độ dài ${duration.inSeconds} giây. Vui lòng chọn video khác hoặc cắt ngắn video.';
          notifyListeners();
          return;
        }

        // Clear existing video if selecting new one
        if (_existingVideo != null) {
          _videoToDelete = _existingVideo!.id;
          _existingVideo = null;
        }
        
        _newVideo = pickedVideo;
        _error = null;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Lỗi khi chọn video: ${e.toString()}';
      notifyListeners();
    }
  }

  void removeNewVideo() {
    _newVideo = null;
    notifyListeners();
  }

  void deleteExistingVideo() {
    if (_existingVideo != null) {
      _videoToDelete = _existingVideo!.id;
      _existingVideo = null;
      notifyListeners();
    }
  }

  Future<MarketplacePost?> updatePost({
    required String postId,
    required String title,
    required String description,
    double? price,
    String? category,
    String? location,
    MarketplaceContactInfo? contactInfo,
    List<XFile>? newImages,
    List<String>? imagesToDelete,
    XFile? newVideo,
    String? videoToDelete,
  }) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      // Use provided values or fallback to current state
      // Don't automatically delete images when video is uploaded
      // Allow both images and video to coexist
      final updatedPost = await _service.updatePost(
        postId: postId,
        title: title,
        description: description,
        price: price,
        category: category ?? _selectedCategory,
        location: location,
        contactInfo: contactInfo,
        newImages: newImages ?? _newImages,
        imagesToDelete: imagesToDelete ?? _imagesToDelete,
        video: newVideo ?? _newVideo,
        videoToDelete: videoToDelete ?? _videoToDelete,
      );

      _isSubmitting = false;
      notifyListeners();
      return updatedPost;
    } catch (e) {
      _isSubmitting = false;
      _error = 'Lỗi khi cập nhật bài đăng: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }
}


