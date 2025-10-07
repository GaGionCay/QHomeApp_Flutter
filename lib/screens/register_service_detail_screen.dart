import 'package:flutter/material.dart';
import '../services/register_service.dart';
import 'package:intl/intl.dart';

class RegisterServiceDetailScreen extends StatefulWidget {
  final RegisterServiceService service;
  final int serviceId;

  const RegisterServiceDetailScreen({
    super.key,
    required this.service,
    required this.serviceId,
  });

  @override
  State<RegisterServiceDetailScreen> createState() =>
      _RegisterServiceDetailScreenState();
}

class _RegisterServiceDetailScreenState
    extends State<RegisterServiceDetailScreen> {
  Map<String, dynamic>? detail;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  void _loadDetail() async {
    setState(() => loading = true);
    try {
      final data = await widget.service.getServiceDetail(widget.serviceId);
      setState(() {
        detail = data;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load service detail')),
      );
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
      appBar: AppBar(title: const Text('Service Detail')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : detail == null
              ? const Center(child: Text('Service not found'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail!['serviceType'] ?? '',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Note: ${detail!['note'] ?? 'N/A'}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Status: ${detail!['status'] ?? 'Pending'}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Created At: ${_formatDate(detail!['createdAt'])}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Updated At: ${_formatDate(detail!['updatedAt'])}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'User Email: ${detail!['userEmail'] ?? 'N/A'}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
    );
  }
}
