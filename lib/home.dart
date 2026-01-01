import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

import 'social_blocker.dart';
import 'api_service.dart';
import 'widgets/dynamic_color_svg.dart';
import 'main.dart' show AuthCheck;
import 'timer_page.dart';
import 'study_planner.dart';
import 'screens/extended_task_list.dart';
import 'habits.dart';
import 'widgets/habit_details_sheet.dart';
import 'shop.dart';
import 'settings.dart';
import 'profile.dart';

enum AuraHistoryView { day, month, year }

class HomePage extends StatefulWidget {
  final Account account;
  const HomePage({super.key, required this.account});

  @override
  _HomePageState createState() => _HomePageState();
}

class Task {
  final String id;
  final String name;
  final String intensity;
  final String type;
  final String taskCategory;
  final int? durationMinutes;
  final bool isImageVerifiable;
  final String status;
  final String userId;
  final String createdAt;
  final String? completedAt;

  Task({
    required this.id,
    required this.name,
    required this.intensity,
    required this.type,
    required this.taskCategory,
    this.durationMinutes,
    required this.isImageVerifiable,
    required this.status,
    required this.userId,
    required this.createdAt,
    this.completedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json[r'$id'] ?? '',
      name: json['name'] ?? 'Unnamed Task',
      intensity: json['intensity'] ?? 'easy',
      type: json['type'] ?? 'good',
      taskCategory: json['taskCategory'] ?? 'normal',
      durationMinutes: json['durationMinutes'] is int
          ? json['durationMinutes']
          : (json['durationMinutes'] is String
                ? int.tryParse(json['durationMinutes'])
                : null),
      isImageVerifiable: json['isImageVerifiable'] ?? false,
      status: json['status'] ?? 'pending',
      userId: json['userId'] ?? '',
      createdAt: json['createdAt'] ?? DateTime.now().toIso8601String(),
      completedAt: json['completedAt'] as String?,
    );
  }
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  String userName = 'User';
  bool isLoading = true;
  List<Task> tasks = [];
  List<Task> completedTasks = [];
  int aura = 50;
  int _aura = 50;
  List<int> auraHistory = [50];
  List<DateTime?> auraDates = [];
  AuraHistoryView auraHistoryView = AuraHistoryView.day;
  Map<String, dynamic>? _userProfile;
  int _selectedIndex = 0;
  bool _isTimetableSetupInProgress = true;

