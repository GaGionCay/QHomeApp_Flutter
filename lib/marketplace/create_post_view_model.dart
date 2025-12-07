import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/marketplace_post.dart';
import '../models/marketplace_category.dart';
import 'marketplace_service.dart';
import '../auth/token_storage.dart';

class CreatePostViewModel extends ChangeNotifier {
  final MarketplaceService _service;
  final TokenStorage _tokenStorage;

  CreatePostViewModel(this._service, this._tokenStorage);

  // Form state
  final _formKey = GlobalKey<FormState>();
  String? _title;
  String? _description;
  double? _price;
  String? _selectedCategory;
  String? _location;
  String? _phone;
  String? _email;
  bool _showPhone = true;
  bool _showEmail = false;
  String? _selectedScope; // BUILDING, ALL, or BOTH
  List<XFile> _selectedImages = [];
  bool _isSubmitting = false;
  String? _error;

  // Categories
  List<MarketplaceCategory> _categories = [];
  bool _isLoadingCategories = false;

  // Getters
  GlobalKey<FormState> get formKey => _formKey;
  String? get title => _title;
  String? get description => _description;
  double? get price => _price;
  String? get selectedCategory => _selectedCategory;
  String? get location => _location;
  String? get phone => _phone;
  String? get email => _email;
  bool get showPhone => _showPhone;
  bool get showEmail => _showEmail;
  String? get selectedScope => _selectedScope;
  List<XFile> get selectedImages => _selectedImages;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  List<MarketplaceCategory> get categories => _categories;
  bool get isLoadingCategories => _isLoadingCategories;

  String? _buildingId;

  Future<void> initialize() async {
    _buildingId = await _tokenStorage.readBuildingId();
    await loadCategories();
  }

  Future<void> loadCategories() async {
    _isLoadingCategories = true;
    notifyListeners();

    try {
      _categories = await _service.getCategories();
      _isLoadingCategories = false;
      notifyListeners();
    } catch (e) {
      _isLoadingCategories = false;
      _error = 'Lỗi khi tải danh mục: ${e.toString()}';
      notifyListeners();
    }
  }

  void setTitle(String? value) {
    _title = value;
    notifyListeners();
  }

  void setDescription(String? value) {
    _description = value;
    notifyListeners();
  }

  void setPrice(String? value) {
    if (value == null || value.isEmpty) {
      _price = null;
    } else {
      _price = double.tryParse(value.replaceAll(',', ''));
    }
    notifyListeners();
  }

  void setCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setLocation(String? value) {
    _location = value;
    notifyListeners();
  }

  void setPhone(String? value) {
    _phone = value;
    notifyListeners();
  }

  void setEmail(String? value) {
    _email = value;
    notifyListeners();
  }

  void setShowPhone(bool value) {
    _showPhone = value;
    notifyListeners();
  }

  void setShowEmail(bool value) {
    _showEmail = value;
    notifyListeners();
  }

  void setScope(String? scope) {
    _selectedScope = scope;
    notifyListeners();
  }

  Future<void> pickImages() async {
    try {
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage(
        imageQuality: 85,
      );

      if (pickedFiles.isNotEmpty) {
        // Giới hạn tối đa 10 ảnh
        final remainingSlots = 10 - _selectedImages.length;
        if (remainingSlots > 0) {
          final filesToAdd = pickedFiles.take(remainingSlots).toList();
          _selectedImages.addAll(filesToAdd);
          notifyListeners();
        } else {
          _error = 'Chỉ có thể thêm tối đa 10 ảnh';
          notifyListeners();
        }
      }
    } catch (e) {
      _error = 'Lỗi khi chọn ảnh: ${e.toString()}';
      notifyListeners();
    }
  }

  void removeImage(int index) {
    if (index >= 0 && index < _selectedImages.length) {
      _selectedImages.removeAt(index);
      notifyListeners();
    }
  }

  Future<MarketplacePost?> submitPost() async {
    if (!_formKey.currentState!.validate()) {
      return null;
    }

    if (_buildingId == null) {
      _error = 'Không tìm thấy Building ID';
      notifyListeners();
      return null;
    }

    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      _error = 'Vui lòng chọn danh mục';
      notifyListeners();
      return null;
    }

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      // Always create contactInfo if phone or email is provided, even if empty strings
      MarketplaceContactInfo? contactInfo;
      final phoneValue = _phone?.trim();
      final emailValue = _email?.trim();
      
      print('📞 [CreatePostViewModel] Preparing contactInfo:');
      print('   - phone: $phoneValue');
      print('   - email: $emailValue');
      print('   - showPhone: $_showPhone');
      print('   - showEmail: $_showEmail');
      
      if ((phoneValue != null && phoneValue.isNotEmpty) || 
          (emailValue != null && emailValue.isNotEmpty)) {
        contactInfo = MarketplaceContactInfo(
          phone: phoneValue?.isNotEmpty == true ? phoneValue : null,
          email: emailValue?.isNotEmpty == true ? emailValue : null,
          showPhone: _showPhone,
          showEmail: _showEmail,
        );
        print('✅ [CreatePostViewModel] Created contactInfo: ${contactInfo.toJson()}');
      } else {
        print('⚠️ [CreatePostViewModel] No phone or email provided, contactInfo will be null');
      }

      final post = await _service.createPost(
        buildingId: _buildingId!,
        title: _title!,
        description: _description ?? '',
        price: _price,
        category: _selectedCategory!,
        location: _location,
        contactInfo: contactInfo,
        images: _selectedImages,
        scope: _selectedScope ?? 'BUILDING',
      );

      _isSubmitting = false;
      notifyListeners();
      return post;
    } catch (e) {
      _isSubmitting = false;
      _error = 'Lỗi khi đăng bài: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}


