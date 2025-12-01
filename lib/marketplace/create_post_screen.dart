import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'create_post_view_model.dart';
import 'marketplace_service.dart';
import '../auth/token_storage.dart';
import 'number_formatter.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  late final CreatePostViewModel _viewModel;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final service = MarketplaceService();
    final storage = TokenStorage();
    _viewModel = CreatePostViewModel(service, storage);
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

  Future<void> _handleSubmit() async {
    final post = await _viewModel.submitPost();
    if (post != null && mounted) {
      Navigator.of(context).pop(post);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đăng bài thành công!'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted && _viewModel.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_viewModel.error!),
          backgroundColor: Colors.red,
        ),
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
          title: const Text('Đăng bài mới'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            Consumer<CreatePostViewModel>(
              builder: (context, viewModel, child) {
                return TextButton(
                  onPressed: viewModel.isSubmitting ? null : _handleSubmit,
                  child: viewModel.isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Đăng',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                );
              },
            ),
          ],
        ),
        body: Consumer<CreatePostViewModel>(
          builder: (context, viewModel, child) {
            return Form(
              key: viewModel.formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Title
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Tiêu đề *',
                      hintText: 'Nhập tiêu đề bài đăng',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(CupertinoIcons.text_alignleft),
                    ),
                    maxLength: 200,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng nhập tiêu đề';
                      }
                      if (value.length < 5) {
                        return 'Tiêu đề phải có ít nhất 5 ký tự';
                      }
                      return null;
                    },
                    onChanged: viewModel.setTitle,
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Mô tả *',
                      hintText: 'Mô tả chi tiết về sản phẩm/dịch vụ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(CupertinoIcons.text_bubble),
                    ),
                    maxLines: 5,
                    maxLength: 2000,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng nhập mô tả';
                      }
                      if (value.length < 10) {
                        return 'Mô tả phải có ít nhất 10 ký tự';
                      }
                      return null;
                    },
                    onChanged: viewModel.setDescription,
                  ),
                  const SizedBox(height: 16),

                  // Price
                  TextFormField(
                    controller: _priceController,
                    decoration: InputDecoration(
                      labelText: 'Giá (VND)',
                      hintText: 'Nhập giá hoặc để trống nếu thỏa thuận',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(CupertinoIcons.money_dollar),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      ThousandsSeparatorInputFormatter(),
                    ],
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final price = parseFormattedNumber(value);
                        if (price == null || price < 0) {
                          return 'Giá không hợp lệ';
                        }
                      }
                      return null;
                    },
                    onChanged: (value) {
                      // Parse formatted number before passing to viewModel
                      final price = parseFormattedNumber(value);
                      viewModel.setPrice(price?.toString() ?? '');
                    },
                  ),
                  const SizedBox(height: 16),

                  // Category
                  DropdownButtonFormField<String>(
                    initialValue: viewModel.selectedCategory,
                    decoration: InputDecoration(
                      labelText: 'Danh mục *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(CupertinoIcons.square_grid_2x2),
                    ),
                    items: viewModel.categories
                        .where((cat) => cat.active)
                        .map((category) => DropdownMenuItem(
                              value: category.code,
                              child: Text(category.name),
                            ))
                        .toList(),
                    onChanged: viewModel.setCategory,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng chọn danh mục';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Location
                  TextFormField(
                    controller: _locationController,
                    decoration: InputDecoration(
                      labelText: 'Vị trí',
                      hintText: 'Tòa nhà, tầng, căn hộ (tùy chọn)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(CupertinoIcons.location),
                    ),
                    onChanged: viewModel.setLocation,
                  ),
                  const SizedBox(height: 24),

                  // Images Section
                  _buildImagesSection(context, viewModel),
                  const SizedBox(height: 24),

                  // Contact Info Section
                  _buildContactInfoSection(context, viewModel),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildImagesSection(BuildContext context, CreatePostViewModel viewModel) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hình ảnh *',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Thêm ít nhất 1 ảnh (tối đa 10 ảnh)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // Add image button
            GestureDetector(
              onTap: viewModel.pickImages,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.add_circled,
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Thêm ảnh',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            // Selected images
            ...viewModel.selectedImages.asMap().entries.map((entry) {
              final index = entry.key;
              final image = entry.value;
              return Stack(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(image.path),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            CupertinoIcons.photo,
                            size: 48,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => viewModel.removeImage(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildContactInfoSection(BuildContext context, CreatePostViewModel viewModel) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              // Remove all non-digit characters
              final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
              if (digitsOnly.length != 10) {
                return 'Số điện thoại phải có đúng 10 chữ số';
              }
            }
            return null;
          },
          onChanged: viewModel.setPhone,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: viewModel.showPhone,
              onChanged: (value) {
                viewModel.setShowPhone(value ?? true);
                // Trigger validation when checkbox changes
                if (viewModel.formKey.currentState != null) {
                  viewModel.formKey.currentState!.validate();
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
          onChanged: viewModel.setEmail,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: viewModel.showEmail,
              onChanged: (value) {
                viewModel.setShowEmail(value ?? false);
                // Trigger validation when checkbox changes
                if (viewModel.formKey.currentState != null) {
                  viewModel.formKey.currentState!.validate();
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
  }
}

