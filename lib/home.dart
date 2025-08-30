import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'social_blocker.dart';
import 'stats.dart';
import 'api_service.dart';
import 'widgets/dynamic_color_svg.dart';
import 'screens/auth_check_screen.dart';
import 'timer_page.dart';
import 'study_planner.dart';
import 'screens/extended_task_list.dart';
import 'habits.dart';

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

class _HomePageState extends State<HomePage> {
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

  final bool _showAllTasks = false;
  final bool _showAllStudyTasks = false;
  List<Map<String, dynamic>> _todaysStudyPlan = [];
  List<Subject> _subjects = [];
  bool _isStudyPlanSetupComplete = false;
  bool _showQuote = true;

  List<DateTime?> auraDatesForView = [];

  late final ApiService _apiService;
  final _storage = const FlutterSecureStorage();
  String? _currentFcmToken;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(account: widget.account);
    _initializePageData();
  }

  Future<void> _initializePageData() async {
    await _initApp();
    if (mounted) {
      //    _initPushNotifications();
    }
  }

  Future<void> _initApp() async {
    setState(() => isLoading = true);
    await _loadUserName();
    await _fetchDataFromServer();
    await _loadStudyPlanData();
    if (mounted) setState(() => isLoading = false);
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

  Future<void> _loadStudyPlanData() async {
    try {
      final plan = await _apiService.getStudyPlan();
      if (mounted) {
        if (plan != null) {
          final subjectsJson = plan['subjects'] as List? ?? [];
          final subjects = subjectsJson
              .map((s) => Subject.fromJson(s as Map<String, dynamic>))
              .toList();

          final timetableJson = plan['timetable'] as List? ?? [];
          final today = DateUtils.dateOnly(DateTime.now());
          final todayString = DateFormat('yyyy-MM-dd').format(today);

          final todaySchedule = timetableJson.firstWhere(
            (d) => d['date'] == todayString,
            orElse: () => {'tasks': []},
          );

          setState(() {
            _isStudyPlanSetupComplete = true;
            _subjects = subjects;
            _todaysStudyPlan = (todaySchedule['tasks'] as List? ?? [])
                .map((t) => Map<String, dynamic>.from(t))
                .toList();
          });
        } else {
          setState(() {
            _isStudyPlanSetupComplete = false;
            _todaysStudyPlan = [];
          });
        }
      }
    } catch (e) {
      print("Error loading study plan from API: $e");
      if (mounted) {
        setState(() {
          _isStudyPlanSetupComplete = false;
          _todaysStudyPlan = [];
        });
      }
    }
  }

  Future<void> _fetchDataFromServer() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final fetchedTasks = await _apiService.getTasks();
      final fetchedProfile = await _apiService.getUserProfile();
      print("Debug: _fetchDataFromServer: fetchedProfile = $fetchedProfile");

      if (mounted) {
        setState(() {
          tasks = fetchedTasks
              .map((taskJson) => Task.fromJson(taskJson))
              .where((task) => task.status == 'pending')
              .toList();
          completedTasks = fetchedTasks
              .map((taskJson) => Task.fromJson(taskJson))
              .where((task) => task.status == 'completed')
              .toList();

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
        });
      }
    } catch (e, s) {
      print("Debug: _fetchDataFromServer: Exception caught: $e");
      print("Debug: _fetchDataFromServer: Stacktrace: $s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching data: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _userProfile = null;
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
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

  /*  void _initPushNotifications() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
      if (mounted) {
        setState(() {
          _currentFcmToken = token;
        });
      }
    } catch (e, s) {
      print("Debug: _initPushNotifications: Exception caught: $e");
      print("Debug: _initPushNotifications: Stacktrace: $s");
      if (mounted) {
        setState(() {
          _currentFcmToken = null;
        });
      }
      return;
    }

    if (token != null && _userProfile != null) {
      final String? currentUserId = _userProfile!['userId'];
      if (currentUserId != null) {
        try {
          Account authenticatedAccount = widget.account;
          await authenticatedAccount.createPushTarget(
            targetId: currentUserId,
            identifier: token,
            providerId: '682f36330001ecdab2e5',
          );

          print(
            'FCM token $token successfully registered with Appwrite for user $currentUserId',
          );
        } catch (e) {
          print('Error registering FCM token with Appwrite: $e');
          if (e is AppwriteException) {
            print(
              'AppwriteException details: ${e.message}, code: ${e.code}, response: ${e.response}',
            );
          }
        }
      } else {
        print(
          "User ID is null in _initPushNotifications, cannot register FCM token with Appwrite.",
        );
      }
    } else {
      if (token == null) print("FCM token is null in _initPushNotifications.");
      if (_userProfile == null) {
        print(
          "_userProfile is null in _initPushNotifications, cannot get User ID for FCM registration.",
        );
      }
    }
  }
*/
  void _updateTimetableSetupState(bool isComplete) {
    if (mounted) {
      setState(() {
        _isTimetableSetupInProgress = !isComplete;
      });

      if (isComplete) {
        _loadStudyPlanData();
      } else {
        setState(() {
          _isStudyPlanSetupComplete = false;
          _todaysStudyPlan = [];
        });
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> widgetOptions = <Widget>[
      _buildDashboardView(),
      HabitsPage(apiService: _apiService),
      SocialMediaBlockerScreen(
        apiService: _apiService,
        onChallengeCompleted: _fetchDataFromServer,
      ),
      StudyPlannerScreen(
        onSetupStateChanged: _updateTimetableSetupState,
        apiService: _apiService,
        onTaskCompleted: _fetchDataFromServer,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          'AurAchieve',
          style: GoogleFonts.ebGaramond(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              Icons.bar_chart_rounded,
              color: Theme.of(context).colorScheme.primary,
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
              Icons.logout_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: logout,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!(_selectedIndex == 3 && _isTimetableSetupInProgress))
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
                if (!(_selectedIndex == 3 && _isTimetableSetupInProgress))
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
                if (!(_selectedIndex == 3 && _isTimetableSetupInProgress))
                  const SizedBox(height: 16),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: widgetOptions,
                  ),
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
        destinations: const <NavigationDestination>[
          NavigationDestination(
            selectedIcon: Icon(Icons.home_rounded),
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.repeat_outlined),
            label: 'Habits',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.no_cell_rounded),
            icon: Icon(Icons.no_cell_outlined),
            label: 'Blocker',
          ),
          NavigationDestination(
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
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            )
          : null,
    );
  }

  Widget _buildDashboardView() {
    final pendingTasks = tasks.where((t) => t.status == 'pending').toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = constraints.maxWidth;
        final int crossAxisCount = screenWidth > 600 ? 4 : 2;

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

            if (_isStudyPlanSetupComplete && _todaysStudyPlan.isNotEmpty) ...[
              const SizedBox(height: 24.0),
              Text(
                "Study Plan",
                style: GoogleFonts.gabarito(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),

              ..._todaysStudyPlan
                  .take(3)
                  .map((task) => _buildStudyPlanTile(task)),

              if (_todaysStudyPlan.length > 3)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 2;
                      });
                    },
                    child: const Text('Show More...'),
                  ),
                ),
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

  Widget _buildStudyPlanTile(Map<String, dynamic> item) {
    IconData icon;
    String titleText;
    String? subtitleText;
    Color avatarColor;

    switch (item['type']) {
      case 'study':
        final content = item['content'] as Map<String, dynamic>;
        final subject = _subjects.firstWhere(
          (s) => s.name == content['subject'],
          orElse: () =>
              Subject(name: 'Unknown', icon: Icons.help, color: Colors.grey),
        );
        icon = subject.icon;
        avatarColor = subject.color;
        titleText = "Study: Ch. ${content['chapterNumber']}";
        subtitleText = subject.name;
        break;
      case 'revision':
        final content = item['content'] as Map<String, dynamic>;
        final subject = _subjects.firstWhere(
          (s) => s.name == content['subject'],
          orElse: () =>
              Subject(name: 'Unknown', icon: Icons.help, color: Colors.grey),
        );
        icon = Icons.history_outlined;
        avatarColor = subject.color.withOpacity(0.7);
        titleText = "Revise: Ch. ${content['chapterNumber']}";
        subtitleText = subject.name;
        break;
      default:
        icon = Icons.self_improvement_outlined;
        avatarColor = Theme.of(context).colorScheme.tertiaryContainer;
        titleText = "Break Day";
        subtitleText = "Relax and recharge!";
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: avatarColor,
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(titleText),
        subtitle: Text(subtitleText),
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
