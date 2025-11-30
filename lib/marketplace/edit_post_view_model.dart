import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  bool _isSubmitting = false;
  String? _error;

  // Getters
  List<MarketplaceCategory> get categories => _categories;
  String? get selectedCategory => _selectedCategory;
  List<MarketplacePostImage> get existingImages => _existingImages;
  List<XFile> get newImages => _newImages;
  List<String> get imagesToDelete => _imagesToDelete;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;

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
  }) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
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

