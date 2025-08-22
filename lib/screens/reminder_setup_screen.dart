import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

import '../api_service.dart';
import '../main.dart';

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
    if (_selectedTime == null) return;

    try {
      // TEMPORARILY DISABLED: Notifications causing black screen issues
      print("Notification scheduling skipped - notifications are disabled");
      return;
      
      /* DISABLED CODE:
      const androidDetails = AndroidNotificationDetails(
        'habit_reminders',
        'Habit Reminders',
        channelDescription: 'Notifications to remind you of your habits',
        importance: Importance.max,
        priority: Priority.high,
      );
      const iosDetails = DarwinNotificationDetails();
      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final bool anyDaySelected = _selectedDays.any((d) => d);

      if (anyDaySelected) {
        for (int i = 0; i < _selectedDays.length; i++) {
          if (_selectedDays[i]) {
            final day = i + 1;
            await flutterLocalNotificationsPlugin.zonedSchedule(
              widget.habitName.hashCode + day,
              'Time for your habit!',
              'I will ${widget.habitName}, ${widget.habitCue}',
              _nextInstanceOf(day, _selectedTime!),
              notificationDetails,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            );
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
        await flutterLocalNotificationsPlugin.zonedSchedule(
          widget.habitName.hashCode,
          'Time for your habit!',
          'I will ${widget.habitName}, ${widget.habitCue}',
          scheduledDate,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      */
    } catch (e) {
      print("Error scheduling notification: $e");
      // Continue without notification
    }
  }

  Future<void> _saveHabitAndReminder() async {
    setState(() => _isSaving = true);
    try {
      final created = await widget.apiService.createHabit(
        habitName: widget.habitName,
        habitGoal: widget.habitGoal,
        habitLocation: widget.habitCue,
      );

      String habitId = created[r'$id'] ?? created['id'] ?? created['habitId'] ?? '';
      if (_selectedTime != null && habitId.isNotEmpty) {
        final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final timeStr = _selectedTime!.format(context);
        final selected = <String>[];
        if (_selectedDays.any((d) => d)) {
          for (int i = 0; i < _selectedDays.length; i++) {
            if (_selectedDays[i]) selected.add('${days[i]} $timeStr');
          }
        } else {
          selected.add('Daily $timeStr');
        }
        await widget.apiService.saveHabitReminderLocal(habitId, selected);
        await _scheduleNotification();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Habit saved successfully!')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving habit: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: const Text('Set a Reminder')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
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
                final time = await showTimePicker(
                  context: context,
                  initialTime: _selectedTime ?? TimeOfDay.now(),
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
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _saveHabitAndReminder,
                child: Text(_isSaving ? 'Saving...' : 'Save Habit & Reminder'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _isSaving
                    ? null
                    : () {
                        _selectedTime = null;
                        _saveHabitAndReminder();
                      },
                child: const Text('Save without reminder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
