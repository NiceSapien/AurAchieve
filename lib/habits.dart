import 'main.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'screens/habit_setup.dart';
import 'dart:async';
import 'widgets/dynamic_color_svg.dart' as dynamic_color_svg;
import 'dart:convert';

class HabitsPage extends StatefulWidget {
  final ApiService apiService;
  const HabitsPage({super.key, required this.apiService});
  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> with TickerProviderStateMixin {
  bool _loading = true;
  bool _updating = false;
  List<Map<String, dynamic>> _habits = [];
  AnimationController? _holdController;
  static const Duration _holdDuration = Duration(milliseconds: 700);
  int? _holdingIndex;
  Timer? _pressDelayTimer;
  Offset? _pressStartPosition;
  static const double _moveTolerance = 8.0;
  late AnimationController _bounceController;
  late Animation<double> _bounceScale;
  int? _completedIndex;
  bool _holdTriggered = false;
  bool _pointerMoved = false; // add this

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(vsync: this, duration: _holdDuration)
      ..addListener(() {
        if (mounted && _holdingIndex != null) setState(() {});
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && _holdingIndex != null) {
          final idx = _holdingIndex!;
          _holdTriggered = true;
          final h = _habits[idx];
          final id = (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '').toString();
          if (id.isNotEmpty) _incrementCompleted(id, idx);
          _resetHold();
        }
      });
    _bounceController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 850),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed && mounted)
            setState(() => _completedIndex = null);
        });
    _bounceScale = _bounceController.drive(
      TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(
            begin: 0.0,
            end: 0.28,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 20,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 0.28,
            end: -0.12,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 14,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -0.12,
            end: 0.1,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 12,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 0.1,
            end: -0.04,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 10,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -0.04,
            end: 0.02,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 8,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 0.02,
            end: 0.0,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 6,
        ),
      ]),
    );
    _loadHabits();
  }

  @override
  void dispose() {
    _pressDelayTimer?.cancel();
    _holdController?.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _resetHold() {
    _pressDelayTimer?.cancel();
    final c = _holdController;
    if (c != null) {
      c.stop();
      c.reset();
    }
    if (mounted) setState(() => _holdingIndex = null);
  }

  void _startHoldAnimation(int index) {
    final c = _holdController;
    if (c == null) return;
    _holdTriggered = false;
    _pointerMoved = false;
    setState(() => _holdingIndex = index);
    c.forward(from: 0);
  }

  Future<void> _loadHabits() async {
    setState(() => _loading = true);
    try {
      final list = await widget.apiService.getHabits();
      final normalized = <Map<String, dynamic>>[];
      // In _loadHabits(), ensure completedDays stays a List<String>
      for (final h in list) {
        if (h is! Map) continue;
        final m = Map<String, dynamic>.from(h);
        final id = m[r'$id'] ?? m['id'] ?? m['habitId'];
        final localRem = id != null
            ? await widget.apiService.getHabitReminderLocal(id.toString())
            : null;
        if (localRem != null && localRem.isNotEmpty)
          m['habitReminder'] = localRem;
        m['completedTimes'] = m['completedTimes'] ?? 0;
        if (m['completedDays'] is List) {
          m['completedDays'] = List<String>.from(
            (m['completedDays'] as List).map((e) => e.toString()),
          );
        } else if (m['completedDays'] is String) {
          final s = (m['completedDays'] as String).trim();
          if (s.isEmpty) {
            m['completedDays'] = <String>[];
          } else {
            m['completedDays'] = s
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
        } else {
          m['completedDays'] = <String>[];
        }
        normalized.add(m);
      }
      if (mounted) setState(() => _habits = normalized);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load habits: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ShapeBorder _shapeForIndex(int i) {
    switch (i % 6) {
      case 0:
        return RoundedRectangleBorder(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(50),
            bottomLeft: Radius.circular(50),
            bottomRight: Radius.circular(16),
          ),
        );
      case 1:
        return RoundedRectangleBorder(borderRadius: BorderRadius.circular(40));
      case 2:
        return const ContinuousRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(60)),
        );
      case 3:
        return BeveledRectangleBorder(borderRadius: BorderRadius.circular(24));
      case 4:
        return RoundedRectangleBorder(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(50),
            bottomRight: Radius.circular(50),
          ),
        );
      default:
        return RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));
    }
  }

  ({Color bg, Color fg}) _colorsForIndex(int i, ColorScheme s) {
    Color elevate(Color surface, Color accent) {
      final base = (surface.alpha == 0 || surface.opacity < 0.05)
          ? s.surface
          : surface;
      return Color.alphaBlend(accent.withOpacity(0.12), base);
    }

    switch (i % 5) {
      case 0:
        return (
          bg: elevate(s.secondaryContainer, s.secondary),
          fg: s.onSecondaryContainer,
        );
      case 1:
        return (
          bg: elevate(s.primaryContainer, s.primary),
          fg: s.onPrimaryContainer,
        );
      case 2:
        return (
          bg: elevate(s.tertiaryContainer, s.tertiary),
          fg: s.onTertiaryContainer,
        );
      case 3:
        return (
          bg: elevate(s.surfaceContainerHighest, s.primary),
          fg: s.onSurfaceVariant,
        );
      default:
        return (
          bg: elevate(s.surfaceContainerHigh, s.secondary),
          fg: s.onSurface,
        );
    }
  }

  // Replace _incrementCompleted with:
  Future<void> _incrementCompleted(String habitId, int index) async {
    if (_updating) return;
    _updating = true;
    final habit = _habits[index];
    final prevCount = habit['completedTimes'] as int? ?? 0;
    final prevDays = List<String>.from(
      (habit['completedDays'] as List?)?.map((e) => e.toString()) ??
          const <String>[],
    );
    final todayKey = DateTime.now().toUtc();
    final todayStr =
        '${todayKey.year.toString().padLeft(4, '0')}-${todayKey.month.toString().padLeft(2, '0')}-${todayKey.day.toString().padLeft(2, '0')}';

    final updatedDays = List<String>.from(prevDays);
    if (!updatedDays.contains(todayStr)) {
      updatedDays.add(todayStr);
    } else {
      // Already completed today: do nothing and exit
      _updating = false;
      return;
    }

    setState(() {
      habit['completedTimes'] = prevCount + 1;
      habit['completedDays'] = updatedDays;
      _completedIndex = index;
    });
    _bounceController.forward(from: 0);

    try {
      final serverDays = await widget.apiService.incrementHabitCompletedTimes(
        habitId,
        completedDays: updatedDays,
      );
      if (mounted) {
        setState(() {
          habit['completedDays'] = serverDays;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          habit['completedTimes'] = prevCount;
          habit['completedDays'] = prevDays;
          _completedIndex = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    } finally {
      _updating = false;
    }
  }

  bool _hasReminderToday(List<String> reminders) {
    if (reminders.isEmpty) return false;
    final now = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = days[now.weekday - 1];
    return reminders.any(
      (r) => r.startsWith(today) || r.toLowerCase().startsWith('daily'),
    );
  }

  String? _todayReminderTime(List<String> reminders) {
    if (reminders.isEmpty) return null;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final today = days[now.weekday - 1];
    for (final r in reminders) {
      if (r.startsWith(today)) return r.replaceFirst('$today ', '');
      if (r.toLowerCase().startsWith('daily')) {
        return r.replaceFirst(RegExp('[Dd]aily ?'), '');
      }
    }
    return null;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int _computeStreak(Set<DateTime> completedSet) {
    if (completedSet.isEmpty) return 0;
    final today = _dateOnly(DateTime.now());
    if (!completedSet.contains(today)) return 0;
    int streak = 0;
    var cursor = today;
    while (completedSet.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  double _computeConsistency(int completedCount, DateTime createdAt) {
    final start = _dateOnly(createdAt);
    final today = _dateOnly(DateTime.now());
    if (today.isBefore(start)) return 0;
    final totalDays = today.difference(start).inDays + 1;
    if (totalDays <= 0) return 0;
    return (completedCount / totalDays) * 100;
  }

  void _showHabitDetails(Map<String, dynamic> habit) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final createdDate = _parseHabitDate(habit) ?? now;
    final completedDays = <DateTime>[];
    final raw = habit['completedDays'];
    Iterable<String> dayStrings = const [];
    if (raw is List) {
      dayStrings = raw.map((e) => e.toString());
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          dayStrings = parsed.map((e) => e.toString());
        } else {
          dayStrings = raw.split(',');
        }
      } catch (_) {
        dayStrings = raw.split(',');
      }
    }
    for (final s in dayStrings) {
      final t = s.trim();
      if (t.isEmpty) continue;
      try {
        final dt = DateTime.parse(t);
        completedDays.add(_dateOnly(dt));
      } catch (_) {}
    }
    final completedSet = completedDays.toSet();
    final streak = _computeStreak(completedSet);
    final streakStr = streak == 1 ? '1 day' : '$streak days';
    final consistencyPct = _computeConsistency(
      completedSet.length,
      createdDate,
    );
    final consistencyStr =
        '${consistencyPct.toStringAsFixed(consistencyPct >= 10 ? 0 : 1)}%';
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        DateTime calMonth = DateTime(now.year, now.month);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _habitSentence(habit, cs),
                const SizedBox(height: 18),
                StatefulBuilder(
                  builder: (calCtx, setCalState) {
                    return _HabitCalendar(
                      month: calMonth,
                      completed: completedSet,
                      created: createdDate,
                      onChange: (m) => setCalState(() {
                        calMonth = DateTime(m.year, m.month);
                      }),
                      cs: cs,
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        title: 'Streak',
                        value: streakStr,
                        icon: Icons.local_fire_department_rounded,
                        cs: cs,
                        iconColor: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _metricBox(
                        title: 'Consistency',
                        value: consistencyStr,
                        icon: Icons.insights_rounded,
                        cs: cs,
                        iconColor: cs.tertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _reminderBox(habit, cs),
                const SizedBox(height: 12),
                _metricBox(
                  title: 'Added',
                  value: _formatDate(createdDate),
                  icon: Icons.event_available_rounded,
                  cs: cs,
                  iconColor: cs.primary,
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final id =
                              (habit[r'$id'] ?? habit['id'] ?? habit['habitId'] ?? '')
                                  .toString();
                          if (id.isEmpty) return;
                          final confirm = await showDialog<bool>(
                            context: ctx,
                            barrierDismissible: true,
                            builder: (dCtx) {
                              final cs2 = Theme.of(dCtx).colorScheme;
                              return AlertDialog(
                                backgroundColor: cs2.surfaceContainerHigh,
                                surfaceTintColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                title: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      color: cs2.error,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Delete habit?',
                                        style: GoogleFonts.gabarito(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: cs2.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                content: Text(
                                  'This will remove the habit and its progress. This action cannot be undone.',
                                  style: GoogleFonts.gabarito(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                    color: cs2.onSurfaceVariant,
                                  ),
                                ),
                                actionsPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                actions: [
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: cs2.onSurfaceVariant,
                                      textStyle: GoogleFonts.gabarito(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(dCtx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: cs2.errorContainer,
                                      foregroundColor: cs2.error,
                                      textStyle: GoogleFonts.gabarito(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(dCtx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (confirm != true) return;
                          Navigator.of(ctx).pop();
                          try {
                            await widget.apiService.deleteHabit(id);
                            if (mounted) {
                              setState(() {
                                _habits.removeWhere(
                                  (h) =>
                                      (h[r'$id'] ??
                                              h['id'] ??
                                              h['habitId'] ??
                                              '')
                                          .toString() ==
                                      id,
                                );
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Habit deleted')),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Delete failed: $e')),
                              );
                            }
                          }
                        },
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: cs.error,
                        ),
                        label: Text(
                          'Delete',
                          style: GoogleFonts.gabarito(
                            fontWeight: FontWeight.w600,
                            color: cs.error,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(
                            color: cs.error.withOpacity(0.55),
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: cs.error.withOpacity(0.05),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Edit'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  DateTime? _parseHabitDate(Map<String, dynamic> habit) {
    final candidates = [
      habit[r'$createdAt'], // Appwrite document field
      habit['createdAt'],
      habit['created_at'],
      habit['timestamp'],
      habit['created'],
      habit[r'$updatedAt'], // fallback if created missing
    ];
    for (final c in candidates) {
      if (c == null) continue;
      if (c is DateTime) return c;
      if (c is String && c.isNotEmpty) {
        try {
          return DateTime.parse(c);
        } catch (_) {}
      }
    }
    return null;
  }

  (String time, List<String> days) _parseReminderParts(
    Map<String, dynamic> habit,
  ) {
    final rem = habit['habitReminder'];
    if (rem is! List || rem.isEmpty) return ('—', const []);
    final List<String> items = rem.map((e) => e.toString()).toList();
    final daySet = <String>{};
    String? time;
    for (final r in items) {
      final lower = r.toLowerCase();
      if (lower.startsWith('daily')) {
        daySet.addAll(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
        final t = r.replaceFirst(RegExp('[Dd]aily ?'), '').trim();
        if (t.isNotEmpty) time ??= t;
        continue;
      }
      final parts = r.split(' ');
      if (parts.length >= 2) {
        final day = parts.first;
        final rest = parts.sublist(1).join(' ').trim();
        if (day.length == 3) daySet.add(day);
        if (time == null && rest.isNotEmpty) time = rest;
      }
    }
    final orderedDays = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ].where(daySet.contains).toList();
    return (time ?? '—', orderedDays);
  }

  Widget _reminderBox(Map<String, dynamic> habit, ColorScheme cs) {
    final (time, days) = _parseReminderParts(habit);
    if (days.isEmpty && time == '—') {
      return _metricBox(
        title: 'Reminder',
        value: 'None',
        icon: Icons.alarm_rounded,
        cs: cs,
        iconColor: cs.secondary,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.secondary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.alarm_rounded, size: 22, color: cs.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reminder',
                  style: GoogleFonts.gabarito(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: GoogleFonts.gabarito(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: days.map((d) {
                    final active = true;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (active ? cs.secondary : cs.surfaceVariant)
                            .withOpacity(active ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cs.secondary.withOpacity(0.30),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        d,
                        style: GoogleFonts.gabarito(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: cs.onSurface,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _habitSentence(Map<String, dynamic> habit, ColorScheme cs) {
    final habitName = (habit['habitName'] ?? habit['habit'] ?? 'habit')
        .toString();
    final cue =
        (habit['habitLocation'] ??
                habit['habitCue'] ??
                habit['location'] ??
                'time/place')
            .toString();
    final goal = (habit['habitGoal'] ?? habit['goal'] ?? 'better person')
        .toString();
    TextStyle base = GoogleFonts.gabarito(
      fontSize: 22,
      fontWeight: FontWeight.w500,
      color: cs.onSurface,
    );
    TextStyle emph = base.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: cs.primary,
      decorationStyle: TextDecorationStyle.wavy,
      decorationThickness: 2,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
    );
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'I will '),
          TextSpan(text: habitName, style: emph),
          const TextSpan(text: ', '),
          TextSpan(text: cue, style: emph),
          const TextSpan(text: ' so that I can become '),
          TextSpan(text: goal, style: emph),
        ],
      ),
    );
  }

  Widget _metricBox({
    required String title,
    required String value,
    required IconData icon,
    required ColorScheme cs,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.gabarito(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.gabarito(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const full = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${date.day} ${full[date.month - 1]}, ${date.year}';
  }

  String _monthName(int month) {
    const names = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month];
  }

  Widget _habitCard(Map<String, dynamic> h, int index, ColorScheme scheme) {
    final c = _holdController;
    final holding = _holdingIndex == index && c != null;
    final progress = holding ? c.value : 0.0;
    final id = (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '').toString();
    final name = (h['habitName'] ?? h['habit'] ?? '').toString();
    final goal = (h['habitGoal'] ?? h['goal'] ?? '').toString();
    final reminders = (h['habitReminder'] is List)
        ? List<String>.from(
            (h['habitReminder'] as List).map((e) => e.toString()),
          )
        : const <String>[];
    final colorPair = _colorsForIndex(index, scheme);
    final shape = _shapeForIndex(index);
    final showReminder = _hasReminderToday(reminders);
    final reminderTime = showReminder ? _todayReminderTime(reminders) : null;
    return AnimatedBuilder(
      animation: _bounceController,
      builder: (context, child) {
        double scale = 1.0;
        if (_completedIndex != null && index == _completedIndex)
          scale = 1.0 + _bounceScale.value;
        if (holding) scale *= (1 - (progress * 0.04));
        return Transform.scale(scale: scale, child: child);
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (id.isEmpty) return;
          _pointerMoved = false;
          _pressStartPosition = event.position;
          _pressDelayTimer?.cancel();
          _pressDelayTimer = Timer(const Duration(milliseconds: 50), () {
            if (_pressStartPosition != null && _holdingIndex == null) {
              _startHoldAnimation(index);
            }
          });
        },
        onPointerMove: (event) {
          if (_pressStartPosition == null) return;
          final moved = (event.position - _pressStartPosition!).distance;
          if (moved > _moveTolerance) {
            _pointerMoved = true;
            if (_holdingIndex != null) {
              _resetHold();
            } else {
              _pressDelayTimer?.cancel();
            }
          }
        },
        onPointerUp: (_) {
          final wasHold = _holdTriggered;
          final moved = _pointerMoved;
          _resetHold();
          if (!wasHold && !moved) _showHabitDetails(h);
        },
        onPointerCancel: (_) {
          _resetHold();
        },
        child: Material(
          clipBehavior: Clip.antiAlias,
          color: colorPair.bg,
          elevation: 3,
          shape: shape,
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: progress,
                    widthFactor: 1,
                    child: Container(color: colorPair.fg.withOpacity(0.10)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'I will',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.gabarito(
                          fontSize: 12,
                          color: colorPair.fg.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.gabarito(
                          fontSize: 20,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: colorPair.fg,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'to become',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.gabarito(
                          fontSize: 12,
                          color: colorPair.fg.withOpacity(0.72),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colorPair.fg.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          goal,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.gabarito(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colorPair.fg,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (reminderTime != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorPair.fg.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            reminderTime,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.gabarito(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorPair.fg,
                            ),
                          ),
                        ),
                      if (reminderTime != null) const SizedBox(height: 4),
                      Text(
                        'Completed: ${h['completedTimes']}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.gabarito(
                          fontSize: 10,
                          color: colorPair.fg.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _habits.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  dynamic_color_svg.DynamicColorSvg(
                    assetName: 'assets/img/habit.svg',
                    color: scheme.primary,
                    width: 240,
                    height: 240,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No habits yet',
                    style: GoogleFonts.gabarito(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: scheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a habit from the button below.',
                    style: GoogleFonts.gabarito(
                      fontSize: 14,
                      color: scheme.outline.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadHabits,
              child: GridView.builder(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.7,
                ),
                itemCount: _habits.length,
                itemBuilder: (context, index) =>
                    _habitCard(_habits[index], index, scheme),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_habit_fab',
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  HabitSetup(userName: 'You', apiService: widget.apiService),
            ),
          );
          if (result == true && mounted) await _loadHabits();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Habit'),
      ),
    );
  }
}

class _HabitCalendar extends StatelessWidget {
  final DateTime month;
  final Set<DateTime> completed;
  final DateTime created;
  final void Function(DateTime) onChange;
  final ColorScheme cs;
  const _HabitCalendar({required this.month, required this.completed, required this.created, required this.onChange, required this.cs});
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startLimit = DateTime(created.year, created.month);
    final endLimit = DateTime(now.year, now.month);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final leading = (firstWeekday + 6) % 7;
    final cells = <Widget>[];
    for (int i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final done = completed.any((c) => _sameDay(c, date));
      final today = _sameDay(date, now);
      Color bg;
      Color fg;
      if (today) {
        bg = cs.primary;
        fg = cs.onPrimary;
      } else if (done) {
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
      } else {
        bg = cs.surfaceVariant.withOpacity(0.35);
        fg = cs.onSurfaceVariant;
      }
      cells.add(Container(
        margin: const EdgeInsets.all(2),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$d',
          style: GoogleFonts.gabarito(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ));
    }
    final rows = (cells.length / 7).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: month.isAfter(startLimit) ? () => onChange(DateTime(month.year, month.month - 1)) : null,
              icon: const Icon(Icons.chevron_left_rounded),
              color: month.isAfter(startLimit) ? cs.onSurfaceVariant : cs.onSurfaceVariant.withOpacity(0.25),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${_monthNameFull(month.month)} ${month.year}',
                  style: GoogleFonts.gabarito(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
              ),
            ),
            IconButton(
              onPressed: month.isBefore(endLimit) ? () => onChange(DateTime(month.year, month.month + 1)) : null,
              icon: const Icon(Icons.chevron_right_rounded),
              color: month.isBefore(endLimit) ? cs.onSurfaceVariant : cs.onSurfaceVariant.withOpacity(0.25),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].map((d) => Expanded(
            child: Center(
              child: Text(
                d,
                style: GoogleFonts.gabarito(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
              ),
            ),
          )).toList(),
        ),
        const SizedBox(height: 4),
        Column(
          children: List.generate(rows, (r) {
            return Row(
              children: List.generate(7, (c) {
                final idx = r * 7 + c;
                if (idx < cells.length) {
                  return Expanded(child: SizedBox(height: 44, child: Center(child: cells[idx])));
                }
                return const Expanded(child: SizedBox(height: 44));
              }),
            );
          }),
        ),
      ],
    );
  }
  String _monthNameFull(int m) {
    const full = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return full[m - 1];
  }
}
