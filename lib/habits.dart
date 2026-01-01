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
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

class SmartTip {
  final String id;
  final String title;
  final String content;
  final String? expandedContent;
  final String type;  
  final String targetTab;  

  const SmartTip({
    required this.id,
    required this.title,
    required this.content,
    this.expandedContent,
    required this.type,
    this.targetTab = 'any',
  });
}

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
  String _suggestionType = 'stalled';
  Set<String> _ignoredSuggestions = {};
  late TabController _tabController;

  SmartTip? _activeTip;
  bool _tipExpanded = false;

  final List<SmartTip> _allTips = [
    const SmartTip(
      id: 'dyk_changes_invisible',
      title: 'Did you know?',
      content:
          "Changes aren't visible each time you perform a habit. That's why habit tracking helps you feel like a change is happening! Each time that 'completed times' number increases, its a different kind of motivation boost!",
      type: 'did_you_know',
      targetTab: 'good',
    ),
    const SmartTip(
      id: 'pt_bad_habit_guilt',
      title: 'Pro tip',
      content:
          "Mark your bad habits as complete before performing them. This way, you'll feel the guilt of losing aura before doing it.",
      expandedContent:
          " And, you might end up in a scenario where you can't grab your phone and mark a bad habit as complete - so you might end up not doing it instead!",
      type: 'pro_tip',
      targetTab: 'bad',
    ),
    const SmartTip(
      id: 'dyk_21_days',
      title: 'Did you know?',
      content:
          "It takes about 21 days to form a new habit, but 90 days to make it a permanent lifestyle change. Keep going!",
      type: 'did_you_know',
      targetTab: 'good',
    ),
    const SmartTip(
      id: 'pt_stacking',
      title: 'Pro tip',
      content:
          "Try 'Habit Stacking'. Perform your new habit immediately after a current habit you already do every day.",
      type: 'pro_tip',
      targetTab: 'good',
    ),
    const SmartTip(
      id: 'pt_environment',
      title: 'Pro tip',
      content:
          "Design your environment for success. If you want to read more, put a book on your pillow.",
      type: 'pro_tip',
      targetTab: 'good',
    ),
    const SmartTip(
      id: 'pt_slow_growth',
      title: 'Pro tip',
      content:
          "Don't try to form too many habits at once. It can become too hard to manage. Success doesn't appear in a day or a week. Slowly work your way up over time.",
      type: 'pro_tip',
      targetTab: 'any',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabController,
      curve: Curves.easeOut,
    );

    _loadIgnoredSuggestions();

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
    _tabController.dispose();
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

  Future<void> _loadIgnoredSuggestions() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final ignored = keys
        .where((k) => k.startsWith('ignored_suggestion_'))
        .map((k) => k.replaceFirst('ignored_suggestion_', ''))
        .toSet();
    if (mounted) {
      setState(() {
        _ignoredSuggestions = ignored;
      });
      _checkForStalledHabits();
    }
  }

  Future<void> _ignoreSuggestion(String habitId, String type) async {
    final key = '${habitId}_$type';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ignored_suggestion_$key', true);

    if (mounted) {
      setState(() {
        _ignoredSuggestions.add(key);
        _stalledHabit = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Won't give this suggestion again",
            style: GoogleFonts.gabarito(
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.inverseSurface,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await prefs.remove('ignored_suggestion_$key');
              if (mounted) {
                setState(() {
                  _ignoredSuggestions.remove(key);
                });
                _checkForStalledHabits();
              }
            },
          ),
        ),
      );
    }
  }

  Future<void> _markTipAsSeen(String tipId) async {
    final key = 'tip_$tipId';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ignored_suggestion_$key', true);

    if (mounted) {
      setState(() {
        _ignoredSuggestions.add(key);
        _activeTip = null;
        _tipExpanded = false;
      });
    }
  }

  void _pickRandomTip() {
    if (_activeTip != null) return;

     
    if (Random().nextDouble() > 0.3) return;

    final availableTips =
        _allTips
            .where((t) => !_ignoredSuggestions.contains('tip_${t.id}'))
            .toList();

    if (availableTips.isNotEmpty) {
      setState(() {
        _activeTip = availableTips[Random().nextInt(availableTips.length)];
      });
    }
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

      final id = (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '').toString();
      if (_ignoredSuggestions.contains('${id}_stalled')) continue;

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
        setState(() {
          _stalledHabit = h;
          _suggestionType = 'stalled';
          _activeTip = null;  
        });
        return;
      }
    }

     
    for (final h in _habits) {
      if (h['type'] == 'bad') continue;

      final id = (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '').toString();
      if (_ignoredSuggestions.contains('${id}_remove_reminders')) continue;

      final completedTimes = h['completedTimes'] as int? ?? 0;
      final reminders = h['habitReminder'];
      final hasReminders = reminders is List && reminders.isNotEmpty;

      if (completedTimes >= 30 && hasReminders) {
        setState(() {
          _stalledHabit = h;
          _suggestionType = 'remove_reminders';
          _activeTip = null;  
        });
        return;
      }
    }

     
    if (_stalledHabit == null) {
      _pickRandomTip();
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
            final newAura = val.toInt();
            final oldAura = widget.currentAura ?? newAura;
            final diff = newAura - oldAura;
            if (diff != 0 && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    diff > 0
                        ? 'You gained $diff Aura!'
                        : 'You lost ${diff.abs()} Aura...',
                    style: GoogleFonts.gabarito(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                    ),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.inverseSurface,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            widget.onAuraChange!(newAura);
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
            final newAura = val.toInt();
            final oldAura = widget.currentAura ?? newAura;
            final diff = newAura - oldAura;
            if (diff != 0 && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    diff > 0
                        ? 'You gained $diff Aura!'
                        : 'You lost ${diff.abs()} Aura...',
                    style: GoogleFonts.gabarito(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                    ),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.inverseSurface,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            widget.onAuraChange!(newAura);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
      body: Column(
        children: [
          Container(
            color: scheme.surface,
            child: TabBar(
              controller: _tabController,
              labelStyle: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
              unselectedLabelStyle: GoogleFonts.gabarito(),
              tabs: const [
                Tab(text: 'Good Habits'),
                Tab(text: 'Bad Habits'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                       
                      goodHabits.isEmpty &&
                              _stalledHabit == null &&
                              (_activeTip == null ||
                                  _activeTip!.targetTab == 'bad')
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
                                    'No good habits yet',
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
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  12,
                                  0,
                                  120,
                                ),
                                children: [
                                  if (_activeTip != null &&
                                      (_activeTip!.targetTab == 'good' ||
                                          _activeTip!.targetTab == 'any')) ...[
                                    Container(
                                      margin: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        24,
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainer,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: scheme.outlineVariant
                                              .withOpacity(0.5),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                  _activeTip!.title,
                                                  style: GoogleFonts.gabarito(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: scheme.primary,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                ),
                                                onPressed: () => setState(
                                                  () => _activeTip = null,
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                style: IconButton.styleFrom(
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: _activeTip!.content,
                                                ),
                                                if (_tipExpanded &&
                                                    _activeTip!
                                                            .expandedContent !=
                                                        null)
                                                  TextSpan(
                                                    text: _activeTip!
                                                        .expandedContent,
                                                  ),
                                              ],
                                            ),
                                            style: GoogleFonts.gabarito(
                                              fontSize: 14,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              if (_activeTip!.expandedContent !=
                                                      null &&
                                                  !_tipExpanded)
                                                TextButton.icon(
                                                  onPressed: () => setState(
                                                    () => _tipExpanded = true,
                                                  ),
                                                  icon: const Icon(
                                                    Icons.keyboard_arrow_down_rounded,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    'View more',
                                                    style: GoogleFonts.gabarito(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              TextButton.icon(
                                                onPressed: () => _markTipAsSeen(
                                                  _activeTip!.id,
                                                ),
                                                icon: const Icon(
                                                  Icons.check,
                                                  size: 16,
                                                ),
                                                label: const Text("Got it"),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      scheme.outline,
                                                  textStyle:
                                                      GoogleFonts.gabarito(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (_stalledHabit != null) ...[
                                    Container(
                                      margin: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        24,
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainer,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: scheme.outlineVariant
                                              .withOpacity(0.5),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                ),
                                                onPressed: () => setState(
                                                  () => _stalledHabit = null,
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                style: IconButton.styleFrom(
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _suggestionType == 'stalled'
                                                ? 'Is "${_stalledHabit!['habitName'] ?? 'your habit'}" still working for you?'
                                                : 'Try removing some reminders',
                                            style: GoogleFonts.gabarito(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _suggestionType == 'stalled'
                                                ? "You haven't completed this habit in a while. Would you like to make changes?"
                                                : "You've completed this habit ${_stalledHabit!['completedTimes']} times. Why not try removing reminders to see if it sticks?",
                                            style: GoogleFonts.gabarito(
                                              fontSize: 14,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Transform.scale(
                                            scale: 1.10,
                                            child: _habitCard(
                                              _stalledHabit!,
                                              _habits.indexOf(_stalledHabit!),
                                              scheme,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton.icon(
                                              onPressed: () {
                                                final id =
                                                    (_stalledHabit![r'$id'] ??
                                                            _stalledHabit!['id'] ??
                                                            _stalledHabit!['habitId'] ??
                                                            '')
                                                        .toString();
                                                if (id.isNotEmpty) {
                                                  _ignoreSuggestion(
                                                    id,
                                                    _suggestionType,
                                                  );
                                                }
                                              },
                                              icon: const Icon(
                                                Icons.visibility_off_outlined,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                "Don't show again",
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: scheme.outline,
                                                textStyle: GoogleFonts.gabarito(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  ...goodHabits.map(
                                    (h) => _habitCard(
                                      h,
                                      _habits.indexOf(h),
                                      scheme,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                       
                      badHabits.isEmpty &&
                              (_activeTip == null ||
                                  _activeTip!.targetTab == 'good')
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  DynamicColorSvg(
                                    assetName: 'assets/img/bad_habit.svg',
                                    color: scheme.error,
                                    width: 240,
                                    height: 240,
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'No bad habits',
                                    style: GoogleFonts.gabarito(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.outline,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Great job! Or add one if you need to break it.',
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
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  12,
                                  0,
                                  120,
                                ),
                                children: [
                                  if (_activeTip != null &&
                                      (_activeTip!.targetTab == 'bad' ||
                                          _activeTip!.targetTab == 'any')) ...[
                                    Container(
                                      margin: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        24,
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainer,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: scheme.outlineVariant
                                              .withOpacity(0.5),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                  _activeTip!.title,
                                                  style: GoogleFonts.gabarito(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: scheme.primary,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                ),
                                                onPressed: () => setState(
                                                  () => _activeTip = null,
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                style: IconButton.styleFrom(
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: _activeTip!.content,
                                                ),
                                                if (_tipExpanded &&
                                                    _activeTip!
                                                            .expandedContent !=
                                                        null)
                                                  TextSpan(
                                                    text: _activeTip!
                                                        .expandedContent,
                                                  ),
                                              ],
                                            ),
                                            style: GoogleFonts.gabarito(
                                              fontSize: 14,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              if (_activeTip!.expandedContent !=
                                                      null &&
                                                  !_tipExpanded)
                                                TextButton.icon(
                                                  onPressed: () => setState(
                                                    () => _tipExpanded = true,
                                                  ),
                                                  icon: const Icon(
                                                    Icons.keyboard_arrow_down_rounded,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    'View more',
                                                    style: GoogleFonts.gabarito(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              TextButton.icon(
                                                onPressed: () => _markTipAsSeen(
                                                  _activeTip!.id,
                                                ),
                                                icon: const Icon(
                                                  Icons.check,
                                                  size: 16,
                                                ),
                                                label: const Text("Got it"),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      scheme.outline,
                                                  textStyle:
                                                      GoogleFonts.gabarito(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  ...badHabits.map(
                                    (h) => _habitCard(
                                      h,
                                      _habits.indexOf(h),
                                      scheme,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ],
                  ),
          ),
        ],
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
