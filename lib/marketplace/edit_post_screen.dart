import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'edit_post_view_model.dart';
import 'marketplace_service.dart';
import '../auth/token_storage.dart';
import '../models/marketplace_post.dart';
import 'number_formatter.dart';

class EditPostScreen extends StatefulWidget {
  final MarketplacePost post;
  final VoidCallback? onPostUpdated;

  const EditPostScreen({
    super.key,
    required this.post,
    this.onPostUpdated,
  });

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  late final EditPostViewModel _viewModel;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final service = MarketplaceService();
    final storage = TokenStorage();
    _viewModel = EditPostViewModel(service, storage);
    
    // Initialize form with existing post data
    _titleController.text = widget.post.title;
    _descriptionController.text = widget.post.description;
    // Format price with thousand separator
    if (widget.post.price != null) {
      _priceController.text = _formatPrice(widget.post.price!);
    }
    _locationController.text = widget.post.location ?? '';
    _phoneController.text = widget.post.contactInfo?.phone ?? '';
    _emailController.text = widget.post.contactInfo?.email ?? '';
    
    // Set showPhone and showEmail from existing post
    if (widget.post.contactInfo != null) {
      _viewModel.setShowPhone(widget.post.contactInfo!.showPhone);
      _viewModel.setShowEmail(widget.post.contactInfo!.showEmail);
    }
    
    // Set existing images
    _viewModel.setExistingImages(widget.post.images);
    
