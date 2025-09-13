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

import 'social_blocker.dart';
import 'stats.dart';
import 'api_service.dart';
import 'widgets/dynamic_color_svg.dart';
import 'screens/auth_check_screen.dart';
import 'timer_page.dart';
import 'study_planner.dart';
import 'screens/extended_task_list.dart';
import 'habits.dart';
import 'settings.dart';

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
  List<int> auraHistory = [50];
  List<DateTime?> auraDates = [];
  AuraHistoryView auraHistoryView = AuraHistoryView.day;
  Map<String, dynamic>? _userProfile;
  int _selectedIndex = 0;
  bool _isTimetableSetupInProgress = true;

  static const _prefShowQuote = 'pref_show_quote';
  static const _prefEnabledTabs = 'pref_enabled_tabs';

  Set<String> _enabledTabs = {'habits', 'blocker', 'planner'};

  final bool _showAllTasks = false;
  final bool _showAllStudyTasks = false;
  List<Map<String, dynamic>> _todaysStudyPlan = [];
  List<Subject> _subjects = [];
  bool _isStudyPlanSetupComplete = false;
  Map<String, dynamic>? _studyPlanMap;
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

    _auraChipTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      setState(() => _showAuraAsText = true);
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _showAuraAsText = false);
      });
    });
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _holdController?.dispose();
    _auraChipTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializePageData() async {
    if (mounted) _initApp();
  }

  Future<void> _initApp() async {
    await _loadUserName();
    await _fetchDataFromServer();
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
    setState(() => isLoading = true);
    try {
      final dashboard = await _apiService.getTasksAndHabits();
      final fetchedTasks = (dashboard['tasks'] as List?) ?? const [];
      final fetchedHabits = (dashboard['habits'] as List?) ?? const [];

      final fetchedProfile = await _apiService.getUserProfile();

      Map<String, dynamic>? planMap;
      try {
        planMap = await _apiService.getStudyPlan();
      } catch (_) {
        planMap = null;
      }

      if (!mounted) return;
      setState(() {
        _studyPlanMap = planMap;

        final allTasks = fetchedTasks
            .map((t) => Task.fromJson(t as Map<String, dynamic>))
            .toList();
        completedTasks = allTasks
            .where((t) => t.status == 'completed')
            .toList();
        tasks = allTasks.where((t) => t.status == 'pending').toList();

        _preloadedHabits = fetchedHabits;

        _userProfile = fetchedProfile;
        aura = fetchedProfile['aura'] ?? 50;
        if (auraHistory.isEmpty || auraHistory.last != aura) {
          auraHistory.add(aura);
          if (auraHistory.length > 8) {
            auraHistory = auraHistory.sublist(auraHistory.length - 8);
          }
        }
        auraDates = completedTasks
            .map(
              (t) => t.completedAt != null
                  ? DateTime.tryParse(t.completedAt!)
                  : null,
            )
            .where((d) => d != null)
            .toList();

        if (planMap != null) {
          List asList(dynamic v) {
            if (v is List) return v;
            if (v is Map) {
              final c = v['data'] ?? v['items'] ?? v['documents'] ?? v['list'];
              return c is List ? c : const [];
            }
            return const [];
          }

          final subjectsJson = asList(planMap['subjects']);
          _subjects = subjectsJson
              .map((s) => Subject.fromJson(s as Map<String, dynamic>))
              .toList();

          List todayTasks = const [];
          final timetableJson = asList(planMap['timetable']);
          if (timetableJson.isNotEmpty) {
            final today = DateUtils.dateOnly(DateTime.now());
            final todayString = DateFormat('yyyy-MM-dd').format(today);
            final day = timetableJson.cast<Map>().firstWhere(
              (d) => d['date'] == todayString,
              orElse: () => const {'tasks': []},
            );
            todayTasks = (day['tasks'] as List?) ?? const [];
          }

          _todaysStudyPlan = todayTasks
              .map((t) => Map<String, dynamic>.from(t as Map))
              .toList();
          _isStudyPlanSetupComplete =
              _subjects.isNotEmpty || _todaysStudyPlan.isNotEmpty;
        } else {
          _isStudyPlanSetupComplete = false;
          _todaysStudyPlan = [];
        }
      });
    } catch (e, s) {
      print("Debug: _fetchDataFromServer error: $e\n$s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching data: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _userProfile = null;
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
      _refreshInFlight = false;
    }
  }

  Future<void> logout() async {
    try {
      await widget.account.deleteSession(sessionId: 'current');
      await _storage.delete(key: 'jwt_token');
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => AuthCheckScreen(account: widget.account),
          ),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {}
  }

  void _addTask() async {
    final taskNameController = TextEditingController();
    final hoursController = TextEditingController();
    final minutesController = TextEditingController();
    String selectedTaskCategory = 'normal';

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceBright,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            String? hourError;
            String? minuteError;

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
                      Text(
                        'Task Category:',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      RadioListTile<String>(
                        title: const Text('Normal Task'),
                        value: 'normal',
                        groupValue: selectedTaskCategory,
                        onChanged: (value) =>
                            modalSetState(() => selectedTaskCategory = value!),
                        activeColor: Theme.of(context).colorScheme.primary,
                      ),
                      RadioListTile<String>(
                        title: const Text('Timed Task'),
                        value: 'timed',
                        groupValue: selectedTaskCategory,
                        onChanged: (value) =>
                            modalSetState(() => selectedTaskCategory = value!),
                        activeColor: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
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
                      if (selectedTaskCategory == 'timed') ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: hoursController,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Upto 4 hours',
                                  labelText: 'Hours',
                                  errorText: hourError,
                                  labelStyle: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: minutesController,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Upto 59 minutes',
                                  labelText: 'Minutes',
                                  errorText: minuteError,
                                  labelStyle: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
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
                                modalSetState(() {
                                  hourError = 'Max 4 hours';
                                  minuteError = 'Max 59 mins';
                                });

                                final name = taskNameController.text.trim();
                                if (name.isEmpty) return;

                                Map<String, dynamic> data = {
                                  'name': name,
                                  'category': selectedTaskCategory,
                                };

                                if (selectedTaskCategory == 'timed') {
                                  final hours =
                                      int.tryParse(
                                        hoursController.text.trim(),
                                      ) ??
                                      0;
                                  final minutes =
                                      int.tryParse(
                                        minutesController.text.trim(),
                                      ) ??
                                      0;

                                  bool hasError = false;
                                  if (hours < 0 || hours > 4) {
                                    modalSetState(() {
                                      hourError = 'Max 4 hours';
                                    });
                                    hasError = true;
                                  }
                                  if (minutes < 0 || minutes > 59) {
                                    modalSetState(() {
                                      minuteError = 'Max 59 mins';
                                    });
                                    hasError = true;
                                  }
                                  if ((hours == 0 && minutes == 0) &&
                                      !hasError) {
                                    modalSetState(() {
                                      minuteError = 'Duration cannot be zero';
                                    });
                                    hasError = true;
                                  }
                                  if (hasError) return;

                                  data['duration'] = hours * 60 + minutes;
                                }
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
      final String category = result['category'];
      final int? duration = result['duration'];

      try {
        setState(() => isLoading = true);
        final newTaskData = await _apiService.createTask(
          name: name,
          taskCategory: category,
          durationMinutes: duration,
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
      } else if (apiCallResult == null && mounted) {}
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
            _isStudyPlanSetupComplete = isComplete;
          });

          if (isComplete) {
            _fetchDataFromServer();
          }
        }
      });
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final showQuote = prefs.getBool(_prefShowQuote);
    final tabs = prefs.getStringList(_prefEnabledTabs);
    if (!mounted) return;
    setState(() {
      if (showQuote != null) _showQuote = showQuote;
      _enabledTabs = (tabs?.toSet() ?? {'habits', 'blocker', 'planner'})
          .where((t) => {'habits', 'blocker', 'planner'}.contains(t))
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
        HabitsPage(apiService: _apiService, initialHabits: _preloadedHabits),
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
          initialStudyPlan: _studyPlanMap,
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
          apiService: _apiService,
          initialHabits: _preloadedHabits,
        );
      case 'blocker':
        return SocialMediaBlockerScreen(
          apiService: _apiService,
          onChallengeCompleted: _fetchDataFromServer,
        );
      case 'planner':
        return StudyPlannerScreen(
          onSetupStateChanged: _updateTimetableSetupState,
          apiService: _apiService,
          onTaskCompleted: _fetchDataFromServer,
          initialStudyPlan: _studyPlanMap,
        );
      case 'home':
      default:
        return _buildDashboardView();
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = _currentTabKeys();
    final selectedKey = keys[_selectedIndex];
    final plannerSelected = selectedKey == 'planner';
    final showHeader = !(plannerSelected && _isTimetableSetupInProgress);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Chip(
            shape: const StadiumBorder(),
            avatar: Icon(
              Icons.auto_awesome_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            label: SizedBox(
              width: 48,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
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
                  _showAuraAsText ? 'Aura' : '$aura',
                  key: ValueKey<bool>(_showAuraAsText),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.gabarito(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            side: BorderSide.none,
          ),
        ),
        leadingWidth: 120,
        title: Text(
          'AurAchieve',
          style: GoogleFonts.ebGaramond(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              Icons.bar_chart_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            tooltip: 'Stats',
            onLongPress: () async {
              Clipboard.setData(
                ClipboardData(text: await _apiService.getJwtToken() ?? ''),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('JWT token copied lil bro'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => StatsPage(
                    aura: aura,
                    tasks: tasks.where((t) => t.status == 'pending').toList(),
                    auraHistory: getAuraHistoryForView(),
                    auraDates: getAuraDatesForView(),
                    completedTasks: completedTasks,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    showQuote: _showQuote,
                    enabledTabs: _enabledTabs,
                    onShowQuoteChanged: _updateShowQuote,
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
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.ebGaramond(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    children: [
                      const TextSpan(text: 'Hi, '),
                      TextSpan(
                        text: userName,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const TextSpan(text: '!'),
                    ],
                  ),
                ),
              ),
            ),
          if (showHeader)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 26,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Your Aura: $aura',
                    style: GoogleFonts.gabarito(
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          if (showHeader) const SizedBox(height: 16),
          Expanded(
            child: selectedKey == 'home'
                ? (isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildDashboardView())
                : _buildSelectedTab(selectedKey),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        selectedIndex: _selectedIndex,
        destinations: [
          const NavigationDestination(
            selectedIcon: Icon(Icons.home_rounded),
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          if (_enabledTabs.contains('habits'))
            const NavigationDestination(
              selectedIcon: Icon(Icons.repeat_rounded),
              icon: Icon(Icons.repeat_outlined),
              label: 'Habits',
            ),
          if (_enabledTabs.contains('blocker'))
            const NavigationDestination(
              selectedIcon: Icon(Icons.no_cell_rounded),
              icon: Icon(Icons.no_cell_outlined),
              label: 'Blocker',
            ),
          if (_enabledTabs.contains('planner'))
            const NavigationDestination(
              selectedIcon: Icon(Icons.school_rounded),
              icon: Icon(Icons.school_outlined),
              label: 'Planner',
            ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              heroTag: 'add_task_fab',
              onPressed: _addTask,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Task'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            )
          : null,
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
      await _apiService.incrementHabitCompletedTimes(
        id,
        completedDays: updatedDays,
      );
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
    showDialog(
      context: context,
      builder: (context) {
        final name = (habit['habitName'] ?? habit['habit'] ?? '').toString();
        final goal = (habit['habitGoal'] ?? habit['goal'] ?? '').toString();
        final totalCompletions = habit['completedTimes'] as int? ?? 0;
        final completedDays = _normalizeCompletedDays(habit['completedDays']);
        return AlertDialog(
          title: Text(
            name,
            style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (goal.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text('Goal: $goal', style: GoogleFonts.gabarito()),
                ),
              Text(
                'Total Completions: $totalCompletions',
                style: GoogleFonts.gabarito(),
              ),
              Text(
                'Completed Days: ${completedDays.length}',
                style: GoogleFonts.gabarito(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
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
    final goal = (h['habitGoal'] ?? h['goal'] ?? '').toString();
    final totalCompletions = h['completedTimes'] as int? ?? 0;

    final completedDaysRaw = _normalizeCompletedDays(h['completedDays']);

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

    final colorPair = (bg: scheme.surfaceContainer, fg: scheme.onSurface);
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
          side: BorderSide(color: scheme.outlineVariant.withOpacity(0.5)),
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

  Widget _buildDashboardView() {
    final pendingTasks = tasks.where((t) => t.status == 'pending').toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = constraints.maxWidth;
        final int crossAxisCount = screenWidth > 600 ? 4 : 2;
        final hasHabits = _preloadedHabits.isNotEmpty;
        final scheme = Theme.of(context).colorScheme;

        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: 18.0,
          ).copyWith(bottom: 80),
          children: [
            if (pendingTasks.isEmpty)
              _buildEmptyTasksView()
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
                            'Make them realise that they lost a diamond while playing with worthless stones',
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
                              "- Captain Underpants",
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
                  Hero(
                    tag: 'your_tasks_title',
                    child: Material(
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
                  ),
                  if (pendingTasks.length > 4)
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: () {
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    AllTasksScreen(
                                      tasks: tasks,
                                      allPendingTasks: pendingTasks,
                                      onCompleteTask: _completeTask,
                                      onDeleteTask: _deleteTask,
                                      buildTaskIcon: _buildTaskIcon,
                                      buildTaskSubtitle: _buildTaskSubtitle,
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
                itemCount: pendingTasks.length > 4 ? 4 : pendingTasks.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
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
                              initialHabits: _preloadedHabits,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              ..._preloadedHabits.take(2).map((h) {
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
            if (_isStudyPlanSetupComplete) ...[
              const SizedBox(height: 24.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Study Plan",
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
                      final idx = keys.indexOf('planner');
                      if (idx != -1) setState(() => _selectedIndex = idx);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_todaysStudyPlan.isEmpty)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withOpacity(0.4),
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.tertiaryContainer,
                      child: Icon(
                        Icons.self_improvement_outlined,
                        color: Theme.of(
                          context,
                        ).colorScheme.onTertiaryContainer,
                      ),
                    ),
                    title: const Text("Break Day"),
                    subtitle: const Text("Relax and recharge!"),
                  ),
                )
              else
                ..._todaysStudyPlan
                    .take(3)
                    .map((task) => _buildStudyPlanTile(task)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTaskCard(Task task, int originalTaskIndex) {
    return Hero(
      tag: 'task_hero_${task.id}',
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          onTap: () {
            if (task.taskCategory == "timed" &&
                task.type == "good" &&
                task.status == "pending") {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TimerPage(
                    task: task,
                    apiService: _apiService,
                    onTaskCompleted: () {
                      _fetchDataFromServer();
                    },
                  ),
                ),
              );
            } else if (task.status == "pending") {
              _completeTask(originalTaskIndex);
            }
          },
          onLongPress: () => _deleteTask(originalTaskIndex),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTaskIcon(task, context),
                const SizedBox(height: 12),
                Text(
                  task.name,
                  style: GoogleFonts.gabarito(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Row(
                  children: [
                    Text(
                      _capitalize(task.type),
                      style: GoogleFonts.gabarito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: task.type == 'bad'
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "(${_capitalize(task.intensity)})",
                      style: GoogleFonts.gabarito(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _todayDateStringLocal() {
    final today = DateUtils.dateOnly(DateTime.now());
    return DateFormat('yyyy-MM-dd').format(today);
  }

  Future<void> _completeStudyPlanFromHome(Map<String, dynamic> item) async {
    if ((item['completed'] as bool?) == true) return;

    bool dialogShown = false;
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      dialogShown = true;
    }

    try {
      final result = await _apiService.completeStudyPlanTask(
        item['id'],
        _todayDateStringLocal(),
      );

      await _fetchDataFromServer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You gained ${result['auraChange'] ?? 30} Aura!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update task: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (dialogShown && mounted) Navigator.pop(context);
    }
  }

  Widget _buildStudyPlanTile(Map<String, dynamic> item) {
    IconData icon;
    Widget title;
    Widget? subtitle;
    Widget? trailing;
    Color avatarColor;

    switch (item['type']) {
      case 'study':
        {
          final content = item['content'] as Map<String, dynamic>;
          final subjectName = content['subject'] as String? ?? 'Unknown';
          final subject = _subjects.firstWhere(
            (s) => s.name == subjectName,
            orElse: () => Subject(
              name: 'Unknown',
              icon: Icons.help,
              color: Theme.of(context).colorScheme.outline,
            ),
          );
          final chapterNumber = content['chapterNumber'] as String?;
          final chapterName = content['chapterName'] as String? ?? '';

          icon = subject.icon;
          avatarColor = subject.color;
          title = Text(
            chapterName.isNotEmpty ? chapterName : "Chapter $chapterNumber",
            style: const TextStyle(fontWeight: FontWeight.w500),
          );
          subtitle = Text(subject.name);
          if (chapterName.isNotEmpty) {
            trailing = Text(
              "Ch. $chapterNumber",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            );
          }
          break;
        }
      case 'revision':
        {
          final content = item['content'] as Map<String, dynamic>;
          final subjectName = content['subject'] as String? ?? 'Unknown';
          final subject = _subjects.firstWhere(
            (s) => s.name == subjectName,
            orElse: () => Subject(
              name: 'Unknown',
              icon: Icons.help,
              color: Theme.of(context).colorScheme.outline,
            ),
          );
          final chapterNumber = content['chapterNumber'] as String?;
          final chapterName = content['chapterName'] as String? ?? '';

          icon = Icons.history_outlined;
          avatarColor = subject.color.withOpacity(0.7);
          title = Text(
            chapterName.isNotEmpty
                ? "Revise: $chapterName"
                : "Revise: Chapter $chapterNumber",
          );
          subtitle = Text(subject.name);
          break;
        }
      default:
        icon = Icons.self_improvement_outlined;
        avatarColor = Theme.of(context).colorScheme.tertiaryContainer;
        title = const Text("Break Day");
        subtitle = const Text("Relax and recharge!");
    }

    final iconColor =
        ThemeData.estimateBrightnessForColor(avatarColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final isBreak = item['type'] == 'break';
    final isCompleted = (item['completed'] as bool?) ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: avatarColor,
          child: Icon(icon, color: iconColor),
        ),
        title: title,
        subtitle: subtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null) trailing,
            if (!isBreak)
              Checkbox(
                value: isCompleted,
                onChanged: isCompleted
                    ? null
                    : (v) {
                        if (v == true) _completeStudyPlanFromHome(item);
                      },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTasksView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DynamicColorSvg(
            assetName: 'assets/img/empty_tasks.svg',
            height: 180,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'No active tasks.',
            style: GoogleFonts.gabarito(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add new tasks to get started.',
            style: GoogleFonts.gabarito(
              fontSize: 16,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksView() {
    final pendingTasks = tasks.where((t) => t.status == 'pending').toList();
    if (pendingTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DynamicColorSvg(
              assetName: 'assets/img/empty_tasks.svg',
              height: 180,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'No active tasks.',
              style: GoogleFonts.gabarito(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add new tasks to get started.',
              style: GoogleFonts.gabarito(
                fontSize: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: pendingTasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = pendingTasks[index];
        final originalTaskIndex = tasks.indexOf(task);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 4),
          child: GestureDetector(
            onLongPress: () => _deleteTask(originalTaskIndex),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(18),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: ListTile(
                onTap: () {
                  if (task.taskCategory == "timed" &&
                      task.type == "good" &&
                      task.status == "pending") {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TimerPage(
                          task: task,
                          apiService: _apiService,
                          onTaskCompleted: () {
                            _fetchDataFromServer();
                          },
                        ),
                      ),
                    );
                  } else if (task.status == "pending") {
                    _completeTask(originalTaskIndex);
                  }
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: _buildTaskIcon(task, context),
                title: Text(
                  task.name,
                  style: GoogleFonts.gabarito(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: _buildTaskSubtitle(task, context),
                trailing: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTaskIcon(Task task, BuildContext context) {
    if (task.type == "bad") {
      return CircleAvatar(
        backgroundColor: Colors.purple.shade100,
        child: Icon(
          Icons.warning_amber_rounded,
          color: Colors.purple,
          size: 26,
        ),
      );
    }
    if (task.taskCategory == "timed") {
      return CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
        child: Icon(
          Icons.timer_outlined,
          color: Theme.of(context).colorScheme.onTertiaryContainer,
          size: 26,
        ),
      );
    }
    return _materialYouTaskIcon(task.intensity, context);
  }

  Widget _buildTaskSubtitle(Task task, BuildContext context) {
    List<Widget> subtitleChildren = [];

    if (task.type == "bad") {
      subtitleChildren.add(
        Text(
          "Bad Task - ${_capitalize(task.intensity)}",
          style: GoogleFonts.gabarito(
            fontSize: 13,
            color: Colors.purple,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      if (task.taskCategory == 'timed' && task.durationMinutes != null) {
        subtitleChildren.add(
          Text(
            " (${task.durationMinutes} min)",
            style: GoogleFonts.gabarito(
              fontSize: 12,
              color: Colors.purple.withOpacity(0.8),
            ),
          ),
        );
      }
    } else {
      subtitleChildren.add(
        Text(
          _capitalize(task.intensity),
          style: GoogleFonts.gabarito(
            fontSize: 13,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

      if (task.taskCategory == 'timed' && task.durationMinutes != null) {
        subtitleChildren.add(
          Text(
            " - Timed (${task.durationMinutes} min)",
            style: GoogleFonts.gabarito(
              fontSize: 12,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        );
      } else {
        subtitleChildren.add(SizedBox(width: 4));
        subtitleChildren.add(
          Icon(
            task.isImageVerifiable
                ? Icons.camera_alt_outlined
                : Icons.check_circle_outline,
            size: 14,
            color: task.isImageVerifiable
                ? Colors.blueGrey
                : Colors.green.shade700,
          ),
        );
        subtitleChildren.add(SizedBox(width: 2));
        subtitleChildren.add(
          Text(
            task.isImageVerifiable ? "Photo" : "Honor",
            style: GoogleFonts.gabarito(
              fontSize: 11,
              color: task.isImageVerifiable
                  ? Colors.blueGrey
                  : Colors.green.shade700,
            ),
          ),
        );

        subtitleChildren.add(Spacer());
        subtitleChildren.add(
          TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: Size(0, 0),
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            icon: Icon(
              Icons.flag_outlined,
              size: 16,
              color: Colors.orange.shade700,
            ),
            label: Text(
              "Flag as Bad",
              style: GoogleFonts.gabarito(
                fontSize: 11,
                color: Colors.orange.shade700,
              ),
            ),
            onPressed: () => _markTaskAsBadClientSide(tasks.indexOf(task)),
          ),
        );
      }
    }
    return Row(children: subtitleChildren);
  }

  Widget _materialYouTaskIcon(String intensity, BuildContext context) {
    switch (intensity.toLowerCase()) {
      case 'easy':
        return CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.eco_rounded,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 26,
          ),
        );
      case 'medium':
        return CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(
            Icons.bolt_rounded,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
            size: 26,
          ),
        );
      case 'hard':
        return CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          child: Icon(
            Icons.whatshot_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
            size: 26,
          ),
        );
      default:
        return CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.task_alt_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 26,
          ),
        );
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
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
