import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'widgets/dynamic_color_svg.dart';
import 'api_service.dart';

const List<IconData> kSubjectIcons = [
  Icons.subject,
  Icons.calculate,
  Icons.science_outlined,
  Icons.biotech_outlined,
  Icons.rocket_launch_outlined,
  Icons.history_edu_outlined,
  Icons.public_outlined,
  Icons.translate_outlined,
  Icons.computer_outlined,
  Icons.code,
  Icons.palette_outlined,
  Icons.music_note_outlined,
  Icons.sports_soccer_outlined,
  Icons.fitness_center,
  Icons.account_balance_outlined,
  Icons.book_outlined,
  Icons.edit_outlined,
  Icons.architecture_outlined,
];

final Map<int, IconData> kSubjectIconMap = {
  for (final icon in kSubjectIcons) icon.codePoint: icon,
};

class Subject {
  String name;
  IconData icon;
  Color color;

  Subject({required this.name, required this.icon, required this.color});

  Map<String, dynamic> toJson() => {
    'name': name,
    'icon_code_point': icon.codePoint,
    'icon_font_family': icon.fontFamily,
    'icon_font_package': icon.fontPackage,
    'color_value': color.value,
  };

  factory Subject.fromJson(Map<String, dynamic> json) {
    final codePoint = json['icon_code_point'] as int?;

    final icon = kSubjectIconMap[codePoint] ?? Icons.subject;
    return Subject(
      name: json['name'],
      icon: icon,
      color: Color(json['color_value'] ?? Colors.blue.value),
    );
  }
}

class StudyPlannerScreen extends StatefulWidget {
  final Function(bool) onSetupStateChanged;
  final ApiService apiService;
  final VoidCallback? onTaskCompleted;

  const StudyPlannerScreen({
    super.key,
    required this.onSetupStateChanged,
    required this.apiService,
    this.onTaskCompleted,
  });

  @override
  State<StudyPlannerScreen> createState() => _StudyPlannerScreenState();
}

