import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import 'register_service_list_screen.dart';

class RegisterServiceScreen extends StatefulWidget {
  const RegisterServiceScreen({super.key});
  @override
  State<RegisterServiceScreen> createState() => _RegisterServiceScreenState();
}

class _RegisterServiceScreenState extends State<RegisterServiceScreen> {
  final ApiClient api = ApiClient();
  String? selected;
  final noteCtrl = TextEditingController();
  DateTime? selectedDate;
  bool submitting = false;

  final List<Map<String, String>> options = [
    {'code': 'CLEANING', 'label': 'Dọn vệ sinh'},
    {'code': 'REPAIR', 'label': 'Sửa chữa'},
    {'code': 'INSTALL', 'label': 'Lắp đặt'},
    {'code': 'MAINTENANCE', 'label': 'Bảo trì'},
  ];

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (selected == null || selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn loại dịch vụ và ngày')),
      );
      return;
    }
    setState(() => submitting = true);
    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate!);
      await api.dio.post('/register-service', data: {
        'serviceType': selected,
        'date': formattedDate,
        'note': noteCtrl.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đăng ký thành công')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RegisterServiceListScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đăng ký thất bại')),
      );
    } finally {
      setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký dịch vụ')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          DropdownButtonFormField<String>(
            value: selected,
            items: options
                .map((o) => DropdownMenuItem(value: o['code'], child: Text(o['label']!)))
                .toList(),
            onChanged: (v) => setState(() => selected = v),
            decoration: const InputDecoration(labelText: 'Loại dịch vụ'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(selectedDate == null
                    ? 'Chưa chọn ngày'
                    : 'Ngày: ${DateFormat('dd/MM/yyyy').format(selectedDate!)}'),
              ),
              TextButton(onPressed: _pickDate, child: const Text('Chọn ngày')),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Ghi chú (không bắt buộc)'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: submitting ? null : _submit,
            child: submitting
                ? const CircularProgressIndicator()
                : const Text('Gửi'),
          ),
        ]),
      ),
    );
  }
}