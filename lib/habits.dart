import 'main.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'screens/habit_setup.dart';
import 'dart:async';
import 'widgets/dynamic_color_svg.dart' as dynamic_color_svg;

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

  void _showHabitDetails(Map<String, dynamic> habit) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final createdDate = _parseHabitDate(habit) ?? now;
    final completedDays = <DateTime>[];
    final rawCompleted = habit['completedDays'];
    if (rawCompleted is List) {
      for (final e in rawCompleted) {
        final s = e.toString();
        try {
          final dt = DateTime.parse(s.length == 10 ? s : s);
          if (dt.year > 1970) {
            completedDays.add(DateTime(dt.year, dt.month, dt.day));
          }
        } catch (_) {}
      }
    }
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _habitSentence(habit, cs),
                const SizedBox(height: 18),
                Text(
                  'History',
                  style: GoogleFonts.gabarito(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(daysInMonth, (i) {
                      final day = i + 1;
                      final completed = completedDays.any(
                        (d) =>
                            d.year == now.year &&
                            d.month == now.month &&
                            d.day == day,
                      );
                      return Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: completed
                              ? cs.primaryContainer
                              : cs.surfaceVariant.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$day',
                          style: GoogleFonts.gabarito(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: completed
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        title: 'Streak',
                        value: '7 days',
                        icon: Icons.local_fire_department_rounded,
                        cs: cs,
                        iconColor: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _metricBox(
                        title: 'Consistency',
                        value: '69%',
                        icon: Icons.insights_rounded,
                        cs: cs,
                        iconColor: cs.tertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _metricBox(
                  title: 'Reminder',
                  value: _formatReminder(habit),
                  icon: Icons.alarm_rounded,
                  cs: cs,
                  iconColor: cs.secondary,
                ),
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
                      child: FilledButton.tonal(
                        onPressed: () {},
                        style: FilledButton.styleFrom(
                          foregroundColor: cs.error,
                          backgroundColor: cs.errorContainer,
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {},
                        child: const Text('Edit'),
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
      habit['createdAt'],
      habit['created_at'],
      habit['timestamp'],
      habit['created'],
    ];
    for (final c in candidates) {
      if (c is DateTime) return c;
      if (c is String) {
        try {
          return DateTime.parse(c);
        } catch (_) {}
      }
    }
    return null;
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

  String _formatReminder(Map<String, dynamic> habit) {
    final rem = habit['habitReminder'];
    if (rem is List && rem.isNotEmpty) {
      return rem.take(3).join(', ') + (rem.length > 3 ? ' +' : '');
    }
    return 'None';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month) {
      return '${date.day} ${_monthName(date.month)}';
    }
    return '${date.day} ${_monthName(date.month)} ${date.year}';
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
