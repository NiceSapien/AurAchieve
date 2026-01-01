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
  final String? existingHabitId;
  final List<String>? initialReminders;

  const ReminderSetupScreen({
    super.key,
    required this.apiService,
    required this.habitName,
    required this.habitCue,
    required this.habitGoal,
    this.existingHabitId,
    this.initialReminders,
  });

  @override
  State<ReminderSetupScreen> createState() => _ReminderSetupScreenState();
}

class _ReminderSetupScreenState extends State<ReminderSetupScreen> {
  final List<TimeOfDay> _selectedTimes = [];
  final List<bool> _selectedDays = List.filled(7, false);
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _configureLocalTimeZone();
    _parseInitialReminders();
  }

  void _parseInitialReminders() {
    if (widget.initialReminders == null || widget.initialReminders!.isEmpty) {
      if (_selectedTimes.isEmpty) {
        _selectedTimes.add(const TimeOfDay(hour: 9, minute: 0));
      }
      return;
    }

    final daysMap = {
      'Mon': 0,
      'Tue': 1,
      'Wed': 2,
      'Thu': 3,
      'Fri': 4,
      'Sat': 5,
      'Sun': 6,
    };

    for (final r in widget.initialReminders!) {
      final lower = r.toLowerCase();
      if (lower.startsWith('daily')) {
        _selectedDays.fillRange(0, 7, true);
        final tStr = r.replaceFirst(RegExp('[Dd]aily ?'), '').trim();
        _addTimeFromString(tStr);
      } else {
        final parts = r.split(' ');
        if (parts.length >= 2) {
          final day = parts.first;
          final timeStr = parts.sublist(1).join(' ').trim();
          if (daysMap.containsKey(day)) {
            _selectedDays[daysMap[day]!] = true;
          }
          _addTimeFromString(timeStr);
        }
      }
    }
    if (_selectedTimes.isEmpty) {
      _selectedTimes.add(const TimeOfDay(hour: 9, minute: 0));
    }
  }

  void _addTimeFromString(String s) {
    try {
       
      final dt = _parseTime(s);
      if (dt != null) {
        final tod = TimeOfDay.fromDateTime(dt);
        if (!_selectedTimes.any(
          (t) => t.hour == tod.hour && t.minute == tod.minute,
        )) {
          _selectedTimes.add(tod);
        }
      }
    } catch (_) {}
  }

  DateTime? _parseTime(String s) {
    final now = DateTime.now();
     
     
    try {
      final parts = s.split(' ');
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      int minute = int.parse(timeParts[1]);
      if (parts.length > 1) {
        final period = parts[1].toUpperCase();
        if (period == 'PM' && hour < 12) hour += 12;
        if (period == 'AM' && hour == 12) hour = 0;
      }
      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  Future<void> _configureLocalTimeZone() async {
    tzdata.initializeTimeZones();
    try {
      final dynamic localTimezone = await FlutterTimezone.getLocalTimezone();
      String timeZoneName = localTimezone.toString();
      debugPrint('Raw timezone string: $timeZoneName');

       
      final RegExp regex = RegExp(r'([A-Za-z]+/[A-Za-z_]+)');
      final match = regex.firstMatch(timeZoneName);

      if (match != null) {
        timeZoneName = match.group(1)!;
      } else {
         
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
       
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));  
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

     
    final exactAlarmStatus = await androidImplementation
        ?.requestExactAlarmsPermission();
    debugPrint('Exact Alarm Permission Status: $exactAlarmStatus');

     
    if (exactAlarmStatus == false) {
       
       
    }

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
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    while (scheduledDate.weekday != day) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
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
          icon: '@mipmap/launcher_icon',
        );
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

     
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

     
     
     
     
     
     
     
     

    if (anyDaySelected && _selectedTimes.isNotEmpty) {
      int notificationIdOffset = 0;
      for (final time in _selectedTimes) {
        for (int i = 0; i < _selectedDays.length; i++) {
          if (_selectedDays[i]) {
            final day = i + 1;
            final scheduledDate = _nextInstanceOf(day, time);

             
            final notificationId = habitId.hashCode + notificationIdOffset;
            notificationIdOffset++;

            try {
              await flutterLocalNotificationsPlugin.zonedSchedule(
                notificationId,
                'Time to $habitName!',
                'Remember? You wanted to become ${widget.habitGoal}.',
                scheduledDate,
                notificationDetails,
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
              );
            } catch (e) {
              debugPrint('Error scheduling notification: $e');
            }
          }
        }
      }
    }
  }

  Future<void> _saveHabitAndReminder() async {
    setState(() => _isSaving = true);
    try {
      String habitId;
      if (widget.existingHabitId != null) {
        habitId = widget.existingHabitId!;
         
      } else {
        final created = await widget.apiService.createHabit(
          habitName: widget.habitName,
          habitGoal: widget.habitGoal,
          habitLocation: widget.habitCue,
          createdAt: DateTime.now(),
          completedDays: [],
        );
        habitId =
            created[r'$id'] ??
            created['id'] ??
            created['habitId'] ??
            DateTime.now().millisecondsSinceEpoch.toString();
      }

      final hasDay = _selectedDays.any((d) => d);
      if (habitId.isNotEmpty) {
        if (hasDay && _selectedTimes.isNotEmpty) {
          final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          final selected = <String>[];

          for (final time in _selectedTimes) {
            final timeStr = time.format(context);
            for (int i = 0; i < _selectedDays.length; i++) {
              if (_selectedDays[i]) selected.add('${days[i]} $timeStr');
            }
          }

          await widget.apiService.saveHabitReminderLocal(habitId, selected);
          await _scheduleNotification(habitId, widget.habitName);
        } else {
           
          await widget.apiService.saveHabitReminderLocal(habitId, []);
           
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved successfully')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
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
        _selectedTimes.isNotEmpty && _selectedDays.any((d) => d);
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
            Text('Times', style: TextStyle(color: onSurface)),
            const SizedBox(height: 10),
            ..._selectedTimes.asMap().entries.map((entry) {
              final index = entry.key;
              final time = entry.value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  time.format(context),
                  style: TextStyle(color: onSurface, fontSize: 18),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      setState(() => _selectedTimes.removeAt(index)),
                ),
                onTap: () async {
                  final newTime = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (newTime != null) {
                    setState(() => _selectedTimes[index] = newTime);
                  }
                },
              );
            }),
            OutlinedButton.icon(
              onPressed: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (time != null) {
                  setState(() => _selectedTimes.add(time));
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Time'),
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
                              _selectedTimes.clear();
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