class _StudyPlannerScreenState extends State<StudyPlannerScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSetupComplete = false;
  bool _isLoading = true;
  bool _isGenerating = false;
  bool _isSaving = false;

  List<Subject> _subjects = [];
  Map<String, List<Map<String, String>>> _chapters = {};
  DateTime? _deadline;
  List<Map<String, dynamic>> _generatedTimetable = [];
  Map<String, dynamic>? _studyPlan;

  final TextEditingController _subjectController = TextEditingController();
  IconData _currentSubjectIcon = Icons.subject;
  bool _showFullSchedule = false;

  final ScrollController _previewScrollController = ScrollController();
  Map<String, dynamic>? _draggingPayload;
  Timer? _autoScrollTimer;

  static final List<Color> _subjectColors = [
    Colors.green[200]!,
    Colors.purple[200]!,
    Colors.blue[200]!,
    Colors.red[200]!,
    Colors.orange[200]!,
    Colors.teal[200]!,
    Colors.pink[100]!,
    Colors.amber[200]!,
    Colors.indigo[100]!,
    Colors.cyan[200]!,
  ];

  @override
  void initState() {
    super.initState();
    _loadTimetableData();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _previewScrollController.dispose();
    _pageController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  void _startAutoScroll(Offset globalPos) {
    const edgeExtent = 80.0;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    final y = globalPos.dy;
    double? direction;
    if (y < edgeExtent) {
      direction = -1;
    } else if (y > size.height - edgeExtent) {
      direction = 1;
    }
    if (direction == null) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      return;
    }
    _autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 60), (_) {
      final sc = _previewScrollController;
      if (!sc.hasClients) return;
      final newOffset = (sc.offset + direction! * 40).clamp(
        0.0,
        sc.position.maxScrollExtent,
      );
      sc.jumpTo(newOffset);
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _addTaskToDay(String date, Map<String, dynamic> task) {
    final idx = _generatedTimetable.indexWhere((d) => d['date'] == date);
    if (idx == -1) return;
    final tasks = List<Map<String, dynamic>>.from(
      _generatedTimetable[idx]['tasks'] as List,
    );
    tasks.removeWhere((t) => t['type'] == 'break');
    tasks.add(task);
    setState(() {
      _generatedTimetable[idx]['tasks'] = tasks;
    });
  }

  IconData _getIconForSubject(String subjectName) {
    final s = subjectName.toLowerCase().trim();
    if (s.isEmpty) return Icons.subject;
    final rules = <RegExp, IconData>{
      RegExp(
        r'\b(math|mathematics|maths|algebra|calc|calculus|trig|geometry|stat|statistics)\b',
      ): Icons.calculate,
      RegExp(r'\b(phys|physics|phy)\b'): Icons.science_outlined,
      RegExp(r'\b(chem|chemistry)\b'): Icons.biotech_outlined,
      RegExp(r'\b(bio|biology)\b'): Icons.biotech_outlined,
      RegExp(r'\b(geo|geog|geography|earth|enviro|environment)\b'):
          Icons.public_outlined,
      RegExp(r'\b(hist|history)\b'): Icons.history_edu_outlined,
      RegExp(r'\b(cs|computer|program|coding|code|software|informatics|it)\b'):
          Icons.code,
      RegExp(r'\b(eng|english|language|literature|lit|lang arts)\b'):
          Icons.translate_outlined,
      RegExp(r'\b(econ|economics)\b'): Icons.account_balance_outlined,
      RegExp(r'\b(bus|business|commerce|acct|accounting|finance)\b'):
          Icons.account_balance_outlined,
      RegExp(r'\b(art|drawing|design|paint|sketch|visual)\b'):
          Icons.palette_outlined,
      RegExp(r'\b(music|piano|guitar|violin|band|choir)\b'):
          Icons.music_note_outlined,
      RegExp(
        r'\b(pe|sport|sports|fitness|health|phys ed|physical education)\b',
      ): Icons.fitness_center,
      RegExp(r'\b(ast|astro|astronomy|space)\b'): Icons.rocket_launch_outlined,
      RegExp(
        r'\b(lang|french|spanish|german|italian|latin|arabic|chinese|japanese|russian|hindi|punjabi)\b',
      ): Icons.translate_outlined,
      RegExp(r'\b(philosophy|ethics|logic)\b'): Icons.history_edu_outlined,
      RegExp(r'\b(psych|psychology|sociology|social)\b'): Icons.subject,
      RegExp(r'\b(comp sci|computer science)\b'): Icons.code,
      RegExp(r'\b(engineer|engineering)\b'): Icons.architecture_outlined,
    };
    for (final entry in rules.entries) {
      if (entry.key.hasMatch(s)) return entry.value;
    }
    return Icons.subject;
  }

  Future<void> _loadTimetableData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final plan = await widget.apiService.getStudyPlan();
      if (plan != null) {
        setState(() {
          _studyPlan = plan;
          _isSetupComplete = true;
          final subjectsJson = plan['subjects'] as List;
          _subjects = subjectsJson
              .map((s) => Subject.fromJson(s as Map<String, dynamic>))
              .toList();

          _chapters = (plan['chapters'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(
              key,
              (value as List)
                  .map((item) => Map<String, String>.from(item))
                  .toList(),
            ),
          );

          _deadline = DateTime.tryParse(plan['deadline']);

          final timetableJson = plan['timetable'] as List;
          _generatedTimetable = timetableJson
              .map(
                (e) => {
                  'date': (e['date'] as String),
                  'tasks': (e['tasks'] as List)
                      .map((t) => Map<String, dynamic>.from(t))
                      .toList(),
                },
              )
              .toList();
        });
      } else {
        setState(() {
          _isSetupComplete = false;
        });
      }
    } catch (e) {
      print('Error loading study plan: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load study plan: $e')),
        );
      }
      setState(() {
        _isSetupComplete = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      widget.onSetupStateChanged(_isSetupComplete);
    }
  }

  Future<void> _resetTimetable() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Reset Study Plan?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to delete your current study plan and start over? This action cannot be undone.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.apiService.deleteStudyPlan();
        setState(() {
          _isSetupComplete = false;
          _subjects.clear();
          _chapters.clear();
          _deadline = null;
          _generatedTimetable.clear();
          _studyPlan = null;
          _currentPage = 0;
        });
        widget.onSetupStateChanged(false);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to reset plan: $e')));
        }
      }
    }
  }

  void _addSubject() {
    final subjectName = _subjectController.text.trim();
    if (subjectName.isNotEmpty &&
        !_subjects.any((s) => s.name == subjectName)) {
      setState(() {
        final color = _subjectColors[_subjects.length % _subjectColors.length];
        _subjects.add(
          Subject(name: subjectName, icon: _currentSubjectIcon, color: color),
        );
        _chapters[subjectName] = [];
        _subjectController.clear();
        _currentSubjectIcon = Icons.subject;
      });
    }
  }

  void _removeSubject(Subject subject) {
    setState(() {
      _subjects.remove(subject);
      _chapters.remove(subject.name);
    });
  }

  void _changeSubjectIcon(Subject subject) async {
    final newIcon = await showDialog<IconData>(
      context: context,
      builder: (context) => SubjectIconPickerDialog(initialIcon: subject.icon),
    );
    if (newIcon != null) {
      setState(() {
        subject.icon = newIcon;
      });
    }
  }

  void _showChapterPicker(String subject) async {
    final existingChapterNumbers =
        _chapters[subject]
            ?.map((chap) => int.tryParse(chap['number']!))
            .where((num) => num != null)
            .cast<int>()
            .toSet() ??
        {};

    final selectedNumbers = await showDialog<Set<int>>(
      context: context,
      builder: (context) =>
          ChapterPickerDialog(initialChapters: existingChapterNumbers),
    );

    if (selectedNumbers != null) {
      setState(() {
        _chapters[subject]!.removeWhere(
          (chap) => !selectedNumbers.contains(int.parse(chap['number']!)),
        );

        for (var number in selectedNumbers) {
          if (!_chapters[subject]!.any(
            (chap) => chap['number'] == number.toString(),
          )) {
            _chapters[subject]!.add({
              'number': number.toString(),
              'chapterName': '',
            });
          }
        }

        _chapters[subject]!.sort(
          (a, b) => int.parse(a['number']!).compareTo(int.parse(b['number']!)),
        );
      });
    }
  }

  void _editChapterName(String subject, String chapterNumber) {
    final nameController = TextEditingController(
      text: _chapters[subject]?.firstWhere(
        (chap) => chap['number'] == chapterNumber,
      )['chapterName'],
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Edit Name for Ch. $chapterNumber',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            labelText: 'Chapter Name (Optional)',
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                final chapterIndex = _chapters[subject]!.indexWhere(
                  (chap) => chap['number'] == chapterNumber,
                );
                if (chapterIndex != -1) {
                  _chapters[subject]![chapterIndex]['chapterName'] =
                      nameController.text.trim();
                }
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateTimetable() async {
    setState(() {
      _isGenerating = true;
    });

    if (_subjects.isEmpty || _deadline == null) {
      setState(() {
        _isGenerating = false;
      });
      return;
    }

    try {
      final apiResponse = await widget.apiService.generateTimetablePreview(
        chapters: _chapters,
        deadline: _deadline!,
      );

      final newTimetable = apiResponse.map((dayData) {
        final date = dayData['date'] as String;
        final tasks = (dayData['tasks'] as List<dynamic>).map((taskData) {
          return Map<String, dynamic>.from(taskData);
        }).toList();
        return {'date': date, 'tasks': tasks};
      }).toList();

      setState(() {
        _generatedTimetable = newTimetable;
      });
    } catch (e) {
      print('Error generating study plan preview from API: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate study plan preview: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _saveAndFinish() async {
    setState(() {
      _isSaving = true;
    });
    try {
      final subjectsJson = _subjects.map((s) => s.toJson()).toList();
      await widget.apiService.saveStudyPlan(
        subjects: subjectsJson,
        chapters: _chapters,
        deadline: _deadline!,
        timetable: _generatedTimetable,
      );
      await _loadTimetableData();
    } catch (e) {
      print('Error saving study plan: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save study plan: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  bool _isNextEnabled() {
    if (_currentPage == 1 && _subjects.isEmpty) return false;

    if (_currentPage == 2) {
      if (_subjects.isEmpty) return false;
      return _subjects.every((subj) {
        final chapList = _chapters[subj.name];
        return chapList != null && chapList.length >= 2;
      });
    }
    if (_currentPage == 3 && _deadline == null) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_isSaving) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Saving your schedule..."),
          ],
        ),
      );
    }
    return _isSetupComplete ? _buildTimetableView() : _buildOnboardingView();
  }

  Widget _buildOnboardingView() {
    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (page) => setState(() => _currentPage = page),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildIntroPage(
                'assets/img/timetable.svg',
                "Welcome to Study Planner",
                "If you're a student who needs to study and remember books, this is for you.",
              ),
              _buildSubjectsPage(),
              _buildChaptersPage(),
              _buildDeadlinePage(),
              _buildFinalPage(),
              _buildPreviewPage(),
            ],
          ),
        ),
        _buildNavigationControls(),
      ],
    );
  }

  Widget _buildTimetableView() {
    final today = DateUtils.dateOnly(DateTime.now());
    final todayString = DateFormat('yyyy-MM-dd').format(today);

    final todaySchedule = _generatedTimetable.firstWhere(
      (d) => d['date'] == todayString,
      orElse: () => <String, Object>{'date': todayString, 'tasks': <dynamic>[]},
    );
    final futureSchedule = _generatedTimetable
        .where((d) => DateTime.parse(d['date']).isAfter(today))
        .toList();

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            "Today's Plan",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),

          if ((todaySchedule['tasks'] as List).isEmpty)
            _buildTaskTile({'type': 'break'}, todaySchedule['date'] as String)
          else
            ...?(todaySchedule['tasks'] as List?)?.map(
              (task) => _buildTaskTile(task, todaySchedule['date'] as String),
            ),
          ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text("See ahead of time"),
            onExpansionChanged: (isExpanded) {
              setState(() => _showFullSchedule = isExpanded);
            },
            children: [
              if (!_showFullSchedule)
                const Center(child: Text("Expand to see future schedule."))
              else
                ...futureSchedule.map((day) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                        child: Text(
                          DateFormat(
                            'EEEE, MMM d',
                          ).format(DateTime.parse(day['date'])),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                      ),

                      if ((day['tasks'] as List).isEmpty)
                        _buildTaskTile({'type': 'break'}, day['date'] as String)
                      else
                        ...(day['tasks'] as List).map(
                          (task) => _buildTaskTile(task, day['date'] as String),
                        ),
                    ],
                  );
                }),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _resetTimetable,
        label: const Text('Reset'),
        icon: const Icon(Icons.refresh),
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
      ),
    );
  }

  Future<void> _toggleTaskCompletion(
    Map<String, dynamic> task,
    String dateOfTask,
  ) async {
    if (task['completed'] == true) return;

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
      final result = await widget.apiService.completeStudyPlanTask(
        task['id'],
        dateOfTask,
      );

      await _loadTimetableData();

      if (widget.onTaskCompleted != null) {
        widget.onTaskCompleted!();
      }

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
      if (dialogWasShown && mounted) {
        Navigator.pop(context);
      }
    }
  }

  Widget _buildTaskTile(
    Map<String, dynamic> item,
    String dateOfTask, {
    bool isFeedback = false,
    bool isPreview = false,
  }) {
    IconData icon;
    Widget title;
    Widget? subtitle;
    Widget? trailing;
    Color avatarColor;

    final today = DateUtils.dateOnly(DateTime.now());
    final taskDate = DateUtils.dateOnly(DateTime.parse(dateOfTask));
    final isFutureTask = taskDate.isAfter(today);

    switch (item['type']) {
      case 'study':
        final content = item['content'] as Map<String, dynamic>;
        final subject = _subjects.firstWhere(
          (s) => s.name == content['subject'],
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
      case 'revision':
        final content = item['content'] as Map<String, dynamic>;
        final subject = _subjects.firstWhere(
          (s) => s.name == content['subject'],
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
      default:
        icon = Icons.self_improvement_outlined;
        avatarColor = Theme.of(context).colorScheme.tertiaryContainer;
        title = const Text("Break Day");
        subtitle = const Text("Relax and recharge!");
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: avatarColor,
          child: Icon(
            icon,
            color:
                ThemeData.estimateBrightnessForColor(avatarColor) ==
                    Brightness.dark
                ? Colors.white
                : Colors.black,
          ),
        ),
        title: title,
        subtitle: subtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null) trailing,

            if (item['type'] != 'break' && !isFeedback && !isPreview)
              Checkbox(
                value: (item['completed'] as bool?) ?? false,
                onChanged:
                    isFutureTask || ((item['completed'] as bool?) ?? false)
                    ? null
                    : (bool? value) {
                        if (value == true) {
                          _toggleTaskCompletion(item, dateOfTask);
                        }
                      },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationControls() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _currentPage == 0
                ? null
                : () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.ease,
                  ),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: !_isNextEnabled() || (_currentPage == 5 && _isGenerating)
                ? null
                : () {
                    if (_currentPage == 1) {
                      FocusScope.of(context).unfocus();
                    }
                    if (_currentPage == 4) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.ease,
                      );
                      _generateTimetable();
                    } else if (_currentPage == 5) {
                      _saveAndFinish();
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.ease,
                      );
                    }
                  },
            child: Text(_currentPage == 5 ? 'Finish' : 'Next'),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroPage(String asset, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DynamicColorSvg(
            assetName: asset,
            height: 180,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.gabarito(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectsPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Enter your subjects",
            style: GoogleFonts.gabarito(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Add subjects and pick an icon for each. We'll try to guess an icon for you!",
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _subjectController,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Subject Name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _currentSubjectIcon = _getIconForSubject(value);
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.add),
                onPressed: _addSubject,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _subjects.length,
              itemBuilder: (context, index) {
                final subject = _subjects[index];
                return Card(
                  child: ListTile(
                    leading: IconButton(
                      icon: Icon(subject.icon),
                      onPressed: () => _changeSubjectIcon(subject),
                      tooltip: "Change Icon",
                    ),
                    title: Text(subject.name),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => _removeSubject(subject),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChaptersPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Now, enter your chapters for each subject!",
            style: GoogleFonts.gabarito(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Select multiple chapter numbers at once, then tap a chapter to add an optional name. Each subject must have at least 2 chapters.",
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _subjects.length,
              itemBuilder: (context, index) {
                final subject = _subjects[index];
                final chapterList = _chapters[subject.name] ?? [];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: Icon(subject.icon),
                    title: Text(subject.name),
                    subtitle: Text("${chapterList.length} chapters"),
                    children: [
                      ...chapterList.map(
                        (chap) => ListTile(
                          title: Text("Ch. ${chap['number']}"),
                          subtitle: chap['chapterName']!.isNotEmpty
                              ? Text(chap['chapterName']!)
                              : const Text(
                                  'Tap to add name',
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    fontSize: 12,
                                  ),
                                ),
                          dense: true,
                          onTap: () =>
                              _editChapterName(subject.name, chap['number']!),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextButton.icon(
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text("Select Chapters"),
                          onPressed: () => _showChapterPicker(subject.name),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlinePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Enter your deadline",
            style: GoogleFonts.gabarito(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "This could be the beginning of your exams or a date before which you want to prepare everything!",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            _deadline == null
                ? 'No date selected'
                : DateFormat.yMMMd().format(_deadline!),
            style: TextStyle(
              fontSize: 28,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: const Text("Select Date"),
            onPressed: () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate:
                    _deadline ?? DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now().add(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              );
              if (pickedDate != null) {
                setState(() {
                  _deadline = pickedDate;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFinalPage() {
    return _buildIntroPage(
      'assets/img/ai_robot.svg',
      "We'll prepare a study plan for you",
      "Based on the information you provided, we'll generate a study plan for you with the power of AI. You get aura for following the plan and lose it otherwise.",
    );
  }

  Widget _buildPreviewPage() {
    if (_isGenerating) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Generating your custom schedule..."),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Here's Your Plan",
            style: GoogleFonts.gabarito(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "This is a preview of the generated schedule. You can go back to make changes or drag and drop these across days.",
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _generatedTimetable.isEmpty
                ? const Center(
                    child: Text(
                      "Could not generate study plan. Check deadline and chapters.",
                    ),
                  )
                : Listener(
                    onPointerMove: (e) {
                      if (_draggingPayload != null)
                        _startAutoScroll(e.position);
                    },
                    onPointerUp: (_) => _stopAutoScroll(),
                    onPointerCancel: (_) => _stopAutoScroll(),
                    child: ListView.builder(
                      controller: _previewScrollController,
                      itemCount: _generatedTimetable.length,
                      itemBuilder: (context, index) {
                        final day = _generatedTimetable[index];
                        final date = DateTime.parse(day['date'] as String);
                        final tasks = List<Map<String, dynamic>>.from(
                          day['tasks'] as List,
                        );

                        Widget buildHandle() {
                          final color = Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.55);
                          return SizedBox(
                            width: 28,
                            height: 52,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(3, (i) {
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: i == 2 ? 0 : 5),
                                    child: Container(
                                      width: 16,
                                      height: 2.2,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          );
                        }

                        List<Widget> taskWidgets = [];
                        if (tasks.isEmpty) {
                          taskWidgets.add(
                            _buildTaskTile(
                              {'type': 'break'},
                              day['date'] as String,
                              isPreview: true,
                            ),
                          );
                        } else {
                          for (int i = 0; i < tasks.length; i++) {
                            final task = tasks[i];
                            final isBreak = task['type'] == 'break';
                            final tile = Stack(
                              children: [
                                _buildTaskTile(
                                  task,
                                  day['date'],
                                  isPreview: true,
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: IgnorePointer(
                                    ignoring: true,
                                    child: buildHandle(),
                                  ),
                                ),
                              ],
                            );

                            if (isBreak) {
                              taskWidgets.add(tile);
                              continue;
                            }

                            taskWidgets.add(
                              LongPressDraggable<Map<String, dynamic>>(
                                data: {'task': task, 'sourceDate': day['date']},
                                dragAnchorStrategy: childDragAnchorStrategy,
                                onDragStarted: () {
                                  HapticFeedback.mediumImpact();
                                  setState(
                                    () => _draggingPayload = {
                                      'task': task,
                                      'sourceDate': day['date'],
                                    },
                                  );
                                },
                                onDragEnd: (_) {
                                  _stopAutoScroll();
                                  setState(() => _draggingPayload = null);
                                },
                                onDraggableCanceled: (_, __) {
                                  _stopAutoScroll();
                                  setState(() => _draggingPayload = null);
                                },
                                feedback: Material(
                                  elevation: 6,
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.transparent,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width -
                                          64,
                                      minWidth:
                                          MediaQuery.of(context).size.width -
                                          64,
                                    ),
                                    child: Opacity(
                                      opacity: 0.95,
                                      child: _buildTaskTile(
                                        task,
                                        day['date'],
                                        isFeedback: true,
                                        isPreview: true,
                                      ),
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.35,
                                  child: tile,
                                ),
                                child: tile,
                              ),
                            );
                            if (i == tasks.length - 1) continue;
                          }
                        }

                        final isReceiving = _draggingPayload != null;

                        return DragTarget<Map<String, dynamic>>(
                          builder: (context, candidate, rejected) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: isReceiving
                                      ? Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.35),
                                          width: 1.4,
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                      ),
                                      child: Text(
                                        DateFormat('EEEE, MMM d').format(date),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ...taskWidgets,
                                    if (candidate.isNotEmpty)
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        height: 58,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withOpacity(0.4),
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            'Drop here',
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                          onWillAccept: (data) => true,
                          onAccept: (payload) {
                            final taskToMove =
                                payload['task'] as Map<String, dynamic>;
                            final sourceDateStr =
                                payload['sourceDate'] as String;
                            final targetDateStr = day['date'] as String;
                            if (sourceDateStr == targetDateStr) return;

                            setState(() {
                              final sourceIndex = _generatedTimetable
                                  .indexWhere(
                                    (d) => d['date'] == sourceDateStr,
                                  );
                              final targetIndex = _generatedTimetable
                                  .indexWhere(
                                    (d) => d['date'] == targetDateStr,
                                  );
                              if (sourceIndex == -1 || targetIndex == -1)
                                return;
                              final sourceTasks =
                                  List<Map<String, dynamic>>.from(
                                    _generatedTimetable[sourceIndex]['tasks']
                                        as List,
                                  );
                              final targetTasks =
                                  List<Map<String, dynamic>>.from(
                                    _generatedTimetable[targetIndex]['tasks']
                                        as List,
                                  );
                              sourceTasks.removeWhere(
                                (t) => t['id'] == taskToMove['id'],
                              );
                              targetTasks.removeWhere(
                                (t) => t['type'] == 'break',
                              );
                              targetTasks.add(taskToMove);
                              _generatedTimetable[sourceIndex]['tasks'] =
                                  sourceTasks;
                              _generatedTimetable[targetIndex]['tasks'] =
                                  targetTasks;
                              _draggingPayload = null;
                            });
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class SubjectIconPickerDialog extends StatelessWidget {
  final IconData initialIcon;
  const SubjectIconPickerDialog({super.key, required this.initialIcon});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose an Icon'),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: kSubjectIcons.length,
          itemBuilder: (context, index) {
            final icon = kSubjectIcons[index];
            return InkWell(
              onTap: () => Navigator.pop(context, icon),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: initialIcon == icon
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                    width: initialIcon == icon ? 2.0 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 32),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class ChapterPickerDialog extends StatefulWidget {
  final Set<int> initialChapters;
  const ChapterPickerDialog({super.key, this.initialChapters = const {}});

  @override
  State<ChapterPickerDialog> createState() => _ChapterPickerDialogState();
}

class _ChapterPickerDialogState extends State<ChapterPickerDialog> {
  final PageController _pageController = PageController();
  final Set<int> _selectedChapters = {};
  int _currentPage = 0;

  final int _totalPages = 6;
  final int _chaptersPerPage = 15;

  @override
  void initState() {
    super.initState();

    _selectedChapters.addAll(widget.initialChapters);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Select Chapters',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _totalPages,
                onPageChanged: (page) => setState(() => _currentPage = page),
                itemBuilder: (context, pageIndex) {
                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          childAspectRatio: 1.2,
                        ),
                    itemCount: _chaptersPerPage,
                    itemBuilder: (context, gridIndex) {
                      final chapterNumber =
                          pageIndex * _chaptersPerPage + gridIndex + 1;
                      final isSelected = _selectedChapters.contains(
                        chapterNumber,
                      );
                      return InkWell(
                        borderRadius: BorderRadius.circular(50),
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedChapters.remove(chapterNumber);
                            } else {
                              _selectedChapters.add(chapterNumber);
                            }
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Center(
                            child: Text(
                              '$chapterNumber',
                              style: TextStyle(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
                                fontWeight: isSelected ? FontWeight.bold : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  onPressed: _currentPage == 0
                      ? null
                      : () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeIn,
                        ),
                ),
                Text(
                  'Page ${_currentPage + 1} of $_totalPages',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios),
                  onPressed: _currentPage >= _totalPages - 1
                      ? null
                      : () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeIn,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selectedChapters),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
