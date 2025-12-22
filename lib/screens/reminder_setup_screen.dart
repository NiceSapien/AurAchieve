import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

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
    _configureLocalTimeZone();
  }

  Future<void> _configureLocalTimeZone() async {
    tzdata.initializeTimeZones();
    try {
      final dynamic localTimezone = await FlutterTimezone.getLocalTimezone();
      String timeZoneName = localTimezone.toString();
      debugPrint('Raw timezone string: $timeZoneName');

      // Try to find a valid timezone ID using regex (e.g., "Asia/Kolkata", "America/New_York")
      final RegExp regex = RegExp(r'([A-Za-z]+/[A-Za-z_]+)');
      final match = regex.firstMatch(timeZoneName);

      if (match != null) {
        timeZoneName = match.group(1)!;
      } else {
        // Fallback for simple IDs or if regex fails but string is valid
        if (timeZoneName.startsWith('TimezoneInfo(')) {
          final split = timeZoneName.split(',');
          if (split.isNotEmpty) {
            timeZoneName = split[0].substring('TimezoneInfo('.length);
          }
        }
      }

      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint('Timezone set to: $timeZoneName');
    } catch (e) {
      debugPrint('Could not get local timezone: $e');
      // Fallback to a known timezone if detection fails, or UTC
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); // Try a default
        debugPrint('Fallback to Asia/Kolkata');
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('UTC'));
        debugPrint('Fallback to UTC');
      }
    }
  }

  Future<bool> _requestPermissions() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    final bool? androidResult = await androidImplementation
        ?.requestNotificationsPermission();

    // Check exact alarm permission status
    final exactAlarmStatus = await androidImplementation
        ?.requestExactAlarmsPermission();
    debugPrint('Exact Alarm Permission Status: $exactAlarmStatus');

    final iosImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    final bool? iosResult = await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    return (androidResult ?? false) || (iosResult ?? false);
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

  Future<void> _scheduleNotification(String habitId, String habitName) async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    final bool anyDaySelected = _selectedDays.any((d) => d);

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
          'habit_reminders',
          'Habit Reminders',
          channelDescription: 'Reminders for your habits',
          importance: Importance.max,
          priority: Priority.high,
        );
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

    // Explicitly create the channel
    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        'habit_reminders',
        'Habit Reminders',
        description: 'Reminders for your habits',
        importance: Importance.max,
      ),
    );

    if (anyDaySelected) {
      for (int i = 0; i < _selectedDays.length; i++) {
        if (_selectedDays[i]) {
          final day = i + 1;
          final scheduledDate = _nextInstanceOf(day, _selectedTime!);
          debugPrint('Current Timezone: ${tz.local.name}');
          debugPrint('Now (Local): ${tz.TZDateTime.now(tz.local)}');
          debugPrint(
            'Scheduling notification for $habitName on day $day at $scheduledDate',
          );

          if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
            debugPrint('WARNING: Scheduled date is in the past!');
          }

          try {
            await flutterLocalNotificationsPlugin.zonedSchedule(
              habitId.hashCode + i,
              'Time to $habitName',
              'Don\'t break the chain!',
              scheduledDate,
              notificationDetails,
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            );
            debugPrint(
              'Notification scheduled successfully for ID: ${habitId.hashCode + i}',
            );

            // Immediate test notification to verify system is working
            await flutterLocalNotificationsPlugin.show(
              99999,
              'Test Notification',
              'If you see this, notifications work!',
              notificationDetails,
            );
          } catch (e) {
            debugPrint('Error scheduling notification: $e');
          }
        }
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
        await _scheduleNotification(habitId, widget.habitName);
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
