import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../models/unit_info.dart';
import '../profile/profile_service.dart';
import 'cleaning_request_service.dart';

class CleaningRequestScreen extends StatefulWidget {
  const CleaningRequestScreen({super.key});

  @override
  State<CleaningRequestScreen> createState() => _CleaningRequestScreenState();
}

class _CleaningRequestScreenState extends State<CleaningRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ApiClient _apiClient;
  late final CleaningRequestService _service;
  late final ProfileService _profileService;
  late final ContractService _contractService;

  UnitInfo? _selectedUnit;
  bool _loadingUnit = true;
  bool _loadingProfile = true;
  bool _submitting = false;
  bool _attemptedSubmit = false;

  final _locationController = TextEditingController();
  final _noteController = TextEditingController();
  final _contactPhoneController = TextEditingController();

  String? _selectedCleaningType;
  DateTime? _cleaningDate;
  TimeOfDay? _startTime;
  final Set<String> _selectedExtras = <String>{};
  String? _dateError;
  String? _timeError;

  static const _selectedUnitPrefsKey = 'selected_unit_id';
  static const TimeOfDay _workingStart = TimeOfDay(hour: 8, minute: 0);
  static const TimeOfDay _workingEnd = TimeOfDay(hour: 18, minute: 0);

  final NumberFormat _currencyFormatter =
      NumberFormat.currency(locale: 'vi_VN', symbol: 'đ', decimalDigits: 0);

  bool get _isLoading => _loadingUnit || _loadingProfile;

  _CleaningPackage? get _currentPackage {
    final selected = _selectedCleaningType;
    if (selected == null) return null;
    for (final pkg in _cleaningPackages) {
      if (pkg.name == selected) return pkg;
    }
    return null;
  }

  int get _basePrice => _currentPackage?.price ?? 0;

  int _extraPriceFor(String name) {
    for (final option in _extraServiceOptions) {
      if (option.name == name) {
        return option.price;
      }
    }
    return 0;
  }

  int get _extrasPrice =>
      _selectedExtras.fold(0, (sum, name) => sum + _extraPriceFor(name));

  int get _totalPrice => _basePrice + _extrasPrice;

  String _formatDuration(double value) {
    return value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
  }

  String _formatCurrency(num value) {
    final formatted = _currencyFormatter.format(value);
    return formatted.replaceAll('\u00A0', ' ').trim();
  }

  String _formatDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  bool _isSelectedDateToday() {
    final date = _cleaningDate;
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _isTimeInPast(TimeOfDay value) {
    final now = DateTime.now();
    final minutesNow = now.hour * 60 + now.minute;
    return _toMinutes(value) <= minutesNow;
  }

  bool _isWithinWorkingHours(TimeOfDay value) {
    final minutes = _toMinutes(value);
    return minutes >= _toMinutes(_workingStart) &&
        minutes <= _toMinutes(_workingEnd);
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String? _evaluateDateError(DateTime? value) {
    if (value == null) return 'Vui lòng chọn ngày dọn dẹp';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (value.isBefore(today)) {
      return 'Ngày dọn dẹp không thể trước hôm nay';
    }
    return null;
  }

  String? _evaluateTimeError(TimeOfDay? value) {
    if (value == null) return 'Vui lòng chọn khung giờ bắt đầu';
    if (!_isWithinWorkingHours(value)) {
      return 'Chỉ nhận yêu cầu từ ${_formatTime(_workingStart)} - ${_formatTime(_workingEnd)}';
    }
    if (_isSelectedDateToday() && _isTimeInPast(value)) {
      return 'Khung giờ đã trôi qua, vui lòng chọn giờ khác';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _service = CleaningRequestService(_apiClient);
    _profileService = ProfileService(_apiClient.dio);
    _contractService = ContractService(_apiClient);
    _loadUnitContext();
    _loadProfile();
  }

  Future<void> _loadUnitContext() async {
    try {
      final units = await _contractService.getMyUnits();
      String? selectedUnitId;
      try {
        final prefs = await SharedPreferences.getInstance();
        selectedUnitId = prefs.getString(_selectedUnitPrefsKey);
      } catch (_) {
        selectedUnitId = null;
      }

      UnitInfo? unit;
      if (selectedUnitId != null) {
        for (final item in units) {
          if (item.id == selectedUnitId) {
            unit = item;
            break;
          }
        }
      }

      unit ??= units.isNotEmpty ? units.first : null;

      if (unit != null && unit.id.isNotEmpty) {
        _locationController.text = unit.displayName;
      }

      if (mounted) {
        setState(() {
          _selectedUnit = unit;
        });
      }
    } catch (e) {
      _showMessage(
        'Không thể tải thông tin căn hộ. Vui lòng thử lại.',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingUnit = false;
        });
      }
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      final phone = profile['phoneNumber']?.toString() ?? '';
      if (mounted) {
        _contactPhoneController.text = phone;
      }
    } catch (_) {
      // allow manual input
    } finally {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
        });
      }
    }
  }

  Future<void> _pickCleaningDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _cleaningDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() {
        _cleaningDate = picked;
        _dateError = _evaluateDateError(picked);
        _timeError = _evaluateTimeError(_startTime);
      });
      if (_dateError != null) {
        _showMessage(_dateError!, color: Colors.orange);
      }
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      final error = _evaluateTimeError(picked);
      setState(() {
        _startTime = picked;
        _timeError = error;
      });
      if (error != null) {
        _showMessage(error, color: Colors.orange);
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      _attemptedSubmit = true;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }
    final selectedPackage = _currentPackage;
    if (selectedPackage == null) {
      _showMessage('Vui lòng chọn loại hình dọn dẹp', color: Colors.orange);
      return;
    }
    final dateError = _evaluateDateError(_cleaningDate);
    final timeError = _evaluateTimeError(_startTime);
    setState(() {
      _dateError = dateError;
      _timeError = timeError;
    });
    if (dateError != null || timeError != null) {
      _showMessage('Vui lòng kiểm tra lại ngày và khung giờ',
          color: Colors.orange);
      return;
    }
    if (_selectedUnit == null) {
      _showMessage(
        'Không tìm thấy thông tin căn hộ. Vui lòng thử lại.',
        color: Colors.red,
      );
      return;
    }
    if (_submitting) return;

    setState(() {
      _submitting = true;
    });

    final startDuration = Duration(
      hours: _startTime!.hour,
      minutes: _startTime!.minute,
    );

    try {
      await _service.createRequest(
        unitId: _selectedUnit!.id,
        cleaningType: selectedPackage.name,
        cleaningDate: _cleaningDate!,
        startTime: startDuration,
        durationHours: selectedPackage.durationHours,
        location: _locationController.text.trim(),
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        contactPhone: _contactPhoneController.text.trim(),
        extraServices: _selectedExtras.toList(),
      );
      if (!mounted) return;
      _showMessage(
        'Đã gửi yêu cầu dọn dẹp. Tổng dự kiến ${_formatCurrency(_totalPrice)}',
        color: Colors.green,
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _showMessage(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _locationController.dispose();
    _noteController.dispose();
    _contactPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo yêu cầu dọn dẹp'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUnitSection(theme),
                    _buildCleaningPackagesSection(),
                    _buildScheduleSection(),
                    _buildContactSection(),
                    _buildExtrasSection(),
                    _buildNoteField(),
                    _buildPriceSummary(),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.08),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: FilledButton.icon(
          onPressed: (_submitting || _isLoading) ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cleaning_services_outlined),
          label: Text(
            _totalPrice > 0
                ? 'Gửi yêu cầu (${_formatCurrency(_totalPrice)})'
                : 'Gửi yêu cầu',
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    String? subtitle,
    required Widget child,
    String? errorText,
  }) {
    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surface.withValues(alpha: 
      theme.brightness == Brightness.dark ? 0.7 : 0.95,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: surfaceColor,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 
              theme.brightness == Brightness.dark ? 0.35 : 0.08,
            ),
            blurRadius: 32,
            offset: const Offset(0, 12),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
          if (errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              errorText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnitSection(ThemeData theme) {
    final unit = _selectedUnit;
    return _buildSection(
      title: 'Căn hộ yêu cầu',
      subtitle: 'Thông tin được lấy từ hợp đồng đang hoạt động',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.apartment_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: unit == null
                    ? const Text('Không tìm thấy thông tin căn hộ')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unit.displayName,
                            style: theme.textTheme.titleMedium,
                          ),
                          if ((unit.buildingName ?? '').isNotEmpty)
                            Text(
                              unit.buildingName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color
                                    ?.withValues(alpha: 0.7),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Địa điểm thực hiện',
              hintText: 'Ví dụ: Phòng khách, tầng 2...',
              border: OutlineInputBorder(),
            ),
            maxLength: 255,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập địa điểm';
              }
              if (value.trim().length < 3) {
                return 'Địa điểm phải có ít nhất 3 ký tự';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCleaningPackagesSection() {
    return _buildSection(
      title: 'Loại hình dọn dẹp',
      subtitle: 'Mỗi gói có thời lượng và chi phí khác nhau',
      errorText: _attemptedSubmit && _selectedCleaningType == null
          ? 'Vui lòng chọn 1 loại hình dọn dẹp'
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 520;
          final double itemWidth =
              isWide ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: _cleaningPackages.map((pkg) {
              final selected = _selectedCleaningType == pkg.name;
              return SizedBox(
                width: itemWidth,
                child: _buildSelectableCard(
                  title: pkg.name,
                  description: pkg.description,
                  chipLabel:
                      '${_formatDuration(pkg.durationHours)} giờ • ${_formatCurrency(pkg.price)}',
                  icon: pkg.icon,
                  selected: selected,
                  onTap: () {
                    setState(() {
                      _selectedCleaningType = pkg.name;
                    });
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildScheduleSection() {
    return _buildSection(
      title: 'Lịch dọn dẹp',
      subtitle: 'Ngày không trước hiện tại, khung giờ hành chính',
      child: Column(
        children: [
          _buildPickerRow(
            label: 'Ngày dọn dẹp',
            value:
                _cleaningDate == null ? 'Chưa chọn' : _formatDate(_cleaningDate!),
            buttonLabel: 'Chọn ngày',
            onPressed: _pickCleaningDate,
            errorText: _dateError,
          ),
          const SizedBox(height: 12),
          _buildPickerRow(
            label: 'Khung giờ bắt đầu',
            value:
                _startTime == null ? 'Chưa chọn' : _formatTime(_startTime!),
            buttonLabel: 'Chọn giờ',
            onPressed: _pickStartTime,
            errorText: _timeError,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            label: 'Thời lượng ước tính',
            value: _currentPackage == null
                ? '--'
                : '${_formatDuration(_currentPackage!.durationHours)} giờ',
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection() {
    return _buildSection(
      title: 'Thông tin liên hệ',
      subtitle: 'Nhân viên sẽ gọi xác nhận trước khi đến',
      child: TextFormField(
      controller: _contactPhoneController,
      decoration: const InputDecoration(
        labelText: 'Số điện thoại liên hệ',
        border: OutlineInputBorder(),
      ),
      keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ],
        autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Vui lòng nhập số điện thoại';
          }
          if (!RegExp(r'^0\d{9}$').hasMatch(value)) {
            return 'Số điện thoại phải có 10 số và bắt đầu bằng 0';
        }
        return null;
      },
      ),
    );
  }

  Widget _buildExtrasSection() {
    return _buildSection(
      title: 'Dịch vụ bổ sung',
      subtitle: 'Có thể chọn nhiều dịch vụ, giá sẽ cộng dồn',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 520;
          final double itemWidth = isWide
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _extraServiceOptions.map((option) {
              final selected = _selectedExtras.contains(option.name);
              return SizedBox(
                width: itemWidth,
                child: _buildSelectableCard(
                  title: option.name,
                  description: option.description,
                  chipLabel: _formatCurrency(option.price),
                  selected: selected,
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selectedExtras.remove(option.name);
                      } else {
                        _selectedExtras.add(option.name);
                      }
                    });
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildNoteField() {
    return _buildSection(
      title: 'Ghi chú cho nhân viên',
      subtitle: 'Ví dụ: mang theo dụng cụ lau kính, chú ý trẻ nhỏ...',
      child: TextFormField(
        controller: _noteController,
        maxLines: 4,
        maxLength: 500,
        decoration: const InputDecoration(
          hintText: 'Ghi chú / yêu cầu đặc biệt (tùy chọn)',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
    );
  }

  Widget _buildPriceSummary() {
    final theme = Theme.of(context);
    return _buildSection(
      title: 'Chi phí dự kiến',
      subtitle: 'Áp dụng khi nhân viên xác nhận lịch',
      child: Column(
        children: [
          _buildPriceRow('Gói dịch vụ', _basePrice),
          const SizedBox(height: 8),
          _buildPriceRow('Dịch vụ bổ sung', _extrasPrice),
          const Divider(height: 32),
          _buildPriceRow('Tổng cộng', _totalPrice, highlight: true),
          const SizedBox(height: 8),
          Text(
            'Giá có thể điều chỉnh nếu phát sinh thêm nhu cầu.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectableCard({
    required String title,
    required String description,
    required String chipLabel,
    IconData? icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.4);
    final gradientColors = selected
        ? [
            theme.colorScheme.primary.withValues(alpha: 0.15),
            theme.colorScheme.primary.withValues(alpha: 0.05),
          ]
        : [
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
          ];
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: selected ? 24 : 12,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                if (icon != null) const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                chipLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerRow({
    required String label,
    required String value,
    required String buttonLabel,
    required VoidCallback onPressed,
    String? errorText,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow({required String label, required String value}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }

  Widget _buildPriceRow(String label, int value, {bool highlight = false}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Text(
          value > 0 ? _formatCurrency(value) : '—',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
            color: highlight ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }

}

class _CleaningPackage {
  final String name;
  final String description;
  final double durationHours;
  final int price;
  final IconData icon;

  const _CleaningPackage({
    required this.name,
    required this.description,
    required this.durationHours,
    required this.price,
    required this.icon,
  });
}

class _ExtraServiceOption {
  final String name;
  final String description;
  final int price;

  const _ExtraServiceOption({
    required this.name,
    required this.description,
    required this.price,
  });
}

const List<_CleaningPackage> _cleaningPackages = [
  _CleaningPackage(
    name: 'Dọn dẹp cơ bản',
    description: 'Vệ sinh định kỳ cho căn hộ 1-2 phòng ngủ.',
    durationHours: 1,
    price: 250000,
    icon: Icons.cleaning_services_outlined,
  ),
  _CleaningPackage(
    name: 'Dọn dẹp tổng thể',
    description: 'Làm sạch toàn căn hộ, bao gồm hút bụi và lau bề mặt.',
    durationHours: 2,
    price: 450000,
    icon: Icons.house_outlined,
  ),
  _CleaningPackage(
    name: 'Dọn bếp',
    description: 'Làm sạch khu vực bếp, bếp nấu, tủ lạnh và khử mùi dầu mỡ.',
    durationHours: 1.5,
    price: 320000,
    icon: Icons.kitchen_outlined,
  ),
  _CleaningPackage(
    name: 'Dọn phòng khách',
    description: 'Tập trung sofa, rèm, bàn ghế và các bề mặt phòng khách.',
    durationHours: 1.5,
    price: 300000,
    icon: Icons.weekend_outlined,
  ),
  _CleaningPackage(
    name: 'Giặt rèm',
    description: 'Tháo lắp và giặt rèm với dung dịch chuyên dụng.',
    durationHours: 2,
    price: 380000,
    icon: Icons.blinds_closed_outlined,
  ),
  _CleaningPackage(
    name: 'Khử mùi toàn căn',
    description: 'Khử mùi ẩm mốc, thuốc lá bằng máy Ozone chuyên dụng.',
    durationHours: 1.5,
    price: 360000,
    icon: Icons.air_outlined,
  ),
  _CleaningPackage(
    name: 'Vệ sinh thiết bị',
    description: 'Vệ sinh điều hòa, quạt và thiết bị điện tử nhẹ.',
    durationHours: 1,
    price: 220000,
    icon: Icons.build_outlined,
  ),
];

const List<_ExtraServiceOption> _extraServiceOptions = [
  _ExtraServiceOption(
    name: 'Lau kính toàn bộ',
    description: 'Bao gồm kính ban công, cửa sổ và gương lớn.',
    price: 180000,
  ),
  _ExtraServiceOption(
    name: 'Giặt thảm',
    description: 'Giặt khô và khử mùi cho tối đa 2 tấm thảm nhỏ.',
    price: 220000,
  ),
  _ExtraServiceOption(
    name: 'Khử khuẩn toàn căn',
    description: 'Phun dung dịch khử khuẩn nano bạc cho mọi phòng.',
    price: 200000,
  ),
  _ExtraServiceOption(
    name: 'Đánh bóng sàn',
    description: 'Áp dụng cho sàn gỗ/đá, bao gồm phủ bóng nhẹ.',
    price: 260000,
  ),
  _ExtraServiceOption(
    name: 'Chăm sóc nội thất da',
    description: 'Lau sạch và phủ dưỡng chất cho sofa, ghế da.',
    price: 190000,
  ),
];