  Widget _buildEmptyTasksView() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DynamicColorSvg(
            assetName: 'assets/img/empty_tasks.svg',
            color: scheme.primary,
            width: 240,
            height: 240,
          ),
          const SizedBox(height: 20),
          Text(
            'No active tasks',
            style: GoogleFonts.gabarito(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: scheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a task from the button below.',
            style: GoogleFonts.gabarito(
              fontSize: 14,
              color: scheme.outline.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  final GlobalKey<State<StatefulWidget>> _habitsKey =
      GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _blockerKey =
      GlobalKey<State<StatefulWidget>>();
  final GlobalKey<State<StatefulWidget>> _plannerKey =
      GlobalKey<State<StatefulWidget>>();

  static const _prefShowQuote = 'pref_show_quote';
  static const _prefEnabledTabs = 'pref_enabled_tabs';
  static const _prefSmartSuggestions = 'pref_smart_suggestions';

  Set<String> _enabledTabs = {'habits', 'blocker', 'planner', 'timer'};
  bool _smartSuggestions = true;

  final bool _showAllTasks = false;
  final bool _showAllStudyTasks = false;
  bool _showQuote = true;

  List<DateTime?> auraDatesForView = [];

  late final ApiService _apiService;
  final _storage = const FlutterSecureStorage();
  String? _currentFcmToken;

  List<dynamic> _preloadedHabits = [];

  late AnimationController _bounceController;
  late Animation<double> _bounceScale;
  int? _completedIndex;
  AnimationController? _holdController;
  int? _holdingIndex;
  bool _secondTickDone = false;
  static const int _secondTickLeadMs = 180;

  bool _refreshInFlight = false;

  Timer? _auraChipTimer;
  bool _showAuraAsText = false;

  bool _titleShowHello = true;
  Timer? _helloTitleTimer;

  String? _taskLoadError;
  String? _quoteText;
  String? _quoteAuthor;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(account: widget.account);
    _initializePageData();
    _loadPreferences();

    _bounceController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 850),
          )
          ..addStatusListener((s) {
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
            end: 0.12,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 20,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 0.12,
            end: -0.06,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 14,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -0.06,
            end: 0.04,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 12,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 0.04,
            end: -0.02,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 10,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -0.02,
            end: 0.01,
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
              final habit = _preloadedHabits[_holdingIndex!];
              final id =
                  (habit[r'$id'] ?? habit['id'] ?? habit['habitId'] ?? '')
                      .toString();
              if (id.isNotEmpty) {
                _completeHabitFromHome(habit, _holdingIndex!);
              }
            }
            _resetHold();
          }
        });

    _auraChipTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (!mounted) return;
      setState(() => _showAuraAsText = true);
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _showAuraAsText = false);
      });
    });

    _helloTitleTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _titleShowHello = false);
    });
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _holdController?.dispose();
    _auraChipTimer?.cancel();
    _helloTitleTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializePageData() async {
    if (mounted) _initApp();
  }

  Future<void> _initApp() async {
    await _loadUserName();
    await _fetchDataFromServer();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final profile = await _apiService.getUserProfile();
      if (!mounted) return;
      setState(() {
        _userProfile = profile;
        final dynamic auraValue = profile['aura'];
        if (auraValue is num) {
          aura = auraValue.toInt();
        } else if (auraValue is String) {
          final parsed = int.tryParse(auraValue);
          if (parsed != null) aura = parsed;
        }
      });
    } catch (e) {
      debugPrint('Failed to fetch profile: $e');
    }
  }

  Future<void> _loadUserName() async {
    try {
      final models.User user = await widget.account.get();
      if (mounted) {
        setState(() => userName = user.name.isNotEmpty ? user.name : "User");
      }
    } catch (e) {
      if (mounted) setState(() => userName = "User");
    }
  }

  Future<void> _fetchDataFromServer() async {
    if (!mounted || _refreshInFlight) return;
    _refreshInFlight = true;
    
    
    if (tasks.isEmpty && _preloadedHabits.isEmpty) {
      setState(() {
        isLoading = true;
        _taskLoadError = null;
      });
    }

    try {
      
      final dashboard = await _apiService.getTasksAndHabits().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException('Failed to load data in time.');
        },
      );

      List<dynamic> badHabits = (dashboard['badHabits'] as List?) ?? [];
      if (badHabits.isEmpty) {
        try {
          
          
          
          
          
        } catch (e) {
          debugPrint('Failed to fetch bad habits: $e');
        }
      } else {
        print('DEBUG: Fetched ${badHabits.length} bad habits from dashboard');
      }

      final fetchedTasks = (dashboard['tasks'] as List?) ?? const [];
      final goodHabits = (dashboard['habits'] as List?) ?? const [];

      final allHabits = <Map<String, dynamic>>[];
      for (final h in goodHabits) {
        if (h is Map) {
          final m = Map<String, dynamic>.from(h);
          m['type'] = 'good';
          allHabits.add(m);
        }
      }
      for (final h in badHabits) {
        if (h is Map) {
          final m = Map<String, dynamic>.from(h);
          m['type'] = 'bad';
          allHabits.add(m);
        }
      }

      final allTasks = fetchedTasks
          .map((t) => Task.fromJson(t as Map<String, dynamic>))
          .toList();

      setState(() {
        final apiName = (dashboard['name'] as String?)?.trim();
        if (apiName != null && apiName.isNotEmpty) userName = apiName;

        if (dashboard['username'] != null) {
          _userProfile = {'username': dashboard['username']};
        }

        final auraValue = dashboard['aura'];
        if (auraValue is num) {
          aura = auraValue.toInt();
        } else if (auraValue is String) {
          final parsed = int.tryParse(auraValue);
          if (parsed != null) aura = parsed;
        }

        final q = dashboard['quote'];
        if (q is Map) {
          _quoteText = (q['quote'] as String?)?.trim();
          _quoteAuthor = (q['author'] as String?)?.trim();
        }

        completedTasks = allTasks
            .where((t) => t.status == 'completed')
            .toList();
        tasks = allTasks.where((t) => t.status == 'pending').toList();
        _preloadedHabits = allHabits;
      });
    } catch (e) {
      setState(() {
        _taskLoadError = e.toString();
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
      _refreshInFlight = false;
    }
  }

  Future<void> logout() async {
    try {
      await widget.account.deleteSession(sessionId: 'current');
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => AuthCheck(account: widget.account)),
      (route) => false,
    );
  }

  void _addTask() async {
    final taskNameController = TextEditingController();
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceBright,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 32,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add New Task',
                        style: GoogleFonts.gabarito(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: taskNameController,
                        autofocus: true,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter task name',
                          labelText: 'Task Name',
                          labelStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          hintStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final name = taskNameController.text.trim();
                                if (name.isEmpty) return;
                                Map<String, dynamic> data = {
                                  'name': name,
                                  'category': 'normal',
                                };
                                Navigator.pop(context, data);
                              },
                              child: const Text('Add Task'),
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
      },
    );
    if (result != null) {
      final String name = result['name'];
      try {
        setState(() => isLoading = true);
        await _apiService.createTask(
          name: name,
          taskCategory: 'normal',
          durationMinutes: null,
        );
        await _fetchDataFromServer();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to add task: ${e.toString()}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteTask(int index) async {
    final pendingTasks = tasks.where((t) => t.status == 'pending').toList();
    if (index < 0 || index >= pendingTasks.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Task index out of bounds.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final Task taskToDelete = pendingTasks[index];

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dCtx) {
        final cs = Theme.of(dCtx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: cs.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Delete task?',
                  style: GoogleFonts.gabarito(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'This will remove the task permanently. This action cannot be undone.',
            style: GoogleFonts.gabarito(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: cs.onSurfaceVariant,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
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
                backgroundColor: cs.errorContainer,
                foregroundColor: cs.error,
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
    if (confirm == true) {
      try {
        setState(() => isLoading = true);
        await _apiService.deleteTask(taskToDelete.id);
        if (mounted) {
          setState(() {
            tasks.remove(taskToDelete);
            isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete task: ${e.toString()}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _completeTask(int index) async {
    if (index < 0 || index >= tasks.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error completing task: Invalid index."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final Task task = tasks[index];
    Map<String, dynamic>? apiCallResult;

    bool dialogWasShown = false;
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      dialogWasShown = true;
    }

    try {
      if (task.type == "bad") {
        if (task.taskCategory == 'timed') {
          apiCallResult = await _apiService.completeTimedTask(task.id);
        } else {
          apiCallResult = await _apiService.completeBadTask(task.id);
        }
      } else {
        if (task.taskCategory == "normal") {
          if (task.isImageVerifiable) {
            final picker = ImagePicker();
            final pickedFile = await picker.pickImage(
              source: ImageSource.camera,
              preferredCameraDevice: CameraDevice.rear,
            );
            if (pickedFile == null) {
              if (dialogWasShown && mounted) Navigator.pop(context);
              return;
            }
            final bytes = await File(pickedFile.path).readAsBytes();
            final base64Image = base64Encode(bytes);
            apiCallResult = await _apiService.completeNormalImageVerifiableTask(
              task.id,
              base64Image,
            );
          } else {
            apiCallResult = await _apiService.completeNormalNonVerifiableTask(
              task.id,
            );
          }
        } else if (task.taskCategory == 'timed') {
          apiCallResult = await _apiService.completeTimedTask(task.id);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Unsupported task completion for ${task.name}."),
              ),
            );
          }
          if (dialogWasShown && mounted) Navigator.pop(context);
          return;
        }
      }

      if (mounted) {
        await _fetchDataFromServer();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${apiCallResult['message'] ?? 'Task status updated.'} Aura change: ${apiCallResult['auraChange'] ?? 0}',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Task completion failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (dialogWasShown && mounted) Navigator.pop(context);
      if (mounted && isLoading) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _markTaskAsBadClientSide(int index) async {
    final Task task = tasks[index];
    if (task.status == 'completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot change type of a completed task.')),
      );
      return;
    }
    try {
      setState(() => isLoading = true);
      final updatedTaskData = await _apiService.markTaskAsBad(task.id);
      if (mounted) {
        setState(() {
          tasks[index] = Task.fromJson(updatedTaskData);
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Task "${task.name}" marked as bad.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark task as bad: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<int> getAuraHistoryForView() {
    if (auraHistoryView == AuraHistoryView.day) return auraHistory;
    if (auraHistoryView == AuraHistoryView.month) {
      Map<String, int> monthMap = {};
      Map<String, DateTime> monthDateMap = {};
      for (int i = 0; i < auraDates.length; i++) {
        final d = auraDates[i];
        if (d == null) continue;
        final key = "${d.year}-${d.month}";
        monthMap[key] = auraHistory[i];
        monthDateMap[key] = DateTime(d.year, d.month, 1);
      }
      auraDatesForView = monthDateMap.values.toList();
      return monthMap.values.toList();
    }
    if (auraHistoryView == AuraHistoryView.year) {
      Map<int, int> yearMap = {};
      Map<int, DateTime> yearDateMap = {};
      for (int i = 0; i < auraDates.length; i++) {
        final d = auraDates[i];
        if (d == null) continue;
        yearMap[d.year] = auraHistory[i];
        yearDateMap[d.year] = DateTime(d.year, 1, 1);
      }
      auraDatesForView = yearDateMap.values.toList();
      return yearMap.values.toList();
    }
    return auraHistory;
  }

  List<DateTime?> getAuraDatesForView() {
    if (auraHistoryView == AuraHistoryView.day) return auraDates;
    return auraDatesForView;
  }

  void _updateTimetableSetupState(bool isComplete) {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isTimetableSetupInProgress = !isComplete;
          });
        }
      });
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final showQuote = prefs.getBool(_prefShowQuote);
    final smartSuggestions = prefs.getBool(_prefSmartSuggestions);
    final tabs = prefs.getStringList(_prefEnabledTabs);
    if (!mounted) return;
    setState(() {
      if (showQuote != null) _showQuote = showQuote;
      if (smartSuggestions != null) _smartSuggestions = smartSuggestions;
      _enabledTabs =
          (tabs?.toSet() ?? {'habits', 'blocker', 'planner', 'timer'})
              .where(
                (t) => {'habits', 'blocker', 'planner', 'timer'}.contains(t),
              )
              .toSet();
      if (_enabledTabs.isEmpty) _enabledTabs = {'habits'};
      final keys = _currentTabKeys();
      if (_selectedIndex >= keys.length) _selectedIndex = 0;
    });
  }

  Future<void> _updateShowQuote(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefShowQuote, value);
    if (mounted) setState(() => _showQuote = value);
  }

  Future<void> _updateSmartSuggestions(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefSmartSuggestions, value);
    if (mounted) setState(() => _smartSuggestions = value);
  }

  Future<void> _updateEnabledTabs(Set<String> tabs) async {
    final next = tabs.isEmpty ? {'habits'} : tabs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefEnabledTabs, next.toList());
    if (!mounted) return;
    setState(() {
      _enabledTabs = next;
      final keys = _currentTabKeys();
      if (_selectedIndex >= keys.length) _selectedIndex = 0;
    });
  }

  List<String> _currentTabKeys() {
    final keys = <String>['home'];
    if (_enabledTabs.contains('timer')) keys.add('timer');
    if (_enabledTabs.contains('habits')) keys.add('habits');
    if (_enabledTabs.contains('blocker')) keys.add('blocker');
    if (_enabledTabs.contains('planner')) keys.add('planner');
    return keys;
  }

  (List<Widget>, List<String>) _currentPagesAndKeys() {
    final pages = <Widget>[];
    final keys = <String>[];

    pages.add(_buildDashboardView());
    keys.add('home');

    if (_enabledTabs.contains('habits')) {
      pages.add(
        HabitsPage(
          apiService: _apiService,
          userName: userName,
          initialHabits: _preloadedHabits,
          smartSuggestionsEnabled: _smartSuggestions,
        ),
      );
      keys.add('habits');
    }
    if (_enabledTabs.contains('blocker')) {
      pages.add(
        SocialMediaBlockerScreen(
          apiService: _apiService,
          onChallengeCompleted: _fetchDataFromServer,
        ),
      );
      keys.add('blocker');
    }
    if (_enabledTabs.contains('planner')) {
      pages.add(
        StudyPlannerScreen(
          onSetupStateChanged: _updateTimetableSetupState,
          apiService: _apiService,
          onTaskCompleted: _fetchDataFromServer,
          initialStudyPlan: null,
          autoFetchIfMissing: true,
        ),
      );
      keys.add('planner');
    }

    return (pages, keys);
  }

  Widget _buildSelectedTab(String key) {
    switch (key) {
      case 'habits':
        return HabitsPage(
          key: _habitsKey,
          apiService: _apiService,
          userName: userName,
          initialHabits: _preloadedHabits,
          smartSuggestionsEnabled: _smartSuggestions,
        );
      case 'blocker':
        return SocialMediaBlockerScreen(
          key: _blockerKey,
          apiService: _apiService,
          onChallengeCompleted: _fetchDataFromServer,
        );
      case 'planner':
        return StudyPlannerScreen(
          key: _plannerKey,
          onSetupStateChanged: _updateTimetableSetupState,
          apiService: _apiService,
          onTaskCompleted: _fetchDataFromServer,
          initialStudyPlan: null,
          autoFetchIfMissing: true,
        );
      case 'home':
      default:
        return _buildDashboardView();
    }
  }

  double _measureTextWidth(BuildContext context, String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return tp.size.width;
  }

  @override
  Widget build(BuildContext context) {
    final keys = _currentTabKeys();
    final selectedKey = keys[_selectedIndex];
    final showHeader =
        !(selectedKey == 'planner' && _isTimetableSetupInProgress);
    final chipTextStyle = GoogleFonts.gabarito(
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final currentAuraText = _showAuraAsText ? 'Aura' : '$aura';
    final baseWidth = _measureTextWidth(context, 'Aura', chipTextStyle);
    final currentWidth = _measureTextWidth(
      context,
      currentAuraText,
      chipTextStyle,
    );
    final labelWidth = math.max(baseWidth, currentWidth);

    final leadingW = labelWidth + 72;

    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.surface,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Chip(
              shape: const StadiumBorder(),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withOpacity(0.5),
              ),
              avatar: Icon(
                Icons.auto_awesome_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              label: ConstrainedBox(
                constraints: BoxConstraints(minWidth: baseWidth),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.0, 0.5),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    currentAuraText,
                    key: ValueKey<bool>(_showAuraAsText),
                    textAlign: TextAlign.center,
                    style: chipTextStyle,
                  ),
                ),
              ),
            ),
          ),
          leadingWidth: leadingW,
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              _titleShowHello ? 'Hello.' : 'AurAchieve',
              key: ValueKey<bool>(_titleShowHello),
              style: GoogleFonts.ebGaramond(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
              ),
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(
                Icons.account_circle_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 32,
              ),
              tooltip: 'Profile',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ProfilePage(
                      apiService: _apiService,
                      aura: aura,
                      tasks: tasks,
                      auraHistory: auraHistory,
                      auraDates: auraDates,
                      completedTasks: completedTasks,
                      showQuote: _showQuote,
                      smartSuggestions: _smartSuggestions,
                      enabledTabs: _enabledTabs,
                      onShowQuoteChanged: _updateShowQuote,
                      onSmartSuggestionsChanged: _updateSmartSuggestions,
                      onEnabledTabsChanged: (tabs) async {
                        if (tabs.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Keep at least one tab besides Home enabled.',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        await _updateEnabledTabs(tabs);
                      },
                      onLogout: logout,
                      username: _userProfile?['username'],
                      onAuraChanged: (newAura) {
                        setState(() {
                          aura = newAura;
                          _aura = newAura;
                        });
                      },
                    ),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        body: Column(
          children: [
            if (showHeader) const SizedBox(height: 8),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  _buildDashboardView(),
                  const TimerPage(),
                  HabitsPage(
                    apiService: _apiService,
                    userName: userName,
                    initialHabits: _preloadedHabits,
                    currentAura: _aura,
                    onAuraChange: (val) => setState(() {
                      aura = val;
                      _aura = val;
                    }),
                  ),
                  SocialMediaBlockerScreen(
                    apiService: _apiService,
                    onChallengeCompleted: _fetchDataFromServer,
                  ),
                  StudyPlannerScreen(
                    onSetupStateChanged: _updateTimetableSetupState,
                    apiService: _apiService,
                    onTaskCompleted: _fetchDataFromServer,
                    initialStudyPlan: null,
                    autoFetchIfMissing: true,
                    onPlanUpdated: _fetchDataFromServer,
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) {
            HapticFeedback.selectionClick();
            setState(() => _selectedIndex = i);
          },
          destinations: keys.map((key) {
            switch (key) {
              case 'home':
                return const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                );
              case 'timer':
                return const NavigationDestination(
                  icon: Icon(Icons.timer_outlined),
                  selectedIcon: Icon(Icons.timer),
                  label: 'Timer',
                );
              case 'habits':
                return const NavigationDestination(
                  icon: Icon(Icons.checklist_rtl_outlined),
                  selectedIcon: Icon(Icons.checklist_rtl_rounded),
                  label: 'Habits',
                );
              case 'blocker':
                return const NavigationDestination(
                  icon: Icon(Icons.app_blocking_outlined),
                  selectedIcon: Icon(Icons.app_blocking_rounded),
                  label: 'Blocker',
                );
              case 'planner':
                return const NavigationDestination(
                  icon: Icon(Icons.edit_calendar_outlined),
                  selectedIcon: Icon(Icons.edit_calendar_rounded),
                  label: 'Planner',
                );
              default:
                return const NavigationDestination(
                  icon: Icon(Icons.circle_outlined),
                  label: '',
                );
            }
          }).toList(),
        ),
        floatingActionButton: _selectedIndex == 0
            ? FloatingActionButton.extended(
                heroTag: 'home_fab',
                onPressed: _addTask,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Task'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              )
            : null,
      ),
    );
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

  String _todayLocalKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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

  Future<void> _completionHaptics() async {
    try {
      HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 40));
      HapticFeedback.mediumImpact();
    } catch (_) {}
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

  Future<void> _completeHabitFromHome(
    Map<String, dynamic> habit,
    int index,
  ) async {
    final id = (habit[r'$id'] ?? habit['id'] ?? habit['habitId'] ?? '')
        .toString();
    if (id.isEmpty) return;

    final isBad = habit['type'] == 'bad';
    final prevCount = habit['completedTimes'] as int? ?? 0;
    final prevDays = _normalizeCompletedDays(habit['completedDays']);
    final today = _todayLocalKey();
    final updatedDays = List<String>.from(prevDays);
    if (!updatedDays.contains(today)) updatedDays.add(today);

    setState(() {
      habit['completedTimes'] = prevCount + 1;
      habit['completedDays'] = updatedDays;
      _completedIndex = index;
    });

    unawaited(_completionHaptics());
    _secondTickDone = false;
    _bounceController.forward(from: 0);

    try {
      Map<String, dynamic> result;
      if (isBad) {
        result = await _apiService.incrementBadHabit(id);
      } else {
        result = await _apiService.incrementHabitCompletedTimes(
          id,
          completedDays: updatedDays,
        );
      }

      if (mounted) {
        final newAura = result['aura'];
        if (newAura is num) {
          setState(() {
            aura = newAura.toInt();
            _aura = newAura.toInt();
          });
        }
      }
    } catch (e) {
      setState(() {
        habit['completedTimes'] = prevCount;
        habit['completedDays'] = prevDays;
        _completedIndex = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update habit: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showHabitDetails(Map<String, dynamic> habit) {
    final isBad = habit['type'] == 'bad';
    if (isBad) {
      final id = (habit[r'$id'] ?? habit['id'] ?? habit['habitId'] ?? '')
          .toString();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(habit['habitName'] ?? 'Bad Habit'),
          content: const Text('Delete this bad habit?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _apiService.deleteBadHabit(id);
                  if (mounted) {
                    setState(() {
                      _preloadedHabits.removeWhere(
                        (h) =>
                            (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '')
                                .toString() ==
                            id,
                      );
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bad habit deleted')),
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
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return HabitDetailsSheet(
          habit: habit,
          apiService: _apiService,
          userName: userName,
          onDelete: (id) async {
            try {
              await _apiService.deleteHabit(id);
              if (mounted) {
                setState(() {
                  _preloadedHabits.removeWhere(
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
                final index = _preloadedHabits.indexWhere(
                  (h) =>
                      (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '').toString() ==
                      id,
                );
                if (index != -1) {
                  final existing = _preloadedHabits[index];
                  final merged = Map<String, dynamic>.from(existing);
                  merged.addAll(updatedHabit);

                  if (!updatedHabit.containsKey('type')) {
                    merged['type'] = existing['type'];
                  }

                  merged['completedDays'] = _normalizeCompletedDays(
                    merged['completedDays'],
                  );
                  _preloadedHabits[index] = merged;
                }
              });
            }
          },
        );
      },
    );
  }

  Widget _buildHabitCardForHome(
    Map<String, dynamic> h,
    int index,
    ColorScheme scheme,
  ) {
    final id = (h[r'$id'] ?? h['id'] ?? h['habitId'] ?? '').toString();
    final name = (h['habitName'] ?? h['habit'] ?? '').toString();
    final isBad = h['type'] == 'bad';
    final badGoal = (h['habitGoal'] ?? '').toString();
    final goal = isBad
        ? (badGoal.isNotEmpty
              ? badGoal
              : (h['severity'] ?? 'Bad Habit').toString())
        : (h['habitGoal'] ?? h['goal'] ?? '').toString();
    final totalCompletions = h['completedTimes'] as int? ?? 0;

    final completedDaysRaw = _normalizeCompletedDays(h['completedDays']);
    final todayStr = _todayLocalKey();
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

    final colorPair = isBad
        ? (bg: scheme.errorContainer, fg: scheme.onErrorContainer)
        : (bg: scheme.surfaceContainer, fg: scheme.onSurface);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16.0),
    );
    final BorderRadius radius = shape.borderRadius as BorderRadius;

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
        margin: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        color: colorPair.bg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: isBad
                ? scheme.error.withOpacity(0.5)
                : scheme.outlineVariant.withOpacity(0.5),
          ),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showHabitDetails(h),
          onLongPressStart: (_) {
            if (id.isEmpty) return;
            if (index < 0 || index >= _preloadedHabits.length) return;
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
                              color: (isBad ? scheme.error : scheme.primary)
                                  .withOpacity(0.22),
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
                                    text: isBad ? ', then ' : 'to become ',
                                    style: TextStyle(
                                      color: colorPair.fg.withOpacity(0.8),
                                    ),
                                  ),
                                  TextSpan(
                                    text: goal,
                                    style: TextStyle(
                                      color: colorPair.fg,
                                      decoration: isBad
                                          ? null
                                          : TextDecoration.underline,
                                      decorationColor: isBad
                                          ? null
                                          : scheme.primary.withOpacity(0.8),
                                      decorationStyle: isBad
                                          ? null
                                          : TextDecorationStyle.wavy,
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

  Widget _buildDashboardView() {
    if (isLoading) {
      return const _LoadingView();
    }

    final pendingTasks = tasks.where((t) => t.status == 'pending').toList();

    if (_taskLoadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load tasks.',
              style: GoogleFonts.gabarito(
                fontSize: 18,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: _fetchDataFromServer,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = constraints.maxWidth;
        final int crossAxisCount = screenWidth > 600 ? 4 : 2;
        final hasHabits = _preloadedHabits.isNotEmpty;
        final scheme = Theme.of(context).colorScheme;

        if (pendingTasks.isEmpty && !hasHabits) {
          return _buildEmptyTasksView();
        }

        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: 18.0,
          ).copyWith(bottom: 80),
          children: [
            if (pendingTasks.isEmpty)
              SizedBox(
                height: constraints.maxHeight * 0.5,
                child: _buildEmptyTasksView(),
              )
            else ...[
              const SizedBox(height: 4),
              if (_showQuote)
                Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 16, bottom: 12),
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 12,
                        top: 20,
                        bottom: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            _quoteText?.isNotEmpty == true
                                ? _quoteText!
                                : 'Make them realise that they lost a diamond while playing with worthless stones',
                            style: GoogleFonts.gabarito(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              _quoteAuthor?.isNotEmpty == true
                                  ? '- ${_quoteAuthor!}'
                                  : '- Captain Underpants',
                              style: GoogleFonts.ebGaramond(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 0,
                      child: IconButton(
                        onPressed: () {
                          setState(() {
                            _showQuote = false;
                          });
                        },
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Material(
                    type: MaterialType.transparency,
                    child: Text(
                      'Your Tasks',
                      style: GoogleFonts.gabarito(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (pendingTasks.length > 4)
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => AllTasksScreen(
                              tasks: tasks,
                              allPendingTasks: pendingTasks,
                              onCompleteTask: _completeTask,
                              onDeleteTask: _deleteTask,
                              buildTaskIcon: _buildTaskIcon,
                              buildTaskSubtitle: _buildCompactSubtitle,
                              apiService: _apiService,
                              onTaskCompleted: _fetchDataFromServer,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.0,
                ),
                itemCount: pendingTasks.length > 4 ? 4 : pendingTasks.length,
                itemBuilder: (context, index) {
                  final task = pendingTasks[index];
                  final originalTaskIndex = tasks.indexOf(task);
                  return _buildTaskCard(task, originalTaskIndex);
                },
              ),
            ],
            if (hasHabits) ...[
              const SizedBox(height: 24.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Habits",
                    style: GoogleFonts.gabarito(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),

                  IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: () {
                      final keys = _currentTabKeys();
                      final idx = keys.indexOf('habits');
                      if (idx != -1) {
                        setState(() => _selectedIndex = idx);
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => HabitsPage(
                              apiService: _apiService,
                              userName: userName,
                              initialHabits: _preloadedHabits,
                              currentAura: _aura,
                              onAuraChange: (newAura) {
                                setState(() => _aura = newAura);
                              },
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              ..._preloadedHabits.where((h) => h['type'] != 'bad').take(2).map((
                h,
              ) {
                final m = (h is Map<String, dynamic>)
                    ? h
                    : Map<String, dynamic>.from(h as Map);
                m['completedTimes'] = m['completedTimes'] ?? 0;
                m['completedDays'] = _normalizeCompletedDays(
                  m['completedDays'],
                );
                final index = _preloadedHabits.indexOf(h);
                return _buildHabitCardForHome(m, index, scheme);
              }),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTaskCard(Task task, int originalTaskIndex) {
    const int maxTitleChars = 30;
    final String displayTitle = task.name.length > maxTitleChars
        ? '${task.name.substring(0, maxTitleChars)}...'
        : task.name;

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () {
          if (task.status == "pending") {
            _completeTask(originalTaskIndex);
          }
        },
        onLongPress: () => _deleteTask(originalTaskIndex),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTaskIcon(task, context),
              const SizedBox(height: 12),
              Text(
                displayTitle,
                style: GoogleFonts.gabarito(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              _buildCompactSubtitle(task, context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactSubtitle(Task task, BuildContext context) {
    final theme = Theme.of(context);

    if (task.type == "bad") {
      return Row(
        children: [
          Text(
            "${_capitalize(task.type)} (${_capitalize(task.intensity)})",
            style: GoogleFonts.gabarito(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      );
    } else if (task.taskCategory == 'timed') {
      return Row(
        children: [
          Text(
            _capitalize(task.intensity),
            style: GoogleFonts.gabarito(
              fontSize: 13,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.timer_outlined,
            size: 14,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 2),
          Text(
            task.durationMinutes != null ? "${task.durationMinutes} min" : "",
            style: GoogleFonts.gabarito(
              fontSize: 12,
              color: theme.colorScheme.secondary.withOpacity(0.8),
            ),
          ),
        ],
      );
    } else {
      return Row(
        children: [
          Text(
            _capitalize(task.intensity),
            style: GoogleFonts.gabarito(
              fontSize: 13,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            task.isImageVerifiable
                ? Icons.camera_alt_outlined
                : Icons.check_circle_outline,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      );
    }
  }

  String _todayDateStringLocal() {
    final today = DateUtils.dateOnly(DateTime.now());
    return DateFormat('yyyy-MM-dd').format(today);
  }



  Widget _materialYouTaskIcon(String intensity, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (intensity.toLowerCase()) {
      case 'easy':
        return CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(
            Icons.eco_rounded,
            color: cs.onPrimaryContainer,
            size: 26,
          ),
        );
      case 'medium':
        return CircleAvatar(
          backgroundColor: cs.secondaryContainer,
          child: Icon(
            Icons.bolt_rounded,
            color: cs.onSecondaryContainer,
            size: 26,
          ),
        );
      case 'hard':
        return CircleAvatar(
          backgroundColor: cs.errorContainer,
          child: Icon(
            Icons.whatshot_rounded,
            color: cs.onErrorContainer,
            size: 26,
          ),
        );
      default:
        return CircleAvatar(
          backgroundColor: cs.surfaceContainerHighest,
          child: Icon(
            Icons.task_alt_rounded,
            color: cs.onSurfaceVariant,
            size: 26,
          ),
        );
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);

  Widget _buildTaskIcon(Task task, BuildContext context) {
    return _materialYouTaskIcon(task.intensity, context);
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

class _LoadingView extends StatefulWidget {
  const _LoadingView();

  @override
  State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView> {
  final List<String> _messages = [
    'Cooking...',
    'Brewing coffee...',
    'Dusting off the pixels...',
    'Aligning the stars...',
    'Feeding the hamsters...',
    'Loading your awesomeness...',
    'Reticulating splines...',
    'Warming up the engines...',
    'Searching across the stars...',
    'Preparing your experience...',
  ];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _index = (_index + 1) % _messages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.5),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              _messages[_index],
              key: ValueKey<int>(_index),
              style: GoogleFonts.gabarito(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
