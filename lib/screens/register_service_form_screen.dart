import 'package:flutter/material.dart';
import '../services/register_service.dart';
import 'package:intl/intl.dart';

class RegisterServiceFormScreen extends StatefulWidget {
  final RegisterServiceService service;

  const RegisterServiceFormScreen({super.key, required this.service});

  @override
  State<RegisterServiceFormScreen> createState() =>
      _RegisterServiceFormScreenState();
}

class _RegisterServiceFormScreenState extends State<RegisterServiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedServiceType;
  final TextEditingController _noteController = TextEditingController();
  bool _loading = false;

  final List<String> _serviceTypes = [
    'CLEANING',
    'REPAIR',
    'MOVING',
    'OTHER',
  ];

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final today = DateTime.now();
      final formattedDate = DateFormat('yyyy-MM-dd').format(today);

      await widget.service.registerService(
        serviceType: _selectedServiceType!,
        date: formattedDate,
        note: _noteController.text.trim(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service registered successfully')),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to register service: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Service')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedServiceType,
                decoration: const InputDecoration(labelText: 'Service Type'),
                items: _serviceTypes
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedServiceType = value);
                },
                validator: (value) =>
                    value == null ? 'Please select a service type' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Register'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
