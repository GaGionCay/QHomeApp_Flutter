import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_primary_button.dart';

import '../core/safe_state_mixin.dart';
class RegisterGuideScreen extends StatefulWidget {
  const RegisterGuideScreen({super.key});

  @override
  State<RegisterGuideScreen> createState() => _RegisterGuideScreenState();
}

class _RegisterGuideScreenState extends State<RegisterGuideScreen> with SafeStateMixin<RegisterGuideScreen> {
  final PageController _pageCtrl = PageController();
  int _pageIndex = 0;

  final List<Map<String, String>> _steps = [
    {
      'image': 'https://cdn-icons-png.flaticon.com/512/7439/7439210.png',
      'title': 'Bước 1: Chọn loại phương tiện',
      'desc': 'Chọn “Ô tô” hoặc “Xe máy” tuỳ theo loại xe bạn muốn đăng ký.'
    },
    {
      'image': 'https://cdn-icons-png.flaticon.com/512/9419/9419264.png',
      'title': 'Bước 2: Điền thông tin chi tiết',
      'desc': 'Nhập biển số, hãng xe, màu xe và ghi chú (nếu có).'
    },
    {
      'image': 'https://cdn-icons-png.flaticon.com/512/9954/9954506.png',
      'title': 'Bước 3: Tải ảnh xe',
      'desc':
          'Tải lên ít nhất 1 ảnh xe rõ nét để Ban quản lý dễ nhận diện phương tiện.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Hướng dẫn đăng ký thẻ xe',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      final nextPage = (_pageIndex + 1) % _steps.length;
                      _pageCtrl.animateToPage(
                        nextPage,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    icon: const Icon(Icons.navigate_next_rounded),
                    label: const Text('Tiếp'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryEmerald,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: PageView.builder(
                  controller: _pageCtrl,
                  onPageChanged: (i) => safeSetState(() => _pageIndex = i),
                  itemCount: _steps.length,
                  itemBuilder: (context, i) {
                    final step = _steps[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient(),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: AppColors.elevatedShadow,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Image.network(
                              step['image']!,
                              height: 160,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            step['title']!,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            step['desc']!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (index) {
                  final isActive = index == _pageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 24 : 10,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primaryEmerald
                          : AppColors.primaryEmerald.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              AppPrimaryButton(
                onPressed: () => Navigator.pop(context),
                label: 'Bắt đầu đăng ký',
                icon: Icons.check_circle_outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


