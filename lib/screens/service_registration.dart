import 'package:flutter/material.dart';
import '../services/register_service.dart';

class ServiceRegistrationPage extends StatefulWidget {
  final int userId;

  const ServiceRegistrationPage({super.key, required this.userId});

  @override
  State<ServiceRegistrationPage> createState() => _ServiceRegistrationPageState();
}

class _ServiceRegistrationPageState extends State<ServiceRegistrationPage> {
  final RegisterService serviceApi = RegisterService();

  List<String> services = [
    'Thẻ xe', 
    'Thẻ thang máy',
    'Dọn dẹp căn hộ',
    'Dọn dẹp hành lang',
    'Bảo trì phòng tập gym',
    'Đăng ký bể bơi',
    'Bảo trì điều hòa',
    'Dịch vụ gửi đồ',
    'Hỗ trợ kỹ thuật'
  ];

  String? selectedService;
  TextEditingController noteController = TextEditingController();
  bool loading = false;

  Future<void> submit() async {
    if (selectedService == null) return;

    setState(() {
      loading = true;
    });

    bool success = await serviceApi.registerService(
      userId: widget.userId,
      serviceType: selectedService!,
      note: noteController.text,
    );

    setState(() {
      loading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Gửi thành công!' : 'Gửi thất bại!'),
      ),
    );

    if (success) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đăng ký dịch vụ'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              hint: const Text('Chọn dịch vụ'),
              value: selectedService,
              items: services
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() {
                selectedService = v;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Ghi chú / lý do',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: loading ? null : submit,
              child: loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Gửi'),
            ),
          ],
        ),
      ),
    );
  }
}
