import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/register_service.dart';

class ServiceRegistrationPage extends StatefulWidget {
  final int id; // truyền từ HomePage
  final String email;
  const ServiceRegistrationPage({
    super.key,
    required this.id,
    required this.email,
  });

  @override
  State<ServiceRegistrationPage> createState() =>
      _ServiceRegistrationPageState();
}

class _ServiceRegistrationPageState extends State<ServiceRegistrationPage> {
  // Thay thế _serviceTypeController bằng biến này để lưu giá trị đã chọn
  String? _selectedServiceType; 
  final _detailsController = TextEditingController();
  final _service = RegisterService();
  final List<String> _serviceTypes = ['Thẻ xe', 'Thang máy'];

  void _submit() async {
    final serviceType = _selectedServiceType; 
    final details = _detailsController.text.trim();

    if (serviceType == null || details.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đầy đủ thông tin')),
      );
      return;
    }

    final result = await _service.registerService(
      id: widget.id,
      email: widget.email,
      serviceType: serviceType,
      details: details,
    );

    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đăng ký thành công')));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký dịch vụ')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Thay thế TextField bằng DropdownButton
            DropdownButtonFormField<String>(
              value: _selectedServiceType,
              hint: const Text('Chọn loại dịch vụ'),
              decoration: const InputDecoration(
                labelText: 'Loại dịch vụ',
                border: OutlineInputBorder(),
              ),
              items: _serviceTypes.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedServiceType = newValue;
                });
              },
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _detailsController,
              decoration: const InputDecoration(
                labelText: 'Chi tiết (VD: biển số xe, tầng...)',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submit,
              child: const Text('Gửi đăng ký'),
            ),
          ],
        ),
      ),
    );
  }
}