import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'screens/habit_setup.dart';
import 'screens/bad_habit_setup.dart';
import 'dart:async';
import 'widgets/habit_details_sheet.dart';
import 'widgets/dynamic_color_svg.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class HabitsPage extends StatefulWidget {
  final ApiService apiService;
  final String userName;
  final List<dynamic>? initialHabits;
  final int? currentAura;
  final Function(int)? onAuraChange;
  final bool smartSuggestionsEnabled;

  const HabitsPage({
    super.key,
    required this.apiService,
    required this.userName,
    this.initialHabits,
    this.currentAura,
    this.onAuraChange,
    this.smartSuggestionsEnabled = true,
  });
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
  bool _fabExpanded = false;
  late AnimationController _fabController;
  late Animation<double> _fabAnimation;
  Map<String, dynamic>? _stalledHabit;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabController,
      curve: Curves.easeOut,
    );

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
      _checkForStalledHabits();
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
      // Ensure type is set if missing (default to good for legacy)
      m['type'] ??= 'good';

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
  void didUpdateWidget(HabitsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialHabits != oldWidget.initialHabits) {
      final preload = widget.initialHabits;
      if (preload != null) {
        setState(() {
          _habits = _normalizeHabits(preload);
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _fabController.dispose();
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

  List<String> _normalizeCompletedDays(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return <String>[];
      try {
        final decoded = jsonDecode(s);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {}
      return s
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  void _checkForStalledHabits() {
    if (!widget.smartSuggestionsEnabled) {
      if (_stalledHabit != null) {
        setState(() => _stalledHabit = null);
      }
      return;
    }
    if (_habits.isEmpty) return;

    final now = DateTime.now();
    final threeDaysAgo = now.subtract(const Duration(days: 3));

    for (final h in _habits) {
      if (h['type'] == 'bad') continue;

      final completedDays = _normalizeCompletedDays(h['completedDays']);
      DateTime? lastDate;

      if (completedDays.isEmpty) {
        final createdAtStr = h[r'$createdAt'] ?? h['createdAt'];
        if (createdAtStr != null) {
          final created = DateTime.tryParse(createdAtStr.toString());
          if (created != null) lastDate = created;
        }
      } else {
        for (final d in completedDays) {
          try {
            final date = DateTime.parse(d);
            if (lastDate == null || date.isAfter(lastDate)) {
              lastDate = date;
            }
          } catch (_) {}
        }
      }

      if (lastDate != null && lastDate.isBefore(threeDaysAgo)) {
        setState(() => _stalledHabit = h);
        return;
      }
    }
  }

  Future<void> _loadHabits() async {
    setState(() => _loading = true);
    try {
      List<dynamic> goodList = [];
      List<dynamic> badList = [];

      try {
        final dashboard = await widget.apiService.getTasksAndHabits();
        goodList = (dashboard['habits'] as List?) ?? [];
        badList = (dashboard['badHabits'] as List?) ?? [];

        // If dashboard returned empty lists, try individual endpoints as fallback
        if (goodList.isEmpty) {
          try {
            goodList = await widget.apiService.getHabits();
          } catch (_) {}
        }
        if (badList.isEmpty) {
          try {
            badList = await widget.apiService.getBadHabits();
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('Failed to fetch from dashboard, falling back: $e');
        goodList = await widget.apiService.getHabits();
        try {
          badList = await widget.apiService.getBadHabits();
        } catch (e) {
          debugPrint('Failed to fetch bad habits: $e');
        }
      }

      final combined = <Map<String, dynamic>>[];

      for (final h in goodList) {
        if (h is Map) {
          final m = Map<String, dynamic>.from(h);
          m['type'] = 'good';
          final id = (m[r'$id'] ?? m['id'] ?? m['habitId'] ?? '').toString();
          if (id.isNotEmpty) {
            final localReminders = await widget.apiService
                .getHabitReminderLocal(id);
            if (localReminders != null) {
              m['habitReminder'] = localReminders;
            }
          }
          combined.add(m);
        }
      }

      for (final h in badList) {
        if (h is Map) {
          final m = Map<String, dynamic>.from(h);
          m['type'] = 'bad';
          combined.add(m);
        }
      }

      if (mounted) {
        setState(() {
          _habits = _normalizeHabits(combined);
          _checkForStalledHabits();
        });
      }
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
    final isBad = habit['type'] == 'bad';
    final prevCount = habit['completedTimes'] as int? ?? 0;

    var cDays = habit['completedDays'];
    if (cDays is String) {
      try {
        final parsed = jsonDecode(cDays);
        if (parsed is List) cDays = parsed;
      } catch (_) {}
    }

    final prevDays = List<String>.from(
      (cDays as List?)?.map((e) => e.toString()) ?? const <String>[],
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
      if (isBad) {
        final resp = await widget.apiService.incrementBadHabit(
          habitId,
          completedDays: updatedDays,
        );

        if (resp.containsKey('aura') && widget.onAuraChange != null) {
          final val = resp['aura'];
          if (val is num) {
            widget.onAuraChange!(val.toInt());
          }
        }
      } else {
        final resp = await widget.apiService.incrementHabitCompletedTimes(
          habitId,
          completedDays: updatedDays,
        );

        if (mounted) {
          setState(() {
            if (resp['completedDays'] is List) {
              habit['completedDays'] = resp['completedDays'];
            } else if (resp['completedDays'] is String) {
              try {
                habit['completedDays'] = jsonDecode(resp['completedDays']);
              } catch (_) {}
            }
          });
        }

        if (resp.containsKey('aura') && widget.onAuraChange != null) {
          final val = resp['aura'];
          if (val is num) {
            widget.onAuraChange!(val.toInt());
          }
        }
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

  void _showHabitDetails(Map<String, dynamic> habit) {
    final isBad = habit['type'] == 'bad';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return HabitDetailsSheet(
          habit: habit,
          apiService: widget.apiService,
          userName: widget.userName,
          onDelete: (id) async {
            try {
              if (isBad) {
                await widget.apiService.deleteBadHabit(id);
              } else {
                await widget.apiService.deleteHabit(id);
              }
              if (mounted) {
                setState(() {
                  _habits.removeWhere(
                    (h) =>
                        (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '')
                            .toString() ==
                        id,
                  );
                });
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Habit deleted')));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
              }
            }
          },
          onUpdate: (updatedHabit) {
            if (mounted) {
              setState(() {
                final id =
                    (updatedHabit[r'$id'] ??
                            updatedHabit['id'] ??
                            updatedHabit['habitId'] ??
                            '')
                        .toString();
                final index = _habits.indexWhere(
                  (h) =>
                      (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '').toString() ==
                      id,
                );
                if (index != -1) {
                  final existing = _habits[index];
                  final merged = Map<String, dynamic>.from(existing);
                  merged.addAll(updatedHabit);

                  // Ensure type is preserved if missing in update
                  if (!updatedHabit.containsKey('type')) {
                    merged['type'] = existing['type'];
                  }

                  final normalized = _normalizeHabits([merged]);
                  if (normalized.isNotEmpty) {
                    _habits[index] = normalized.first;
                  }
                }
              });
            }
          },
        );
      },
    );
  }

  Widget _habitCard(Map<String, dynamic> h, int index, ColorScheme scheme) {
    final id = (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '').toString();
    final name = (h['habitName'] ?? h['habit'] ?? '').toString();
    final isBad = h['type'] == 'bad';
    final badGoal = (h['habitGoal'] ?? '').toString();
    final goal = isBad
        ? (badGoal.isNotEmpty
              ? badGoal
              : (h['severity'] ?? 'Bad Habit').toString())
        : (h['habitGoal'] ?? h['goal'] ?? '').toString();

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
    final totalCompletions = h['completedTimes'] as int? ?? 0;

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
                            isBad ? 'If I' : 'I will',
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
                                    text: isBad ? 'then ' : 'to become ',
                                    style: TextStyle(
                                      color: colorPair.fg.withOpacity(0.8),
                                    ),
                                  ),
                                  TextSpan(
                                    text: goal,
                                    style: TextStyle(
                                      color: colorPair.fg,
                                      decoration: TextDecoration.underline,
                                      decorationColor: isBad
                                          ? scheme.error
                                          : scheme.primary.withOpacity(0.8),
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
                        if (!isBad)
                          Tooltip(
                            triggerMode: TooltipTriggerMode.tap,
                            message: streak > 0
                                ? (completedToday
                                      ? 'Streak active! Completed today.'
                                      : 'Streak active! Complete today to keep it.')
                                : 'No active streak.',
                            child: _StatBadge(
                              value: streak,
                              icon: streak > 0
                                  ? Icons.local_fire_department_rounded
                                  : Icons.local_fire_department_outlined,
                              backgroundColor: streak > 0
                                  ? (completedToday
                                        ? scheme.primary
                                        : Colors.transparent)
                                  : scheme.surfaceContainerHighest.withOpacity(
                                      0.4,
                                    ),
                              iconColor: streak > 0
                                  ? (completedToday
                                        ? scheme.onPrimary
                                        : scheme.primary)
                                  : scheme.onSurfaceVariant.withOpacity(0.6),
                              borderColor: (streak > 0 && !completedToday)
                                  ? scheme.primary
                                  : null,
                              textColor: colorPair.fg,
                            ),
                          ),
                        if (isBad)
                          _StatBadge(
                            value: totalCompletions,
                            icon: Icons.warning_amber_rounded,
                            backgroundColor: Colors.transparent,
                            iconColor: colorPair.fg,
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

  void _toggleFab() {
    setState(() {
      _fabExpanded = !_fabExpanded;
      if (_fabExpanded) {
        _fabController.forward();
      } else {
        _fabController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final goodHabits = _habits.where((h) => h['type'] != 'bad').toList();
    final badHabits = _habits.where((h) => h['type'] == 'bad').toList();

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _habits.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DynamicColorSvg(
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
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 120),
                children: [
                  if (_stalledHabit != null) ...[
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: scheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline_rounded,
                                color: scheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Smart Suggestion',
                                  style: GoogleFonts.gabarito(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () =>
                                    setState(() => _stalledHabit = null),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Is "${_stalledHabit!['habitName'] ?? 'your habit'}" still working for you?',
                            style: GoogleFonts.gabarito(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "You haven't completed this habit in a while. Would you like to make changes?",
                            style: GoogleFonts.gabarito(
                              fontSize: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    final h = _stalledHabit!;
                                    setState(() => _stalledHabit = null);
                                    _showHabitDetails(h);
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 0,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('Edit Habit'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () =>
                                      setState(() => _stalledHabit = null),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 0,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('Keep Going'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (goodHabits.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Good Habits",
                            style: GoogleFonts.gabarito(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                            ),
                          ),
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: scheme.primary,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                    ...goodHabits.map(
                      (h) => _habitCard(h, _habits.indexOf(h), scheme),
                    ),
                  ],
                  if (badHabits.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Bad Habits",
                            style: GoogleFonts.gabarito(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                            ),
                          ),
                          Icon(
                            Icons.warning_amber_rounded,
                            color: scheme.error,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                    ...badHabits.map(
                      (h) => _habitCard(h, _habits.indexOf(h), scheme),
                    ),
                  ],
                ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ScaleTransition(
            scale: _fabAnimation,
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FloatingActionButton.extended(
                heroTag: 'add_bad_habit',
                onPressed: () async {
                  _toggleFab();
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          BadHabitSetup(apiService: widget.apiService),
                    ),
                  );
                  if (result == true && mounted) await _loadHabits();
                },
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('Bad Habit'),
              ),
            ),
          ),
          ScaleTransition(
            scale: _fabAnimation,
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FloatingActionButton.extended(
                heroTag: 'add_good_habit',
                onPressed: () async {
                  _toggleFab();
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HabitSetup(
                        userName: 'You',
                        apiService: widget.apiService,
                      ),
                    ),
                  );
                  if (result == true && mounted) await _loadHabits();
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Good Habit'),
              ),
            ),
          ),
          FloatingActionButton(
            heroTag: 'add_habit_fab',
            onPressed: _toggleFab,
            child: AnimatedRotation(
              turns: _fabExpanded ? 0.125 : 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: const Icon(Icons.add, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final int value;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final Color? borderColor;
  final Color textColor;

  const _StatBadge({
    required this.value,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.borderColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 2)
                : null,
          ),
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
