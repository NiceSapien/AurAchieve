import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'screens/habit_setup.dart';
import 'dart:async';
import 'widgets/dynamic_color_svg.dart' as dynamic_color_svg;
import 'dart:convert';
import 'package:flutter/services.dart';

class HabitsPage extends StatefulWidget {
  final ApiService apiService;
  final List<dynamic>? initialHabits;
  const HabitsPage({super.key, required this.apiService, this.initialHabits});
  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> with TickerProviderStateMixin {
  bool _loading = true;
  bool _updating = false;
  List<Map<String, dynamic>> _habits = [];
  late AnimationController _bounceController;
  late Animation<double> _bounceScale;
  int? _completedIndex;
  AnimationController? _holdController;
  int? _holdingIndex;
  bool _secondTickDone = false;
  static const int _secondTickLeadMs = 180;

  @override
  void initState() {
    super.initState();
    _bounceController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 850),
          )
          ..addStatusListener((s) async {
            if (s == AnimationStatus.completed && mounted) {
              setState(() => _completedIndex = null);
            }
          })
          ..addListener(() {
            if (_secondTickDone) return;
            final total = _bounceController.duration?.inMilliseconds ?? 0;
            final elapsed =
                _bounceController.lastElapsedDuration?.inMilliseconds ?? 0;
            if (total > 0 && elapsed >= (total - _secondTickLeadMs)) {
              try {
                HapticFeedback.selectionClick();
              } catch (_) {}
              _secondTickDone = true;
            }
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
    _holdController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            if (_holdingIndex != null) {
              final habit = _habits[_holdingIndex!];
              final id =
                  (habit[r'$id'] ?? habit['id'] ?? habit['habitId'] ?? '')
                      .toString();
              if (id.isNotEmpty) {
                _incrementCompleted(id, _holdingIndex!);
              }
            }
            _resetHold();
          }
        });

    final preload = widget.initialHabits;
    if (preload != null && preload.isNotEmpty) {
      _habits = _normalizeHabits(preload);
      _loading = false;
      setState(() {});
    } else {
      _loadHabits();
    }
  }

  List<Map<String, dynamic>> _normalizeHabits(List rawList) {
    final normalized = <Map<String, dynamic>>[];
    for (final h in rawList) {
      if (h is! Map) continue;
      final m = Map<String, dynamic>.from(h);
      final id = m[r'$id'] ?? m['id'] ?? m['habitId'];
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
          try {
            final parsed = jsonDecode(s);
            if (parsed is List) {
              m['completedDays'] = List<String>.from(
                parsed.map((e) => e.toString()),
              );
            } else {
              m['completedDays'] = s
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
            }
          } catch (_) {
            m['completedDays'] = s
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
        }
      } else {
        m['completedDays'] = <String>[];
      }
      normalized.add(m);
    }
    return normalized;
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _holdController?.dispose();
    super.dispose();
  }

  void _startHold(int index) {
    setState(() => _holdingIndex = index);
    _holdController?.forward(from: 0);
  }

  void _resetHold() {
    final c = _holdController;
    if (c != null) {
      c.stop();
      c.reset();
    }
    if (mounted) setState(() => _holdingIndex = null);
  }

  Future<void> _loadHabits() async {
    setState(() => _loading = true);
    try {
      final list = await widget.apiService.getHabits();
      if (mounted) setState(() => _habits = _normalizeHabits(list));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load habits: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ShapeBorder _shapeForIndex(int i) {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0));
  }

  ({Color bg, Color fg}) _colorsForIndex(int i, ColorScheme s) {
    return (bg: s.surfaceContainer, fg: s.onSurface);
  }

  Future<void> _completionHaptics() async {
    try {
      HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 40));
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  Future<void> _incrementCompleted(String habitId, int index) async {
    if (_updating) return;
    setState(() => _updating = true);
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
    }

    setState(() {
      habit['completedTimes'] = prevCount + 1;
      habit['completedDays'] = updatedDays;
      _completedIndex = index;
    });

    unawaited(_completionHaptics());

    _secondTickDone = false;
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
      if (mounted) setState(() => _updating = false);
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
    final yesterday = today.subtract(const Duration(days: 1));

    if (!completedSet.contains(today) && !completedSet.contains(yesterday)) {
      return 0;
    }
    int streak = 0;
    var cursor = completedSet.contains(today) ? today : yesterday;
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
    final totalCompletions = habit['completedTimes'] as int? ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        DateTime calMonth = DateTime(now.year, now.month);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.58,
          minChildSize: 0.40,
          maxChildSize: 0.94,
          builder: (context, scrollController) => SafeArea(
            top: false,
            child: SingleChildScrollView(
              controller: scrollController,
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
                  Row(
                    children: [
                      Expanded(
                        child: _metricBox(
                          title: 'Completed',
                          value: '$totalCompletions times',
                          icon: Icons.done_all,
                          cs: cs,
                          iconColor: cs.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricBox(
                          title: 'Added',
                          valueWidget: _MarqueeText(
                            text: _formatDate(createdDate),
                            style: GoogleFonts.gabarito(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          icon: Icons.event_available_rounded,
                          cs: cs,
                          iconColor: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _reminderBox(habit, cs),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final id =
                                (habit[r'$id'] ??
                                        habit['id'] ??
                                        habit['habitId'] ??
                                        '')
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
                                      onPressed: () =>
                                          Navigator.pop(dCtx, false),
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
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      onPressed: () =>
                                          Navigator.pop(dCtx, true),
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
                                  const SnackBar(
                                    content: Text('Habit deleted'),
                                  ),
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
          ),
        );
      },
    );
  }

  DateTime? _parseHabitDate(Map<String, dynamic> habit) {
    final candidates = [
      habit[r'$createdAt'],
      habit['createdAt'],
      habit['created_at'],
      habit['timestamp'],
      habit['created'],
      habit[r'$updatedAt'],
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
                        color:
                            (active ? cs.secondary : cs.surfaceContainerHighest)
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
    String? value,
    Widget? valueWidget,
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
                valueWidget != null
                    ? SizedBox(width: double.infinity, child: valueWidget)
                    : Text(
                        value ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
    final id = (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '').toString();
    final name = (h['habitName'] ?? h['habit'] ?? '').toString();
    final goal = (h['habitGoal'] ?? h['goal'] ?? '').toString();
    final totalCompletions = h['completedTimes'] as int? ?? 0;

    final todayKey = DateTime.now().toUtc();
    final todayStr =
        '${todayKey.year.toString().padLeft(4, '0')}-${todayKey.month.toString().padLeft(2, '0')}-${todayKey.day.toString().padLeft(2, '0')}';

    List<String> completedDaysRaw = [];
    if (h['completedDays'] is List) {
      completedDaysRaw = List<String>.from(h['completedDays']);
    }
    final completedToday = completedDaysRaw.contains(todayStr);

    final completedDates = completedDaysRaw
        .map((s) {
          try {
            return DateTime.parse(s);
          } catch (_) {
            return null;
          }
        })
        .whereType<DateTime>()
        .map(_dateOnly)
        .toSet();
    final streak = _computeStreak(completedDates);

    final colorPair = _colorsForIndex(index, scheme);
    final shape = _shapeForIndex(index);
    final BorderRadius radius =
        (shape is RoundedRectangleBorder && shape.borderRadius is BorderRadius)
        ? (shape.borderRadius as BorderRadius)
        : BorderRadius.circular(16);

    return AnimatedBuilder(
      animation: _bounceController,
      builder: (context, child) {
        double scale = 1.0;
        if (_completedIndex == index) {
          scale = 1.0 + _bounceScale.value;
        }
        return Transform.scale(scale: scale, child: child);
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        clipBehavior: Clip.antiAlias,
        color: colorPair.bg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant.withOpacity(0.5)),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showHabitDetails(h),
          onLongPressStart: (_) {
            if (_updating || id.isEmpty) return;

            if (index < 0 || index >= _habits.length) return;

            _startHold(index);
          },
          onLongPressEnd: (_) => _resetHold(),
          onLongPressCancel: _resetHold,
          child: Stack(
            children: [
              if (_holdController != null)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _holdController!,
                    builder: (context, _) {
                      final isActive = _holdingIndex == index;
                      final v = isActive ? _holdController!.value : 0.0;
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          widthFactor: 1.0,
                          heightFactor: v.clamp(0.0, 1.0),
                          child: ClipRRect(
                            borderRadius: radius,
                            child: Container(
                              color: scheme.primary.withOpacity(0.22),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'I will',
                            style: GoogleFonts.gabarito(
                              fontSize: 13,
                              color: colorPair.fg.withOpacity(0.8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            name,
                            style: GoogleFonts.gabarito(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: colorPair.fg,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (goal.isNotEmpty) const SizedBox(height: 6),
                          if (goal.isNotEmpty)
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.gabarito(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'to become ',
                                    style: TextStyle(
                                      color: colorPair.fg.withOpacity(0.8),
                                    ),
                                  ),
                                  TextSpan(
                                    text: goal,
                                    style: TextStyle(
                                      color: colorPair.fg,
                                      decoration: TextDecoration.underline,
                                      decorationColor: scheme.primary
                                          .withOpacity(0.8),
                                      decorationStyle: TextDecorationStyle.wavy,
                                      decorationThickness: 1.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Row(
                      children: [
                        _StatBadge(
                          value: streak,
                          icon: Icons.local_fire_department_outlined,
                          color: scheme.primary,
                          textColor: colorPair.fg,
                        ),
                        const SizedBox(width: 12),
                        _StatBadge(
                          value: totalCompletions,
                          icon: Icons.done_all_outlined,
                          color: scheme.tertiary,
                          textColor: colorPair.fg,
                        ),
                      ],
                    ),
                  ],
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
              child: ListView.builder(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 120),
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

class _StatBadge extends StatelessWidget {
  final int value;
  final IconData icon;
  final Color color;
  final Color textColor;

  const _StatBadge({
    required this.value,
    required this.icon,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, size: 22, color: iconColor),
        ),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: GoogleFonts.gabarito(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor.withOpacity(0.9),
          ),
        ),
      ],
    );
  }
}

class _HabitCalendar extends StatelessWidget {
  final DateTime month;
  final Set<DateTime> completed;
  final DateTime created;
  final void Function(DateTime) onChange;
  final ColorScheme cs;
  const _HabitCalendar({
    required this.month,
    required this.completed,
    required this.created,
    required this.onChange,
    required this.cs,
  });
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
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
        bg = cs.surfaceContainerHighest.withOpacity(0.35);
        fg = cs.onSurfaceVariant;
      }
      cells.add(
        Container(
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
        ),
      );
    }
    final rows = (cells.length / 7).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: month.isAfter(startLimit)
                  ? () => onChange(DateTime(month.year, month.month - 1))
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
              color: month.isAfter(startLimit)
                  ? cs.onSurfaceVariant
                  : cs.onSurfaceVariant.withOpacity(0.25),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${_monthNameFull(month.month)} ${month.year}',
                  style: GoogleFonts.gabarito(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: month.isBefore(endLimit)
                  ? () => onChange(DateTime(month.year, month.month + 1))
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
              color: month.isBefore(endLimit)
                  ? cs.onSurfaceVariant
                  : cs.onSurfaceVariant.withOpacity(0.25),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: GoogleFonts.gabarito(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        Column(
          children: List.generate(rows, (r) {
            return Row(
              children: List.generate(7, (c) {
                final idx = r * 7 + c;
                if (idx < cells.length) {
                  return Expanded(
                    child: SizedBox(
                      height: 44,
                      child: Center(child: cells[idx]),
                    ),
                  );
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
    return full[m - 1];
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _animationController;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animationController =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _animationController.reverse();
              });
            } else if (status == AnimationStatus.dismissed) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _animationController.forward();
              });
            }
          });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfScrollIsNeeded();
      if (_needsScroll) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _animationController.forward();
        });
      }
    });
  }

  void _checkIfScrollIsNeeded() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 0) {
      setState(() => _needsScroll = true);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return ClipRect(
          child: SizedBox(
            width: constraints.maxWidth,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                if (_scrollController.hasClients && _needsScroll) {
                  final pos =
                      _animationController.value *
                      _scrollController.position.maxScrollExtent;
                  _scrollController.jumpTo(pos);
                }
                return child!;
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _scrollController,
                physics: const NeverScrollableScrollPhysics(),
                child: Text(
                  widget.text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: widget.style,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
