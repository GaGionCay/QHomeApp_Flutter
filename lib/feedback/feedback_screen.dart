import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/asset_maintenance_api_client.dart';
import '../auth/customer_interaction_api_client.dart';
import '../service_registration/service_booking_service.dart';
import '../theme/app_colors.dart';
import 'feedback_service.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  late final FeedbackService _feedbackService;
  late final ServiceBookingService _bookingService;
  final ScrollController _scrollController = ScrollController();

  final List<FeedbackRequest> _requests = [];
  List<Map<String, dynamic>> _paidBookings = [];
  Map<String, int> _statusCounts = const {};

  bool _loading = true;
  bool _loadingMore = false;
  bool _countsLoading = true;
  bool _loadingBookings = true;
  String? _error;
  String? _countsError;
  String? _bookingsError;

  int _currentPage = 0;
  bool _isLastPage = false;

  String? _statusFilter;
  String? _priorityFilter;

  @override
  void initState() {
    super.initState();
    _feedbackService = FeedbackService(CustomerInteractionApiClient());
    _bookingService = ServiceBookingService(AssetMaintenanceApiClient());
    _scrollController.addListener(_onScroll);
    _loadCounts();
    _loadRequests(reset: true);
    _loadPaidBookings();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    setState(() {
      _countsLoading = true;
      _countsError = null;
    });
    try {
      final counts = await _feedbackService.getCounts(
        priority: _priorityFilter,
      );
      if (!mounted) return;
      setState(() {
        _statusCounts = counts;
        _countsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _countsError = e.toString();
        _countsLoading = false;
      });
    }
  }

  Future<void> _loadRequests({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _currentPage = 0;
        _isLastPage = false;
        _requests.clear();
      });
    } else {
      if (_loadingMore || _loading || _isLastPage) return;
      setState(() => _loadingMore = true);
    }

    try {
      final page = await _feedbackService.getRequests(
        page: _currentPage,
        status: _statusFilter,
        priority: _priorityFilter,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _requests
            ..clear()
            ..addAll(page.items);
        } else {
          _requests.addAll(page.items);
        }
        _currentPage = page.pageNumber + 1;
        _isLastPage = page.isLast;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        !_isLastPage &&
        !_loading) {
      _loadRequests();
    }
  }

  void _onStatusSelected(String? status) {
    setState(() {
      _statusFilter = status;
    });
    _loadRequests(reset: true);
    _loadCounts();
  }

  void _onPrioritySelected(String? priority) {
    setState(() {
      _priorityFilter = priority;
    });
    _loadRequests(reset: true);
    _loadCounts();
  }

  Future<void> _loadPaidBookings() async {
    setState(() {
      _loadingBookings = true;
      _bookingsError = null;
    });
    try {
      final bookings = await _bookingService.getPaidBookings();
      if (!mounted) return;
      setState(() {
        _paidBookings = bookings;
        _loadingBookings = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookingsError = e.toString();
        _loadingBookings = false;
      });
    }
  }

  Future<void> _openCreateDialog({String? bookingId}) async {
    final result = await showModalBottomSheet<FeedbackRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeedbackFormSheet(
        service: _feedbackService,
        bookingService: _bookingService,
        selectedBookingId: bookingId,
      ),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Đã gửi phản ánh thành công!'),
        ),
      );
      await _refresh();
      await _loadPaidBookings(); // Reload bookings sau khi gửi feedback
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadCounts(),
      _loadRequests(reset: true),
      _loadPaidBookings(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phản ánh & Hỗ trợ'),
        backgroundColor: AppColors.primaryEmerald,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: null, // Bỏ FAB vì sẽ click vào booking để gửi feedback
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(theme),
                    const SizedBox(height: 16),
                    // Section: Dịch vụ đã sử dụng
                    _buildPaidBookingsSection(theme),
                    const SizedBox(height: 16),
                    // Section: Phản ánh của tôi
                    _buildMyFeedbacksHeader(theme),
                    const SizedBox(height: 12),
                    _buildFilters(theme),
                    const SizedBox(height: 12),
                    _buildCounts(theme),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            if (_loading && _requests.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _requests.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildErrorState(),
              )
            else if (_requests.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final request = _requests[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: index == _requests.length - 1 ? 24 : 12,
                      ),
                      child: _FeedbackCard(
                        request: request,
                        bookingService: _bookingService,
                      ),
                    );
                  },
                  childCount: _requests.length,
                ),
              ),
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.support_agent, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Phản ánh về tiện ích nội khu sau khi sử dụng dịch vụ.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildPaidBookingsSection(ThemeData theme) {
    if (_loadingBookings) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_bookingsError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Không thể tải danh sách dịch vụ: ${_bookingsError!.replaceFirst('Exception: ', '')}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.red,
          ),
        ),
      );
    }

    if (_paidBookings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bạn chưa có dịch vụ nào đã thanh toán. Sau khi thanh toán dịch vụ, bạn có thể phản ánh tại đây.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dịch vụ đã sử dụng',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ..._paidBookings.map((booking) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PaidBookingCard(
              booking: booking,
              onTap: () => _openCreateDialog(bookingId: booking['id']?.toString()),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMyFeedbacksHeader(ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.history, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Text(
          'Phản ánh của tôi',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        DropdownButtonHideUnderline(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButton<String?>(
                value: _statusFilter,
                hint: const Text('Trạng thái'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tất cả trạng thái'),
                  ),
                  ..._statusLabels.entries.map(
                    (entry) => DropdownMenuItem<String?>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  ),
                ],
                onChanged: _onStatusSelected,
              ),
            ),
          ),
        ),
        DropdownButtonHideUnderline(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButton<String?>(
                value: _priorityFilter,
                hint: const Text('Mức ưu tiên'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tất cả ưu tiên'),
                  ),
                  ..._priorityLabels.entries.map(
                    (entry) => DropdownMenuItem<String?>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  ),
                ],
                onChanged: _onPrioritySelected,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCounts(ThemeData theme) {
    if (_countsLoading) {
      return const LinearProgressIndicator();
    }

    if (_countsError != null) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _countsError!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: _loadCounts,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (_statusCounts.isEmpty) {
      return const SizedBox.shrink();
    }

    final total = _statusCounts['total'] ?? 0;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatusChip(
          label: 'Tổng',
          value: total,
          color: theme.colorScheme.primary,
        ),
        ..._statusLabels.entries.map(
          (entry) => _StatusChip(
            label: entry.value,
            value: _statusCounts[entry.key] ?? 0,
            color: _statusColors[entry.key] ?? theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Đã xảy ra lỗi không xác định',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _loadRequests(reset: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Bạn chưa có phản ánh nào.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Bấm "Gửi phản ánh" để tạo yêu cầu đầu tiên.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = color.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(
            '$label · $value',
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatefulWidget {
  const _FeedbackCard({
    required this.request,
    this.bookingService,
  });

  final FeedbackRequest request;
  final ServiceBookingService? bookingService;

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard> {
  Map<String, dynamic>? _bookingDetails;
  bool _loadingBooking = false;

  @override
  void initState() {
    super.initState();
    if (widget.request.serviceBookingId != null &&
        widget.request.serviceBookingId!.isNotEmpty &&
        widget.bookingService != null) {
      _loadBookingDetails();
    }
  }

  Future<void> _loadBookingDetails() async {
    if (widget.request.serviceBookingId == null ||
        widget.request.serviceBookingId!.isEmpty ||
        widget.bookingService == null) {
      return;
    }

    setState(() => _loadingBooking = true);
    try {
      final booking = await widget.bookingService!
          .getBookingById(widget.request.serviceBookingId!);
      if (!mounted) return;
      setState(() {
        _bookingDetails = booking;
        _loadingBooking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = DateFormat('dd/MM/yyyy HH:mm');
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.request.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '#${widget.request.requestCode}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildStatusBadge(widget.request.status, theme),
                    const SizedBox(height: 6),
                    _buildPriorityBadge(widget.request.priority, theme),
                  ],
                ),
              ],
            ),
            // Hiển thị thông tin dịch vụ nếu có
            if (widget.request.serviceBookingId != null &&
                widget.request.serviceBookingId!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildServiceInfo(theme),
            ],
            const SizedBox(height: 12),
            Text(
              widget.request.content,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text(
                  formatter.format(widget.request.createdAt.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceInfo(ThemeData theme) {
    if (_loadingBooking) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Đang tải thông tin dịch vụ...',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    if (_bookingDetails == null) {
      return const SizedBox.shrink();
    }

    final serviceName =
        _bookingDetails!['serviceName']?.toString() ?? 'Dịch vụ';
    final bookingDate = _bookingDetails!['bookingDate']?.toString();
    final bookingCode = _bookingDetails!['bookingCode']?.toString() ?? '';

    String dateText = '';
    if (bookingDate != null) {
      try {
        final date = DateTime.parse(bookingDate);
        dateText = DateFormat('dd/MM/yyyy').format(date);
      } catch (_) {
        dateText = bookingDate;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_available,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Về dịch vụ: $serviceName',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (dateText.isNotEmpty || bookingCode.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (dateText.isNotEmpty)
                        Text(
                          'Ngày: $dateText',
                          style: theme.textTheme.bodySmall,
                        ),
                      if (bookingCode.isNotEmpty)
                        Text(
                          'Mã: $bookingCode',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status, ThemeData theme) {
    final label = _statusLabels[status] ?? status;
    final color = _statusColors[status] ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String priority, ThemeData theme) {
    final label = _priorityLabels[priority] ?? priority;
    final color = _priorityColors[priority] ?? theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class FeedbackFormSheet extends StatefulWidget {
  const FeedbackFormSheet({
    super.key,
    required this.service,
    required this.bookingService,
    this.selectedBookingId,
  });

  final FeedbackService service;
  final ServiceBookingService bookingService;
  final String? selectedBookingId;

  @override
  State<FeedbackFormSheet> createState() => _FeedbackFormSheetState();
}

class _FeedbackFormSheetState extends State<FeedbackFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  String _priority = 'MEDIUM';
  bool _submitting = false;
  bool _loadingBooking = false;
  Map<String, dynamic>? _selectedBooking;

  @override
  void initState() {
    super.initState();
    if (widget.selectedBookingId != null) {
      _loadBookingDetails();
    }
  }

  Future<void> _loadBookingDetails() async {
    if (widget.selectedBookingId == null) return;
    setState(() => _loadingBooking = true);
    try {
      final booking = await widget.bookingService.getBookingById(widget.selectedBookingId!);
      if (!mounted) return;
      setState(() {
        _selectedBooking = booking;
        _loadingBooking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingBooking = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final request = await widget.service.createRequest(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        priority: _priority,
        serviceBookingId: widget.selectedBookingId,
      );
      if (!mounted) return;
      Navigator.pop(context, request);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SingleChildScrollView(
            controller: controller,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Text(
                    widget.selectedBookingId != null
                        ? 'Phản ánh về dịch vụ'
                        : 'Gửi phản ánh mới',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  // Hiển thị thông tin booking nếu đã chọn
                  if (widget.selectedBookingId != null) ...[
                    if (_loadingBooking)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_selectedBooking != null)
                      _buildSelectedBookingInfo(_selectedBooking!, theme),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Tiêu đề',
                      hintText: 'Hãy ghi tiêu đề rõ ràng để ban quản lý phân loại yêu cầu dễ dàng hơn',
                    ),
                    textInputAction: TextInputAction.next,
                    maxLength: 255,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Vui lòng nhập tiêu đề';
                      }
                      if (value.trim().length < 5) {
                        return 'Tiêu đề phải có ít nhất 5 ký tự';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contentController,
                    decoration: const InputDecoration(
                      labelText: 'Nội dung chi tiết',
                      hintText: 'Mô tả vấn đề của bạn để ban quản lý hỗ trợ nhanh hơn',
                    ),
                    maxLines: 5,
                    maxLength: 1000,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Vui lòng mô tả vấn đề';
                      }
                      if (value.trim().length < 10) {
                        return 'Vui lòng mô tả chi tiết hơn (tối thiểu 10 ký tự)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Mức ưu tiên'),
                    items: _priorityLabels.entries.map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    ).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _priority = value);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(_submitting ? 'Đang gửi...' : 'Gửi phản ánh'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

const Map<String, String> _statusLabels = <String, String>{
  'PENDING': 'Chờ xử lý',
  'IN_PROGRESS': 'Đang xử lý',
  'RESOLVED': 'Đã giải quyết',
  'CLOSED': 'Đã đóng',
};

const Map<String, Color> _statusColors = <String, Color>{
  'PENDING': Color(0xFFFB8C00),
  'IN_PROGRESS': Color(0xFF42A5F5),
  'RESOLVED': Color(0xFF26A69A),
  'CLOSED': Color(0xFF9E9E9E),
};

const Map<String, String> _priorityLabels = <String, String>{
  'LOW': 'Thấp',
  'MEDIUM': 'Trung bình',
  'HIGH': 'Cao',
  'URGENT': 'Khẩn cấp',
};

const Map<String, Color> _priorityColors = <String, Color>{
  'LOW': Color(0xFF90A4AE),
  'MEDIUM': Color(0xFF26A69A),
  'HIGH': Color(0xFFFF7043),
  'URGENT': Color(0xFFD32F2F),
};

// Widget hiển thị thông tin booking đã chọn trong form
Widget _buildSelectedBookingInfo(
  Map<String, dynamic> booking,
  ThemeData theme,
) {
  final serviceName = booking['serviceName']?.toString() ?? 'Dịch vụ';
  final bookingDate = booking['bookingDate']?.toString();
  final bookingCode = booking['bookingCode']?.toString() ?? '';
  final totalAmount = booking['totalAmount'];

  String dateText = '';
  if (bookingDate != null) {
    try {
      final date = DateTime.parse(bookingDate);
      dateText = DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      dateText = bookingDate;
    }
  }

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: theme.colorScheme.primary.withValues(alpha: 0.3),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.event_available,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Dịch vụ đã chọn',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          serviceName,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (dateText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Ngày sử dụng: $dateText',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (bookingCode.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Mã đặt: $bookingCode',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (totalAmount != null) ...[
          const SizedBox(height: 4),
          Text(
            'Tổng tiền: ${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(totalAmount)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    ),
  );
}

// Widget hiển thị paid booking card
class _PaidBookingCard extends StatelessWidget {
  const _PaidBookingCard({
    required this.booking,
    required this.onTap,
  });

  final Map<String, dynamic> booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final serviceName = booking['serviceName']?.toString() ?? 'Dịch vụ';
    final bookingDate = booking['bookingDate']?.toString();
    final bookingCode = booking['bookingCode']?.toString() ?? '';
    final totalAmount = booking['totalAmount'];

    String dateText = '';
    if (bookingDate != null) {
      try {
        final date = DateTime.parse(bookingDate);
        dateText = DateFormat('dd/MM/yyyy').format(date);
      } catch (_) {
        dateText = bookingDate;
      }
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.event_available,
                color: colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    serviceName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  if (dateText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      dateText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? Colors.white70
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (bookingCode.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Mã: $bookingCode',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? Colors.white70
                            : AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (totalAmount != null) ...[
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    NumberFormat.currency(locale: 'vi_VN', symbol: '₫')
                        .format(totalAmount),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