    _viewModel.initialize();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _showDeleteImageConfirmation(
    BuildContext context,
    EditPostViewModel viewModel,
    String imageId,
    String imageUrl,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa ảnh'),
        content: const Text('Bạn có chắc chắn muốn xóa ảnh này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      viewModel.deleteImage(imageId);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final result = await _viewModel.updatePost(
      postId: widget.post.id,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      price: _priceController.text.isNotEmpty 
          ? parseFormattedNumber(_priceController.text.trim())
          : null,
      category: _viewModel.selectedCategory,
      location: _locationController.text.trim().isNotEmpty 
          ? _locationController.text.trim() 
          : null,
      contactInfo: (_phoneController.text.trim().isNotEmpty || 
                    _emailController.text.trim().isNotEmpty)
          ? MarketplaceContactInfo(
              phone: _phoneController.text.trim().isNotEmpty 
                  ? _phoneController.text.trim() 
                  : null,
              email: _emailController.text.trim().isNotEmpty 
                  ? _emailController.text.trim() 
                  : null,
              showPhone: _viewModel.showPhone,
              showEmail: _viewModel.showEmail,
            )
          : null,
      newImages: _viewModel.newImages,
      imagesToDelete: _viewModel.imagesToDelete,
    );

    if (result != null && mounted) {
      // Call callback if provided
      if (widget.onPostUpdated != null) {
        widget.onPostUpdated!();
      }
      
      Navigator.of(context).pop(true); // Return true to indicate success
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_viewModel.error ?? 'Lỗi khi cập nhật bài đăng')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Chỉnh sửa bài đăng'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Tiêu đề *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLength: 200,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vui lòng nhập tiêu đề';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Mô tả *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 5,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vui lòng nhập mô tả';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Category
            Consumer<EditPostViewModel>(
              builder: (context, viewModel, child) {
                return DropdownButtonFormField<String>(
                  value: viewModel.selectedCategory ?? widget.post.category,
                  decoration: InputDecoration(
                    labelText: 'Danh mục *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: viewModel.categories.map((category) {
                    return DropdownMenuItem(
                      value: category.code,
                      child: Text(category.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    viewModel.setCategory(value);
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Vui lòng chọn danh mục';
                    }
                    return null;
                  },
                );
              },
            ),
            const SizedBox(height: 16),

            // Price
            TextFormField(
              controller: _priceController,
              decoration: InputDecoration(
                labelText: 'Giá (VND)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixText: '₫ ',
                hintText: '0',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                ThousandsSeparatorInputFormatter(),
              ],
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  final price = parseFormattedNumber(value.trim());
                  if (price == null || price < 0) {
                    return 'Giá không hợp lệ';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Location
            TextFormField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: 'Địa điểm',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Contact Info Section
            Text(
              'Thông tin liên hệ',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Thông tin này sẽ được hiển thị công khai',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            Consumer<EditPostViewModel>(
              builder: (context, viewModel, child) {
                return Column(
                  children: [
                    // Phone
                    TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Số điện thoại',
                        hintText: 'Nhập số điện thoại (tùy chọn)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(CupertinoIcons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      validator: (value) {
                        if (viewModel.showPhone) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Số điện thoại không được để trống khi chọn hiển thị số điện thoại';
                          }
                          final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
                          if (digitsOnly.length != 10) {
                            return 'Số điện thoại phải có đúng 10 chữ số';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: viewModel.showPhone,
                          onChanged: (value) {
                            viewModel.setShowPhone(value ?? true);
                            if (_formKey.currentState != null) {
                              _formKey.currentState!.validate();
                            }
                          },
                        ),
                        Text(
                          'Hiển thị số điện thoại',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Email
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        hintText: 'Nhập email (tùy chọn)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(CupertinoIcons.mail),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (viewModel.showEmail) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email không được để trống khi chọn hiển thị email';
                          }
                          final emailRegex = RegExp(r'^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Email không đúng định dạng';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: viewModel.showEmail,
                          onChanged: (value) {
                            viewModel.setShowEmail(value ?? false);
                            if (_formKey.currentState != null) {
                              _formKey.currentState!.validate();
                            }
                          },
                        ),
                        Text(
                          'Hiển thị email',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // Existing Images
            Consumer<EditPostViewModel>(
              builder: (context, viewModel, child) {
                if (viewModel.existingImages.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Ảnh hiện tại',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(Chạm vào ảnh để xóa)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: viewModel.existingImages.length,
                        itemBuilder: (context, index) {
                          final image = viewModel.existingImages[index];
                          final isMarkedForDelete = viewModel.imagesToDelete.contains(image.id);
                          
                          return GestureDetector(
                            onTap: () {
                              // Show confirmation dialog when tapping on image
                              _showDeleteImageConfirmation(context, viewModel, image.id, image.imageUrl);
                            },
                            child: Container(
                              width: 120,
                              margin: EdgeInsets.only(
                                right: index < viewModel.existingImages.length - 1 ? 8 : 0,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isMarkedForDelete 
                                      ? theme.colorScheme.error 
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      imageUrl: image.imageUrl,
                                      fit: BoxFit.cover,
                                      httpHeaders: {
                                        'ngrok-skip-browser-warning': 'true',
                                      },
                                      errorWidget: (context, url, error) => Container(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        child: Icon(
                                          CupertinoIcons.photo,
                                          size: 48,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isMarkedForDelete)
                                    Container(
                                      color: Colors.black54,
                                      child: Center(
                                        child: Icon(
                                          CupertinoIcons.delete,
                                          color: theme.colorScheme.error,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        // Show confirmation dialog when tapping delete icon
                                        _showDeleteImageConfirmation(context, viewModel, image.id, image.imageUrl);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: isMarkedForDelete 
                                              ? theme.colorScheme.error 
                                              : Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isMarkedForDelete 
                                              ? CupertinoIcons.arrow_clockwise 
                                              : CupertinoIcons.delete,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),

            // New Images
            Consumer<EditPostViewModel>(
              builder: (context, viewModel, child) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ảnh mới',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (viewModel.newImages.isNotEmpty)
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: viewModel.newImages.length,
                          itemBuilder: (context, index) {
                            final image = viewModel.newImages[index];
                            return Container(
                              width: 120,
                              margin: EdgeInsets.only(
                                right: index < viewModel.newImages.length - 1 ? 8 : 0,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: theme.colorScheme.surfaceContainerHighest,
                              ),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      File(image.path),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () => viewModel.removeNewImage(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          CupertinoIcons.delete,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final images = await picker.pickMultiImage();
                        if (images.isNotEmpty) {
                          viewModel.addNewImages(images);
                        }
                      },
                      icon: const Icon(CupertinoIcons.photo_on_rectangle),
                      label: const Text('Thêm ảnh'),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),

            // Submit Button
            Consumer<EditPostViewModel>(
              builder: (context, viewModel, child) {
                return FilledButton(
                  onPressed: viewModel.isSubmitting ? null : _handleSubmit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: viewModel.isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Cập nhật bài đăng',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      ),
    );
  }

  String _formatPrice(double price) {
    // Format price with thousand separator
    String priceStr = price.toStringAsFixed(0);
    String formatted = '';
    for (int i = priceStr.length - 1; i >= 0; i--) {
      if ((priceStr.length - 1 - i) > 0 && (priceStr.length - 1 - i) % 3 == 0) {
        formatted = ',' + formatted;
      }
      formatted = priceStr[i] + formatted;
    }
    return formatted;
  }
}

