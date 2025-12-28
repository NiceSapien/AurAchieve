import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import '../api_service.dart';
import '../screens/habit_setup.dart';
import '../screens/bad_habit_setup.dart';

class HabitDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> habit;
  final ApiService apiService;
  final String userName;
  final Function(String) onDelete;
  final Function(Map<String, dynamic>) onUpdate;

  const HabitDetailsSheet({
    super.key,
    required this.habit,
    required this.apiService,
    required this.userName,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  State<HabitDetailsSheet> createState() => _HabitDetailsSheetState();
}

class _HabitDetailsSheetState extends State<HabitDetailsSheet> {
  late DateTime _calMonth;
  bool _showConsistencyPercent = false;

  @override
  void initState() {
    super.initState();
    _calMonth = DateTime(DateTime.now().year, DateTime.now().month);
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

  Widget _habitSentence(Map<String, dynamic> habit, ColorScheme cs) {
    final isBad = habit['type'] == 'bad';
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
      decorationColor: isBad ? cs.error : cs.primary,
      decorationStyle: TextDecorationStyle.wavy,
      decorationThickness: 1,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
    );

    if (isBad) {
      return RichText(
        text: TextSpan(
          style: base,
          children: [
            const TextSpan(text: 'If I '),
            TextSpan(text: habitName, style: emph),
            const TextSpan(text: ', then '),
            TextSpan(text: goal, style: emph),
          ],
        ),
      );
    }

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
    final isConsistency = title == 'Consistency';
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
                    : (isConsistency
                          ? GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showConsistencyPercent =
                                      !_showConsistencyPercent;
                                });
                              },
                              child: Text(
                                _showConsistencyPercent
                                    ? '${_computeConsistency(widget.habit['completedDays'] is List ? (widget.habit['completedDays'] as List).length : 0, _parseHabitDate(widget.habit) ?? DateTime.now()).toStringAsFixed(1)}%'
                                    : (value ?? ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.gabarito(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                            )
                          : Text(
                              value ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.gabarito(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            )),
              ],
            ),
          ),
        ],
      ),
    );
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
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.secondary.withOpacity(0.22),
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

  String _getConsistencyLabel(double pct) {
    if (pct >= 100) return 'Perfect';
    if (pct >= 80) return 'Excellent';
    if (pct >= 60) return 'Good';
    if (pct >= 40) return 'Okay';
    if (pct >= 20) return 'Bad';
    return 'Terrible';
  }

  void _onEdit() async {
    final isBad =
        widget.habit['type'] == 'bad' || widget.habit.containsKey('badHabit');
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => isBad
            ? BadHabitSetup(
                apiService: widget.apiService,
                initialHabit: widget.habit,
              )
            : HabitSetup(
                apiService: widget.apiService,
                userName: widget.userName,
                initialHabit: widget.habit,
              ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      widget.onUpdate(result);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isBad = widget.habit['type'] == 'bad';
    final createdDate = _parseHabitDate(widget.habit) ?? now;
    final completedDays = <DateTime>[];
    final raw = widget.habit['completedDays'];
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
    final consistencyLabel = _getConsistencyLabel(consistencyPct);
    final totalCompletions = widget.habit['completedTimes'] as int? ?? 0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.40,
      maxChildSize: 0.94,
      builder: (sheetContext, scrollController) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _habitSentence(widget.habit, cs),
              const SizedBox(height: 18),
              _HabitCalendar(
                month: _calMonth,
                completed: completedSet,
                created: createdDate,
                onChange: (m) => setState(() => _calMonth = m),
                cs: cs,
              ),
              const SizedBox(height: 20),
              if (isBad) ...[
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
                        title: 'Completed',
                        value: '$totalCompletions times',
                        icon: Icons.done_all,
                        cs: cs,
                        iconColor: cs.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _metricBox(
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
              ] else ...[
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
                        title: 'Completed',
                        value: '$totalCompletions times',
                        icon: Icons.done_all,
                        cs: cs,
                        iconColor: cs.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _metricBox(
                  title: 'Consistency',
                  value: consistencyLabel,
                  icon: Icons.insights_rounded,
                  cs: cs,
                  iconColor: cs.tertiary,
                ),
                const SizedBox(height: 12),
                _metricBox(
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
              ],
              if (!isBad) ...[
                const SizedBox(height: 12),
                _reminderBox(widget.habit, cs),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final id =
                            (widget.habit[r'$id'] ??
                                    widget.habit['id'] ??
                                    widget.habit['habitId'] ??
                                    '')
                                .toString();
                        if (id.isEmpty) return;
                        final confirm = await showDialog<bool>(
                          context: context,
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
                        Navigator.of(context).pop();
                        widget.onDelete(id);
                      },
                      icon: Icon(Icons.delete_outline_rounded, color: cs.error),
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
                      onPressed: _onEdit,
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
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  _scrollController.jumpTo(0);
                  _animationController.reset();
                  _animationController.forward();
                }
              });
            } else if (status == AnimationStatus.dismissed) {
              _animationController.forward();
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
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                if (!_needsScroll) return child!;
                final maxScroll = _scrollController.position.maxScrollExtent;
                _scrollController.jumpTo(
                  _animationController.value * maxScroll,
                );
                return child!;
              },
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Text(widget.text, style: widget.style),
              ),
            ),
          ),
        );
      },
    );
  }
}
