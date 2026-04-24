import 'package:flutter/material.dart';

class UnsafeAreaDialog extends StatefulWidget {
  final void Function(UnsafeAreaData) onConfirm;
  final VoidCallback? onCancel;
  final double latitude;
  final double longitude;

  const UnsafeAreaDialog({
    super.key,
    required this.onConfirm,
    this.onCancel,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<UnsafeAreaDialog> createState() => _UnsafeAreaDialogState();
}

class _UnsafeAreaDialogState extends State<UnsafeAreaDialog>
    with TickerProviderStateMixin {
  String? selectedReason;
  String? selectedTime;
  TimeOfDay? customStartTime;
  TimeOfDay? customEndTime;
  bool showCustomTimePicker = false;
  late AnimationController _chipAnimationController;

  final List<ReasonOption> reasonOptions = [
    ReasonOption(
      id: 'poor_lighting',
      label: 'Poor lighting',
      icon: Icons.light_mode,
    ),
    ReasonOption(id: 'harassment', label: 'Harassment', icon: Icons.security),
    ReasonOption(
      id: 'isolated_area',
      label: 'Isolated area',
      icon: Icons.location_on_outlined,
    ),
  ];

  final List<TimeOption> timeOptions = [
    TimeOption(id: 'night', label: 'Night', emoji: '🌙'),
    TimeOption(id: 'evening', label: 'Evening', emoji: '🌅'),
    TimeOption(id: 'morning', label: 'Morning', emoji: '🌅'),
  ];

  @override
  void initState() {
    super.initState();
    _chipAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _chipAnimationController.dispose();
    super.dispose();
  }

  void _selectReason(String reasonId) {
    setState(() {
      selectedReason = selectedReason == reasonId ? null : reasonId;
    });
    _chipAnimationController.forward(from: 0.0);
  }

  void _selectTime(String timeId) {
    setState(() {
      selectedTime = selectedTime == timeId ? null : timeId;
      if (timeId != 'custom') {
        showCustomTimePicker = false;
      }
    });
    _chipAnimationController.forward(from: 0.0);
  }

  Future<void> _showStartTimePicker() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: customStartTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        customStartTime = picked;
      });
    }
  }

  Future<void> _showEndTimePicker() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: customEndTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        customEndTime = picked;
      });
    }
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _handleConfirm() {
    final data = UnsafeAreaData(
      latitude: widget.latitude,
      longitude: widget.longitude,
      reason: selectedReason,
      timeType: selectedTime,
      timeStart: customStartTime != null ? _formatTime(customStartTime!) : null,
      timeEnd: customEndTime != null ? _formatTime(customEndTime!) : null,
    );
    widget.onConfirm(data);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: 24,
      ),
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(colorScheme),
                const SizedBox(height: 24),

                // Reason Section
                _buildSectionTitle('Select Reason (Optional)', colorScheme),
                const SizedBox(height: 12),
                _buildReasonChips(colorScheme),
                const SizedBox(height: 28),

                // Time Section
                _buildSectionTitle('Select Time Range (Optional)', colorScheme),
                const SizedBox(height: 12),
                _buildTimeRangePicker(colorScheme),

                const SizedBox(height: 32),

                // Bottom Buttons
                _buildBottomButtons(colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mark Unsafe Area',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Do you want to mark this area as unsafe?',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    );
  }

  Widget _buildReasonChips(ColorScheme colorScheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 12,
      children: reasonOptions.map((reason) {
        final isSelected = selectedReason == reason.id;
        return _buildChip(
          label: reason.label,
          isSelected: isSelected,
          onTap: () => _selectReason(reason.id),
          colorScheme: colorScheme,
          icon: reason.icon,
        );
      }).toList(),
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    IconData? icon,
  }) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.9, end: 1.0).animate(
        CurvedAnimation(
          parent: _chipAnimationController,
          curve: Curves.easeOut,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: Colors.red.withOpacity(0.1),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.red.shade50
                  : colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? Colors.red : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: icon != null ? 10 : 12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: isSelected
                        ? Colors.red
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isSelected
                        ? Colors.red
                        : colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeRangePicker(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTimePickerButton(
                  label: 'From',
                  time: customStartTime,
                  onTap: _showStartTimePicker,
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTimePickerButton(
                  label: 'To',
                  time: customEndTime,
                  onTap: _showEndTimePicker,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
          if (customStartTime != null && customEndTime != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatTime(customStartTime!)} - ${_formatTime(customEndTime!)}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimePickerButton({
    required String label,
    required TimeOfDay? time,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.3), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                time != null ? _formatTime(time) : '--:--',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: time != null
                      ? Colors.red
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButtons(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              widget.onCancel?.call();
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Cancel',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: colorScheme.onSurface),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _handleConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              shadowColor: Colors.red.withOpacity(0.4),
              elevation: 4,
            ),
            child: Text(
              'Confirm',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// Models
class ReasonOption {
  final String id;
  final String label;
  final IconData icon;

  ReasonOption({required this.id, required this.label, required this.icon});
}

class TimeOption {
  final String id;
  final String label;
  final String emoji;

  TimeOption({required this.id, required this.label, required this.emoji});
}

class UnsafeAreaData {
  final double latitude;
  final double longitude;
  final String? reason;
  final String? timeType;
  final String? timeStart;
  final String? timeEnd;

  UnsafeAreaData({
    required this.latitude,
    required this.longitude,
    this.reason,
    this.timeType,
    this.timeStart,
    this.timeEnd,
  });

  Map<String, dynamic> toJson() {
    return {
      'location': {'lat': latitude, 'lng': longitude},
      'reason': reason,
      'time_type': timeType,
      'time_start': timeStart,
      'time_end': timeEnd,
    };
  }
}
