import 'package:flutter/material.dart';

class RegisterGuideScreen extends StatefulWidget {
  const RegisterGuideScreen({super.key});

  @override
  State<RegisterGuideScreen> createState() => _RegisterGuideScreenState();
}

class _RegisterGuideScreenState extends State<RegisterGuideScreen> {
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ====== TOP BAR ======
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    '${_pageIndex + 1}/${_steps.length}',
                    style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ====== PAGEVIEW ======
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                itemCount: _steps.length,
                itemBuilder: (context, i) {
                  final step = _steps[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.network(step['image']!, height: 200),
                        const SizedBox(height: 30),
                        Text(
                          step['title']!,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          step['desc']!,
                          style: const TextStyle(fontSize: 16, color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ====== BOTTOM BUTTON ======
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _pageIndex == _steps.length - 1
                    ? ElevatedButton(
                        key: const ValueKey('done'),
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF26A69A),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text(
                          'Bắt đầu đăng ký',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                        ),
                      )
                    : ElevatedButton(
                        key: const ValueKey('next'),
                        onPressed: () =>
                            _pageCtrl.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade300,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('Tiếp theo',
                            style: TextStyle(fontSize: 17, color: Colors.white)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
