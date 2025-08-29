import 'main.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'screens/habit_setup.dart';
import 'dart:async';
import 'package:vector_math/vector_math_64.dart' as vector;
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
          final h = _habits[idx];
          final id = (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '').toString();
          if (id.isNotEmpty) _incrementCompleted(id, idx);
          _resetHold();
        }
      });
    _bounceController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _completedIndex = null);
          }
        });
    _bounceScale = _bounceController.drive(
      TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(
            begin: 0.0,
            end: -0.06,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 10,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -0.06,
            end: 0.18,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 22,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 0.18,
            end: -0.03,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 14,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -0.03,
            end: 0.08,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 12,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 0.08,
            end: -0.015,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 10,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -0.015,
            end: 0.0,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 8,
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
    setState(() => _holdingIndex = index);
    c.forward(from: 0);
  }

  Future<void> _loadHabits() async {
    setState(() => _loading = true);
    try {
      final list = await widget.apiService.getHabits();
      final normalized = <Map<String, dynamic>>[];
      for (final h in list) {
        if (h is! Map) continue;
        final m = Map<String, dynamic>.from(h);
        final id = m[r'$id'] ?? m['id'] ?? m['habitId'];
        final localRem = id != null
            ? await widget.apiService.getHabitReminderLocal(id.toString())
            : null;
        if (localRem != null && localRem.isNotEmpty) {
          m['habitReminder'] = localRem;
        }
        m['completedTimes'] = m['completedTimes'] ?? 0;
        normalized.add(m);
      }
      if (mounted) setState(() => _habits = normalized);
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

  Future<void> _incrementCompleted(String habitId, int index) async {
    if (_updating) return;
    _updating = true;
    final previousCount = _habits[index]['completedTimes'] as int? ?? 0;
    setState(() {
      _habits[index]['completedTimes'] = previousCount + 1;
      _completedIndex = index;
    });
    _bounceController.forward(from: 0);
    try {
      await widget.apiService.incrementHabitCompletedTimes(habitId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 1200),
          content: Text('Habit marked as complete'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _habits[index]['completedTimes'] = previousCount;
        _completedIndex = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
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
        if (_completedIndex != null && index == _completedIndex) {
          scale = 1.0 + _bounceScale.value;
        }
        if (holding) scale *= (1 - (progress * 0.04));
        return Transform.scale(scale: scale, child: child);
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (id.isEmpty) return;
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
            if (_holdingIndex != null) {
              _resetHold();
            } else {
              _pressDelayTimer?.cancel();
            }
          }
        },
        onPointerUp: (_) => _resetHold(),
        onPointerCancel: (_) => _resetHold(),
        child: Material(
          clipBehavior: Clip.antiAlias,
          color: colorPair.bg,
          elevation: 3,
          shadowColor: scheme.shadow.withOpacity(0.25),
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
                        'to become a',
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
                      if (reminderTime != null) ...[
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
                        const SizedBox(height: 4),
                      ],
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
