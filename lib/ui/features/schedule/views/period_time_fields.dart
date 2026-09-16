import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

String periodClock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

int? parsePeriodClock(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match[1]!);
  final minute = int.parse(match[2]!);
  if (minute > 59 || hour > 24 || (hour == 24 && minute != 0)) return null;
  return hour * 60 + minute;
}

String periodSessionLabel(PeriodSession session) => switch (session) {
  PeriodSession.morning => '上午',
  PeriodSession.afternoon => '下午',
  PeriodSession.evening => '晚上',
};

class PeriodClockField extends StatelessWidget {
  const PeriodClockField({
    super.key,
    required this.controller,
    required this.label,
    this.allowDayEnd = false,
    this.required = true,
    this.onChanged,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool allowDayEnd;
  final bool required;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.datetime,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: label,
      hintText: 'HH:mm',
      isDense: true,
      errorMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: '选择$label',
        onPressed: () => _pickTime(context),
        icon: const Icon(Icons.schedule_outlined, size: 20),
      ),
    ),
    validator: (value) {
      if (!required && (value?.trim().isEmpty ?? true)) return null;
      final minutes = parsePeriodClock(value ?? '');
      if (minutes == null ||
          (!allowDayEnd && minutes == PeriodTime.minutesPerDay)) {
        return '请填写有效时间，如 08:30';
      }
      return validator?.call(value);
    },
    onChanged: onChanged,
  );

  Future<void> _pickTime(BuildContext context) async {
    final existing = parsePeriodClock(controller.text);
    final picked = await showTimePicker(
      context: context,
      initialTime: existing == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: (existing ~/ 60) % 24, minute: existing % 60),
      initialEntryMode: TimePickerEntryMode.input,
      emptyInitialInput: existing == null,
      helpText: allowDayEnd ? '$label（00:00 表示当天 24:00）' : label,
      cancelText: '取消',
      confirmText: '选定',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!context.mounted || picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    controller.text = periodClock(
      allowDayEnd && minutes == 0 ? PeriodTime.minutesPerDay : minutes,
    );
    onChanged?.call(controller.text);
  }
}
