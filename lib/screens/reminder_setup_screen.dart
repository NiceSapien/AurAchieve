import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

import '../api_service.dart';

class ReminderSetupScreen extends StatefulWidget {
  final ApiService apiService;
  final String habitName;
  final String habitCue;
  final String habitGoal;

  const ReminderSetupScreen({
    super.key,
    required this.apiService,
    required this.habitName,
    required this.habitCue,
    required this.habitGoal,
  });

  @override
  State<ReminderSetupScreen> createState() => _ReminderSetupScreenState();
}

class _ReminderSetupScreenState extends State<ReminderSetupScreen> {
  TimeOfDay? _selectedTime;
  final List<bool> _selectedDays = List.filled(7, false);
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
  }

  Future<bool> _requestPermissions() async {
    return true;
  }

  tz.TZDateTime _nextInstanceOf(int day, TimeOfDay time) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    while (scheduledDate.weekday != day) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }
    return scheduledDate;
  }

  Future<void> _scheduleNotification() async {
    final bool anyDaySelected = _selectedDays.any((d) => d);

    if (anyDaySelected) {
      for (int i = 0; i < _selectedDays.length; i++) {
        if (_selectedDays[i]) {
          final day = i + 1;
        }
      }
    } else {
      final now = tz.TZDateTime.now(tz.local);
      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }
    }
  }

  Future<void> _saveHabitAndReminder() async {
    setState(() => _isSaving = true);
    try {
      final created = await widget.apiService.createHabit(
        habitName: widget.habitName,
        habitGoal: widget.habitGoal,
        habitLocation: widget.habitCue,
        createdAt: DateTime.now(),
        completedDays: [],
      );
      final habitId =
          created[r'$id'] ?? created['id'] ?? created['habitId'] ?? '';
      final hasTime = _selectedTime != null;
      final hasDay = _selectedDays.any((d) => d);
      if (habitId.isNotEmpty && hasTime && hasDay) {
        final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final timeStr = _selectedTime!.format(context);
        final selected = <String>[];
        for (int i = 0; i < _selectedDays.length; i++) {
          if (_selectedDays[i]) selected.add('${days[i]} $timeStr');
        }
        await widget.apiService.saveHabitReminderLocal(habitId, selected);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Habit saved successfully')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving habit: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final canSaveReminder =
        _selectedTime != null && _selectedDays.any((d) => d);
    return Scaffold(
      appBar: AppBar(title: const Text('Set a Reminder')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'When would you like to be reminded about this habit?',
              style: GoogleFonts.gabarito(
                fontSize: 20,
                color: onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              title: Text('Time', style: TextStyle(color: onSurface)),
              subtitle: Text(
                _selectedTime?.format(context) ?? 'Not set',
                style: TextStyle(color: onSurface.withOpacity(0.8)),
              ),
              trailing: Icon(Icons.arrow_forward_ios, color: onSurface),
              onTap: () async {
                final hasPermissions = await _requestPermissions();
                if (!hasPermissions && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Notification permissions are required to set reminders.',
                      ),
                    ),
                  );
                  return;
                }
                final time = await showTimePicker(
                  context: context,
                  initialTime: _selectedTime ?? TimeOfDay.now(),
                  builder: (context, child) {
                    final theme = Theme.of(context);
                    final cs = theme.colorScheme;
                    return Theme(
                      data: theme.copyWith(
                        colorScheme: cs.copyWith(
                          primary: cs.primary,
                          onPrimary: cs.onPrimary,
                          surface: cs.surface,
                          onSurface: cs.onSurface,
                        ),
                        textButtonTheme: TextButtonThemeData(
                          style: TextButton.styleFrom(
                            foregroundColor: cs.primary,
                          ),
                        ),
                        timePickerTheme: TimePickerThemeData(
                          helpTextStyle: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          hourMinuteTextColor: cs.onSurface,
                          dayPeriodTextColor: cs.onSurface,
                          dialHandColor: cs.primary,
                          dialBackgroundColor: cs.surfaceContainerHigh,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (time != null) {
                  setState(() => _selectedTime = time);
                }
              },
            ),
            const SizedBox(height: 20),
            Text('Repeat on', style: TextStyle(color: onSurface)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(days.length, (i) {
                final selected = _selectedDays[i];
                return ChoiceChip(
                  label: Text(days[i]),
                  selected: selected,
                  onSelected: (v) => setState(() => _selectedDays[i] = v),
                );
              }),
            ),
            const Spacer(),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(top: 8, bottom: 12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSaving || !canSaveReminder
                          ? null
                          : _saveHabitAndReminder,
                      child: Text(
                        _isSaving ? 'Saving...' : 'Save Habit & Reminder',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _isSaving
                          ? null
                          : () {
                              _selectedTime = null;
                              for (int i = 0; i < _selectedDays.length; i++) {
                                _selectedDays[i] = false;
                              }
                              _saveHabitAndReminder();
                            },
                      child: const Text('Save without reminder'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
