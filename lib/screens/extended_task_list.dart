import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../home.dart';
import '../../api_service.dart';
import '../../timer_page.dart';
import 'dart:math' as math;

class AllTasksScreen extends StatefulWidget {
  final List<Task> tasks;
  final List<Task> allPendingTasks;
  final Function(int) onCompleteTask;
  final Function(int) onDeleteTask;
  final Function(Task, BuildContext) buildTaskIcon;
  final Function(Task, BuildContext) buildTaskSubtitle;
  final ApiService apiService;
  final VoidCallback onTaskCompleted;

  const AllTasksScreen({
    super.key,
    required this.tasks,
    required this.allPendingTasks,
    required this.onCompleteTask,
    required this.onDeleteTask,
    required this.buildTaskIcon,
    required this.buildTaskSubtitle,
    required this.apiService,
    required this.onTaskCompleted,
  });

  @override
  State<AllTasksScreen> createState() => _AllTasksScreenState();
}

class _AllTasksScreenState extends State<AllTasksScreen>
    with TickerProviderStateMixin {
  String? expandedTaskId;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  final Map<String, bool> _completingTasks = {};
  final Map<String, AnimationController> _checkAnimControllers = {};

  bool _showCompleteLabel = false;
  Timer? _labelTimer;

  late List<Task> _localPendingTasks;

  @override
  void initState() {
    super.initState();
    _expandController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 350),
          )
          ..addListener(() {
            setState(() {});
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              setState(() => _showCompleteLabel = true);
              _labelTimer?.cancel();
              _labelTimer = Timer(const Duration(seconds: 2), () {
                if (mounted) setState(() => _showCompleteLabel = false);
              });
            } else if (status == AnimationStatus.dismissed) {
              _labelTimer?.cancel();
              setState(() {
                _showCompleteLabel = false;
              });

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => expandedTaskId = null);
              });
            }
          });

    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOutCubic,
    );

    _localPendingTasks = List.from(widget.allPendingTasks);
  }

  @override
  void dispose() {
    _expandController.dispose();
    _labelTimer?.cancel();

    for (final controller in _checkAnimControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void _toggleExpand(String taskId) {
    if (_expandController.isAnimating) return;

    if (expandedTaskId == taskId) {
      _labelTimer?.cancel();
      setState(() => _showCompleteLabel = false);
      _expandController.reverse();
    } else {
      setState(() {
        expandedTaskId = taskId;
      });
      _expandController.forward(from: 0.0);
    }
  }

  Future<void> _completeTask(Task task, int originalIndex) async {
    if (_completingTasks[task.id] == true) return;

    if (!_checkAnimControllers.containsKey(task.id)) {
      _checkAnimControllers[task.id] = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
    }

    setState(() => _completingTasks[task.id] = true);
    await _checkAnimControllers[task.id]!.forward(from: 0.0);

    try {
      await widget.onCompleteTask(originalIndex);

      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        setState(() {
          _localPendingTasks.remove(task);
          _completingTasks[task.id] = false;

          if (expandedTaskId == task.id) {
            _toggleExpand(task.id);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _completingTasks[task.id] = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to complete task: ${e.toString()}'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Hero(
          tag: 'tasks_header_hero_v2',
          child: Material(
            type: MaterialType.transparency,
            child: Text(
              'Your Tasks',
              style: GoogleFonts.gabarito(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),

      body: LayoutBuilder(
        builder: (context, constraints) {
          final double screenWidth = constraints.maxWidth;
          final int crossAxisCount = screenWidth > 600 ? 4 : 2;

          return Stack(
            children: [
              GridView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18.0,
                  vertical: 8.0,
                ),
                itemCount: _localPendingTasks.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, index) {
                  final task = _localPendingTasks[index];
                  final originalIndex = widget.tasks.indexOf(task);
                  final isExpanded = expandedTaskId == task.id;
                  final isCompleting = _completingTasks[task.id] == true;

                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: (expandedTaskId != null && !isExpanded)
                        ? 0.3
                        : 1.0,
                    child: Material(
                      type: MaterialType.transparency,
                      child: _buildTaskCardItem(
                        context,
                        task,
                        originalIndex,
                        isExpanded,
                        isCompleting,
                        constraints,
                        index,
                      ),
                    ),
                  );
                },
              ),

              if (expandedTaskId != null)
                GestureDetector(
                  onTap: () {
                    if (expandedTaskId != null) {
                      _toggleExpand(expandedTaskId!);
                    }
                  },
                  child: Container(
                    color: Colors.transparent,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),

              if (expandedTaskId != null)
                _buildExpandedOverlayFromConstraints(
                  context,
                  constraints,
                  crossAxisCount,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExpandedOverlayFromConstraints(
    BuildContext context,
    BoxConstraints constraints,
    int crossAxisCount,
  ) {
    final expandedIndex = _localPendingTasks.indexWhere(
      (t) => t.id == expandedTaskId,
    );
    if (expandedIndex == -1) return const SizedBox.shrink();

    final task = _localPendingTasks[expandedIndex];
    final originalIndex = widget.tasks.indexOf(task);
    final isCompleting = _completingTasks[task.id] == true;

    final itemsPerRow = crossAxisCount;
    final row = expandedIndex ~/ itemsPerRow;
    final column = expandedIndex % itemsPerRow;

    final screenWidth = constraints.maxWidth;
    final screenHeight = constraints.maxHeight;

    final double totalHorizontalPadding = 36.0;
    final double totalSpacing = (crossAxisCount - 1) * 12.0;
    final itemWidth =
        (screenWidth - totalHorizontalPadding - totalSpacing) / crossAxisCount;
    final itemHeight = itemWidth / 1.1;

    final leftPos = 18.0 + (column * (itemWidth + 12));
    final topPos = 8.0 + (row * (itemHeight + 12));

    final widthIncrease = itemWidth * _expandAnimation.value * 0.40;
    final heightIncrease = itemHeight * _expandAnimation.value * 0.50;

    final animatedWidth = itemWidth + widthIncrease;
    final animatedHeight = itemHeight + heightIncrease;

    var animatedLeft = leftPos - (widthIncrease / 2);
    var animatedTop =
        topPos - (heightIncrease / 2) - (_expandAnimation.value * 15);

    const double horizontalPadding = 18.0;
    const double verticalPadding = 8.0;

    if (animatedLeft < horizontalPadding) {
      animatedLeft = horizontalPadding;
    }

    if (animatedLeft + animatedWidth > screenWidth - horizontalPadding) {
      animatedLeft = screenWidth - horizontalPadding - animatedWidth;
    }

    if (animatedTop < verticalPadding) {
      animatedTop = verticalPadding;
    }

    if (animatedTop + animatedHeight > screenHeight - verticalPadding) {
      animatedTop = screenHeight - verticalPadding - animatedHeight;
    }

    return Positioned(
      left: animatedLeft,
      top: animatedTop,
      width: animatedWidth,
      height: animatedHeight,
      child: _buildExpandedCardOverlay(
        context,
        task,
        originalIndex,
        isCompleting,
      ),
    );
  }

  Widget _buildExpandedCardOverlay(
    BuildContext context,
    Task task,
    int originalIndex,
    bool isCompleting,
  ) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {},
      child: Transform(
        transform: Matrix4.identity()
          ..scale(1.0 + _expandAnimation.value * 0.05),
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.6),
              width: 2.0,
            ),
          ),

          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: isCompleting
                          ? null
                          : () => _completeTask(task, originalIndex),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isCompleting
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerLow,
                              shape: BoxShape.circle,
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Transform.scale(
                                  scale: 1.0 - _expandAnimation.value,
                                  child: Opacity(
                                    opacity: 1.0 - _expandAnimation.value,
                                    child: widget.buildTaskIcon(task, context),
                                  ),
                                ),

                                Transform.scale(
                                  scale: _expandAnimation.value,
                                  child: Transform.rotate(
                                    angle: _expandAnimation.value * math.pi * 2,
                                    child: Opacity(
                                      opacity: _expandAnimation.value,
                                      child: isCompleting
                                          ? const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : Icon(
                                              Icons.check_circle_outline,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              size: 24,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          AnimatedOpacity(
                            opacity: _showCompleteLabel ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                            child: Text(
                              'Mark as complete',
                              style: GoogleFonts.gabarito(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    GestureDetector(
                      onTap: () => _toggleExpand(task.id),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),

                Expanded(
                  child: AnimatedOpacity(
                    opacity: _expandAnimation.value,

                    duration: const Duration(milliseconds: 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          task.name,
                          style: GoogleFonts.gabarito(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        _buildExpandedDetails(task, context, originalIndex),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedDetails(
    Task task,
    BuildContext context,
    int originalIndex,
  ) {
    final theme = Theme.of(context);

    Widget details;
    if (task.type == "bad") {
      details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                "${_capitalize(task.type)} (${_capitalize(task.intensity)})",
                style: GoogleFonts.gabarito(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
          if (task.taskCategory == 'timed' && task.durationMinutes != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: theme.colorScheme.error.withOpacity(0.8),
                ),
                const SizedBox(width: 4),
                Text(
                  "Timed (${task.durationMinutes} min)",
                  style: GoogleFonts.gabarito(
                    fontSize: 13,
                    color: theme.colorScheme.error.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    } else if (task.taskCategory == 'timed' && task.durationMinutes != null) {
      details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                _capitalize(task.intensity),
                style: GoogleFonts.gabarito(
                  fontSize: 15,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.timer_outlined,
                size: 16,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 4),
              Text(
                "Timed (${task.durationMinutes} min)",
                style: GoogleFonts.gabarito(
                  fontSize: 13,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _capitalize(task.intensity),
                style: GoogleFonts.gabarito(
                  fontSize: 15,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                task.isImageVerifiable
                    ? Icons.camera_alt_outlined
                    : Icons.check_circle_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                task.isImageVerifiable ? "Photo Verification" : "Honor System",
                style: GoogleFonts.gabarito(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        details,
        const SizedBox(height: 12),
        TextButton.icon(
          style: TextButton.styleFrom(
            backgroundColor: theme.colorScheme.tertiaryContainer.withOpacity(
              0.6,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: Icon(
            Icons.flag_outlined,
            size: 18,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          label: Text(
            "Flag as Bad",
            style: GoogleFonts.gabarito(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          onPressed: () async {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final textColor = isDark ? Colors.white : Colors.black87;
            final bgColor = Theme.of(context).colorScheme.surface;

            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: bgColor,
                title: Text(
                  "Mark Task as Bad",
                  style: TextStyle(color: textColor),
                ),
                content: Text(
                  "If this is a bad task, you can mark it as one and lose aura whenever you do it.",
                  style: TextStyle(color: textColor),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    child: const Text("Cancel"),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    child: const Text("Mark as Bad"),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              try {
                await widget.apiService.markTaskAsBad(task.id);
                widget.onTaskCompleted();
                _toggleExpand(task.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Task marked as bad.'),
                    backgroundColor: theme.colorScheme.error,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to mark as bad: $e'),
                    backgroundColor: theme.colorScheme.error,
                  ),
                );
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildTaskCardItem(
    BuildContext context,
    Task task,
    int originalIndex,
    bool isExpanded,
    bool isCompleting,
    BoxConstraints constraints,
    int index,
  ) {
    const int maxTitleChars = 30;
    final String displayTitle = task.name.length > maxTitleChars && !isExpanded
        ? '${task.name.substring(0, maxTitleChars)}...'
        : task.name;

    return GestureDetector(
      onTap: () {
        if (task.taskCategory == "timed" &&
            task.type == "good" &&
            task.status == "pending") {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TimerPage(
                task: task,
                apiService: widget.apiService,
                onTaskCompleted: widget.onTaskCompleted,
              ),
            ),
          );
        } else if (isExpanded) {
          _toggleExpand(task.id);
        } else {
          _toggleExpand(task.id);
        }
      },
      onLongPress: () => widget.onDeleteTask(originalIndex),
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
            widget.buildTaskIcon(task, context),
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

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
