import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/register_service.dart';
import 'register_service_detail_screen.dart';
import 'register_service_form_screen.dart';
import 'package:intl/intl.dart';

class MyRegisterServiceScreen extends StatefulWidget {
  final AuthService authService;

  const MyRegisterServiceScreen({super.key, required this.authService});

  @override
  State<MyRegisterServiceScreen> createState() =>
      _MyRegisterServiceScreenState();
}

class _MyRegisterServiceScreenState extends State<MyRegisterServiceScreen> {
  late final RegisterServiceService service;
  List<dynamic> list = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    service = RegisterServiceService(apiClient: widget.authService.apiClient);
    _loadServices();
  }

  void _loadServices() async {
    setState(() => loading = true);
    try {
      final data = await service.getMyServices();
      if (data == null) throw Exception('No data received');
      setState(() {
        list = data;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
      debugPrint('Error loading services: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load services: $e')));
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (e) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Registered Services')),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RegisterServiceFormScreen(service: service),
            ),
          );
          _loadServices(); // refresh sau khi thêm
        },
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(child: Text('No registered services'))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final item = list[index];
                    return ListTile(
                      title: Text(item['serviceType'] ?? 'Unknown'),
                      subtitle: Text(
                        'Note: ${item['note'] ?? 'N/A'}\n'
                        'Status: ${item['status'] ?? 'Pending'}\n'
                        'Created At: ${_formatDate(item['createdAt'])}\n'
                        'Updated At: ${_formatDate(item['updatedAt'])}\n'
                        'User Email: ${item['userEmail'] ?? 'N/A'}',
                      ),
                      isThreeLine: false,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RegisterServiceDetailScreen(
                              service: service,
                              serviceId: item['id'],
                            ),
                          ),
                        );
                        _loadServices();
                      },
                    );
                  },
                ),
    );
  }
}
