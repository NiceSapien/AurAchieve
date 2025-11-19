import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

enum TimerKind { stopwatch, timer, pomodoro }

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> with WidgetsBindingObserver {
  final TextEditingController _timerMinutesController = TextEditingController(
    text: '25',
  );
  TimerKind _mode = TimerKind.stopwatch;

  Timer? _timer;
  DateTime? _lastTickTime;
  DateTime _lastInteractionTime = DateTime.now();

  bool _isRunning = false;
  bool _isPaused = false;

  int _elapsedMs = 0;
  List<int> _laps = [];

  int _timerTargetMs = 25 * 60 * 1000;

  int _pomoWorkMs = 25 * 60 * 1000;
  int _pomoBreakMs = 5 * 60 * 1000;
  bool _pomoIsWork = true;
  int _pomoSessionElapsedMs = 0;
  int _pomoCyclesTotal = 4;
  int _pomoCurrentCycle = 0;
  String _pomoTitle = '';

  bool _blackoutShown = false;
  final ValueNotifier<int> _tickNotifier = ValueNotifier<int>(0);

  bool _immersiveMode = true;
  bool _soundVibration = true;

  IconData _pomoIcon = Icons.work_outline_rounded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastTickTime = DateTime.now();
      if (_isRunning && !_isPaused) {
        // Ensure timer is running
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(milliseconds: 16), _onTick);
      }
    } else if (state == AppLifecycleState.paused) {
      // We don't cancel the timer here to allow it to potentially run a bit longer
      // or rely on the OS to suspend it.
      // When we resume, we'll calculate the diff.
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _immersiveMode = prefs.getBool('timer_immersive') ?? true;
      _soundVibration = prefs.getBool('timer_sound_vibration') ?? true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    WakelockPlus.disable();
    _tickNotifier.dispose();
    _timerMinutesController.dispose();
    super.dispose();
  }

  void _start() {
    if (_isRunning && !_isPaused) return;
    setState(() {
      _isRunning = true;
      _isPaused = false;
    });
    WakelockPlus.enable();

    _lastTickTime = DateTime.now();
    _lastInteractionTime = DateTime.now();
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(milliseconds: 16), _onTick);
  }

  void _onTick(Timer timer) {
    final now = DateTime.now();
    final diff = now.difference(_lastTickTime ?? now).inMilliseconds;
    _lastTickTime = now;

    if (!_isPaused) {
      _tickLogic(diff);
      _checkBlackout();
    }
  }

  void _tickLogic(int deltaMs) {
    switch (_mode) {
      case TimerKind.stopwatch:
        _elapsedMs += deltaMs;
        break;
      case TimerKind.timer:
        final next = _elapsedMs + deltaMs;
        if (next >= _timerTargetMs) {
          _elapsedMs = _timerTargetMs;
          _stop();
        } else {
          _elapsedMs = next;
        }
        break;
      case TimerKind.pomodoro:
        final target = _pomoIsWork ? _pomoWorkMs : _pomoBreakMs;
        final next = _pomoSessionElapsedMs + deltaMs;
        if (next >= target) {
          _pomoSessionElapsedMs = target;
          _handlePomodoroPhaseFinish();
        } else {
          _pomoSessionElapsedMs = next;
        }
        break;
    }
    if (_blackoutShown) {
      _tickNotifier.value++;
    }
    if (mounted) setState(() {});
  }

  void _stop() {
    _isRunning = false;
    _isPaused = false;
    _timer?.cancel();
    WakelockPlus.disable();
  }

  void _handlePomodoroPhaseFinish() {
    _timer?.cancel();
    WakelockPlus.enable();

    if (_soundVibration) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);
    }

    _showTransitionDialog();
  }

  Future<void> _showTransitionDialog() async {
    if (_blackoutShown) {
      setState(() => _blackoutShown = false);
      Navigator.of(context).pop();
      _restoreSystemUI();
    }

    int countdown = 10;
    Timer? countdownTimer;
    bool isPaused = false;

    final nextTitle = _pomoIsWork
        ? 'Break Time!'
        : '${_pomoTitle.isEmpty ? "Work" : _pomoTitle} Time!';
    final nextPhaseName = _pomoIsWork ? 'Break' : 'Work';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (
              timer,
            ) {
              if (!isPaused) {
                if (countdown > 0) {
                  setStateDialog(() => countdown--);
                } else {
                  timer.cancel();
                  Navigator.of(context).pop();
                }
              }
            });

            return AlertDialog(
              title: Text(
                nextTitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Starting in...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$countdown',
                    style: GoogleFonts.gabarito(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Next: $nextPhaseName',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setStateDialog(() {
                      isPaused = !isPaused;
                    });
                  },
                  child: Text(isPaused ? 'Resume' : 'Pause'),
                ),
                FilledButton(
                  onPressed: () {
                    countdownTimer?.cancel();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Start Now'),
                ),
              ],
            );
          },
        );
      },
    );

    countdownTimer?.cancel();

    if (_pomoIsWork) {
      setState(() {
        _pomoIsWork = false;
        _pomoSessionElapsedMs = 0;
      });
    } else {
      setState(() {
        _pomoCurrentCycle += 1;
        if (_pomoCurrentCycle >= _pomoCyclesTotal) {
          _stop();
          return;
        } else {
          _pomoIsWork = true;
          _pomoSessionElapsedMs = 0;
        }
      });
    }

    _lastTickTime = DateTime.now();
    _lastInteractionTime = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 16), _onTick);
  }

  void _pause() {
    if (_isRunning && !_isPaused) {
      setState(() => _isPaused = true);
      _timer?.cancel();
      WakelockPlus.enable();
    }
  }

  void _resume() {
    if (_isRunning && _isPaused) {
      setState(() => _isPaused = false);
      _lastTickTime = DateTime.now();
      _lastInteractionTime = DateTime.now();
      _timer = Timer.periodic(const Duration(milliseconds: 16), _onTick);
    }
  }

  void _lap() {
    if (_mode == TimerKind.stopwatch && _isRunning && !_isPaused) {
      setState(() {
        _laps.insert(0, _elapsedMs);
      });
    }
  }

  void _reset() {
    _timer?.cancel();
    WakelockPlus.disable();
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _elapsedMs = 0;
      _laps.clear();
      _pomoSessionElapsedMs = 0;
      _pomoIsWork = true;
      _pomoCurrentCycle = 0;
      _blackoutShown = false;
    });
  }

  void _checkBlackout() {
    final now = DateTime.now();
    final inactivityMs = now.difference(_lastInteractionTime).inMilliseconds;

    if (!_blackoutShown && _isRunning && !_isPaused && inactivityMs >= 20000) {
      _blackoutShown = true;
      _showBlackoutOverlay();
    }
  }

  void _showBlackoutOverlay() {
    if (_immersiveMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Blackout',
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _lastInteractionTime = DateTime.now();
            setState(() {
              _blackoutShown = false;
            });
            _restoreSystemUI();
            Navigator.of(context).pop();
          },
          child: Material(
            color: Colors.transparent,
            child: ValueListenableBuilder<int>(
              valueListenable: _tickNotifier,
              builder: (context, _, __) {
                return Center(
                  child: Text(
                    _currentTimeText(),
                    style: GoogleFonts.gabarito(
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _restoreSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  String _currentTimeText() {
    switch (_mode) {
      case TimerKind.stopwatch:
        return _formatHMS(_elapsedMs, includeMillis: true);
      case TimerKind.timer:
        final remaining = (_timerTargetMs - _elapsedMs).clamp(
          0,
          _timerTargetMs,
        );
        return _formatHMS(remaining);
      case TimerKind.pomodoro:
        final target = _pomoIsWork ? _pomoWorkMs : _pomoBreakMs;
        final remaining = (target - _pomoSessionElapsedMs).clamp(0, target);
        return _formatHMS(remaining);
    }
  }

  String _formatHMS(int ms, {bool includeMillis = false}) {
    final totalSeconds = ms ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');

    if (includeMillis) {
      final millis = (ms % 1000) ~/ 10;
      final mms = millis.toString().padLeft(2, '0');
      return hours > 0 ? '$hh:$mm:$ss.$mms' : '$mm:$ss.$mms';
    }

    return hours > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  }

  double? _progressValue() {
    switch (_mode) {
      case TimerKind.stopwatch:
        return null;
      case TimerKind.timer:
        if (_timerTargetMs <= 0) return 0.0;
        return (_elapsedMs / _timerTargetMs).clamp(0.0, 1.0);
      case TimerKind.pomodoro:
        final target = _pomoIsWork ? _pomoWorkMs : _pomoBreakMs;
        if (target <= 0) return 0.0;
        return (_pomoSessionElapsedMs / target).clamp(0.0, 1.0);
    }
  }

  Future<void> _openModeSheet() async {
    final theme = Theme.of(context);
    TimerKind selected = _mode;
    final timerCtrl = TextEditingController(
      text: (_timerTargetMs ~/ 60000).toString(),
    );
    final workCtrl = TextEditingController(
      text: (_pomoWorkMs ~/ 60000).toString(),
    );
    final breakCtrl = TextEditingController(
      text: (_pomoBreakMs ~/ 60000).toString(),
    );
    final cyclesCtrl = TextEditingController(text: _pomoCyclesTotal.toString());
    final titleCtrl = TextEditingController(text: _pomoTitle);
    IconData selectedIcon = _pomoIcon;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final onSurface = theme.colorScheme.onSurface;
        final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return StatefulBuilder(
                  builder: (context, setStateSheet) {
                    return Column(
                      children: [
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            width: 48,
                            height: 5,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'Timer Mode',
                            style: GoogleFonts.gabarito(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        Expanded(
                          child: SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color:
                                        theme.colorScheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: Row(
                                    children: [
                                      for (final kind in TimerKind.values)
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => setStateSheet(
                                              () => selected = kind,
                                            ),
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 200,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: selected == kind
                                                    ? theme.colorScheme.primary
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                kind.name[0].toUpperCase() +
                                                    kind.name.substring(1),
                                                style: GoogleFonts.gabarito(
                                                  fontWeight: FontWeight.w600,
                                                  color: selected == kind
                                                      ? theme
                                                            .colorScheme
                                                            .onPrimary
                                                      : onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 32),

                                if (selected == TimerKind.stopwatch)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Text(
                                        'Just hit play to start counting up!',
                                        style: TextStyle(
                                          color: onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),

                                if (selected == TimerKind.timer)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Duration',
                                        style: GoogleFonts.gabarito(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: timerCtrl,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        style: TextStyle(color: onSurface),
                                        decoration: InputDecoration(
                                          labelText: 'Minutes',
                                          filled: true,
                                          fillColor: theme
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withOpacity(0.3),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          suffixText: 'min',
                                        ),
                                      ),
                                    ],
                                  ),

                                if (selected == TimerKind.pomodoro)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Session Details',
                                        style: GoogleFonts.gabarito(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: workCtrl,
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                              ],
                                              style: TextStyle(
                                                color: onSurface,
                                              ),
                                              decoration: InputDecoration(
                                                labelText: 'Work',
                                                filled: true,
                                                fillColor: theme
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                                    .withOpacity(0.3),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                suffixText: 'min',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: TextField(
                                              controller: breakCtrl,
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                              ],
                                              style: TextStyle(
                                                color: onSurface,
                                              ),
                                              decoration: InputDecoration(
                                                labelText: 'Break',
                                                filled: true,
                                                fillColor: theme
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                                    .withOpacity(0.3),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                suffixText: 'min',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: cyclesCtrl,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        style: TextStyle(color: onSurface),
                                        decoration: InputDecoration(
                                          labelText: 'Cycles',
                                          helperText:
                                              'Number of work sessions (max 7)',
                                          filled: true,
                                          fillColor: theme
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withOpacity(0.3),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Text(
                                        'Task Info',
                                        style: GoogleFonts.gabarito(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: titleCtrl,
                                        textInputAction: TextInputAction.done,
                                        style: TextStyle(color: onSurface),
                                        decoration: InputDecoration(
                                          labelText: 'What are you working on?',
                                          filled: true,
                                          fillColor: theme
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withOpacity(0.3),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          prefixIcon: Icon(selectedIcon),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children:
                                              [
                                                Icons.work_outline_rounded,
                                                Icons.code_rounded,
                                                Icons.book_rounded,
                                                Icons.fitness_center_rounded,
                                                Icons.brush_rounded,
                                                Icons.music_note_rounded,
                                                Icons.science_rounded,
                                                Icons.laptop_chromebook_rounded,
                                              ].map((icon) {
                                                final isSelected =
                                                    selectedIcon == icon;
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 12,
                                                      ),
                                                  child: InkWell(
                                                    onTap: () => setStateSheet(
                                                      () => selectedIcon = icon,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            12,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: isSelected
                                                            ? theme
                                                                  .colorScheme
                                                                  .primaryContainer
                                                            : theme
                                                                  .colorScheme
                                                                  .surfaceContainerHigh,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                        border: isSelected
                                                            ? Border.all(
                                                                color: theme
                                                                    .colorScheme
                                                                    .primary,
                                                                width: 2,
                                                              )
                                                            : null,
                                                      ),
                                                      child: Icon(
                                                        icon,
                                                        color: isSelected
                                                            ? theme
                                                                  .colorScheme
                                                                  .onPrimaryContainer
                                                            : theme
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                        ),
                                      ),
                                    ],
                                  ),

                                if (error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(
                                      error!,
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ),

                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    if (selected == TimerKind.timer) {
                                      final m = int.tryParse(timerCtrl.text);
                                      if (m == null || m <= 0 || m > 720) {
                                        setStateSheet(
                                          () => error = 'Enter 1–720 minutes',
                                        );
                                        return;
                                      }
                                    }
                                    if (selected == TimerKind.pomodoro) {
                                      final w = int.tryParse(workCtrl.text);
                                      final b = int.tryParse(breakCtrl.text);
                                      final c = int.tryParse(cyclesCtrl.text);
                                      if (w == null ||
                                          b == null ||
                                          c == null ||
                                          w <= 0 ||
                                          b <= 0 ||
                                          c <= 0 ||
                                          w > 720 ||
                                          b > 720 ||
                                          c > 7) {
                                        setStateSheet(
                                          () => error =
                                              'Enter valid work/break (1–720) and cycles (1–7)',
                                        );
                                        return;
                                      }
                                    }
                                    setState(() {
                                      _mode = selected;
                                      if (selected == TimerKind.timer) {
                                        final m = int.parse(timerCtrl.text);
                                        _timerTargetMs = m * 60 * 1000;
                                        _elapsedMs = 0;
                                      } else if (selected ==
                                          TimerKind.pomodoro) {
                                        final w = int.parse(workCtrl.text);
                                        final b = int.parse(breakCtrl.text);
                                        final c = int.parse(cyclesCtrl.text);
                                        _pomoWorkMs = w * 60 * 1000;
                                        _pomoBreakMs = b * 60 * 1000;
                                        _pomoCyclesTotal = c.clamp(1, 7);
                                        _pomoTitle = titleCtrl.text.trim();
                                        _pomoIcon = selectedIcon;
                                        _pomoSessionElapsedMs = 0;
                                        _pomoIsWork = true;
                                        _pomoCurrentCycle = 0;
                                      } else {
                                        _elapsedMs = 0;
                                      }
                                    });
                                    Navigator.of(ctx).pop();
                                  },
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text('Apply'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openTimelineSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Session Timeline',
                  style: GoogleFonts.gabarito(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _pomoCyclesTotal * 2,
                    itemBuilder: (ctx, index) {
                      final cycleIndex = index ~/ 2;
                      final isWork = index % 2 == 0;

                      bool isCompleted = false;
                      bool isCurrent = false;

                      if (cycleIndex < _pomoCurrentCycle) {
                        isCompleted = true;
                      } else if (cycleIndex == _pomoCurrentCycle) {
                        if (isWork) {
                          if (_pomoIsWork)
                            isCurrent = true;
                          else
                            isCompleted = true;
                        } else {
                          if (!_pomoIsWork)
                            isCurrent = true;
                          else
                            isCompleted = false;
                        }
                      }

                      final color = isWork
                          ? theme.colorScheme.primary
                          : theme.colorScheme.tertiary;

                      return IntrinsicHeight(
                        child: Row(
                          children: [
                            Column(
                              children: [
                                Container(
                                  width: 2,
                                  height: 24,
                                  color: index == 0
                                      ? Colors.transparent
                                      : theme.colorScheme.outlineVariant
                                            .withOpacity(0.5),
                                ),
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isCompleted
                                        ? color
                                        : (isCurrent
                                              ? color
                                              : Colors.transparent),
                                    border: Border.all(
                                      color: isCompleted || isCurrent
                                          ? color
                                          : theme.colorScheme.outlineVariant,
                                      width: 2,
                                    ),
                                  ),
                                  child: isCompleted
                                      ? Icon(
                                          Icons.check,
                                          size: 10,
                                          color: theme.colorScheme.surface,
                                        )
                                      : null,
                                ),
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    color: index == (_pomoCyclesTotal * 2 - 1)
                                        ? Colors.transparent
                                        : theme.colorScheme.outlineVariant
                                              .withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isWork
                                          ? 'Work Session ${cycleIndex + 1}'
                                          : 'Break',
                                      style: GoogleFonts.gabarito(
                                        fontWeight: isCurrent
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isCurrent
                                            ? theme.colorScheme.onSurface
                                            : theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                      ),
                                    ),
                                    if (isCurrent)
                                      Text(
                                        'Current Phase',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: color,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Text(
                              isWork
                                  ? '${_pomoWorkMs ~/ 60000} min'
                                  : '${_pomoBreakMs ~/ 60000} min',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPomodoroDots(ThemeData theme) {
    final track = theme.colorScheme.outlineVariant.withOpacity(0.35);
    final activeWorkColor = theme.colorScheme.primaryContainer;
    final breakColor = theme.colorScheme.tertiary;
    final doneColor = Colors.green;
    final small = 10.0;
    final big = 16.0;
    final spacing = 10.0;

    List<Widget> dots = [];
    for (int i = 0; i < _pomoCyclesTotal; i++) {
      final isCompleted = i < _pomoCurrentCycle;
      final isActive =
          i == _pomoCurrentCycle && _pomoCurrentCycle < _pomoCyclesTotal;
      Color fillColor;
      _DotFill fillState;

      if (isCompleted) {
        fillColor = doneColor;
        fillState = _DotFill.full;
        dots.add(
          _HalfFillDot(
            size: small,
            color: fillColor,
            track: track,
            fill: fillState,
          ),
        );
      } else if (isActive) {
        fillColor = _pomoIsWork ? activeWorkColor : breakColor;
        if (_pomoIsWork) {
          fillState = _DotFill.empty;
        } else {
          fillState = _DotFill.half;
        }
        dots.add(
          _HalfFillDot(
            size: big,
            color: fillColor,
            track: track,
            fill: fillState,
          ),
        );
      } else {
        fillColor = track;
        fillState = _DotFill.empty;
        dots.add(
          _HalfFillDot(
            size: small,
            color: fillColor,
            track: track,
            fill: fillState,
          ),
        );
      }

      if (i != _pomoCyclesTotal - 1) dots.add(SizedBox(width: spacing));
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: dots);
  }

  double? _remainingRatio() {
    if (_mode == TimerKind.timer) {
      if (_timerTargetMs <= 0) return 0;
      final used = (_elapsedMs / _timerTargetMs).clamp(0.0, 1.0);
      return 1 - used;
    }
    return _progressValue();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = _remainingRatio();

    final isBreak = _mode == TimerKind.pomodoro && !_pomoIsWork;
    final activeColor = isBreak
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    final onActiveColor = isBreak
        ? theme.colorScheme.onTertiary
        : theme.colorScheme.onPrimary;
    final ringColor = activeColor;
    final trackColor = theme.colorScheme.surfaceContainerHighest;

    final timeText = _currentTimeText();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Listener(
        onPointerDown: (_) => _lastInteractionTime = DateTime.now(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_mode == TimerKind.pomodoro) ...[
                    InkWell(
                      onTap: _openTimelineSheet,
                      borderRadius: BorderRadius.circular(32),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _pomoIsWork
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(32),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _pomoIsWork ? _pomoIcon : Icons.coffee_rounded,
                              size: 18,
                              color: _pomoIsWork
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _pomoIsWork
                                  ? (_pomoTitle.isNotEmpty
                                        ? _pomoTitle
                                        : 'Focus')
                                  : 'Break',
                              style: GoogleFonts.gabarito(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _pomoIsWork
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onTertiaryContainer,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: _pomoIsWork
                                  ? theme.colorScheme.onPrimaryContainer
                                        .withOpacity(0.5)
                                  : theme.colorScheme.onTertiaryContainer
                                        .withOpacity(0.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildPomodoroDots(theme),
                    const SizedBox(height: 40),
                  ],

                  SizedBox(
                    width: 300,
                    height: 300,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (ratio != null)
                          CustomPaint(
                            painter: _RingPainter(
                              value: 1.0,
                              color: trackColor,
                              thickness: 24,
                              rounded: false,
                            ),
                          ),
                        if (ratio != null)
                          CustomPaint(
                            painter: _RingPainter(
                              value: ratio,
                              color: ringColor,
                              thickness: 24,
                              rounded: true,
                            ),
                          ),
                        Center(
                          child: Text(
                            timeText,
                            style: GoogleFonts.gabarito(
                              fontSize: 64,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                              letterSpacing: -1.0,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutQuint,
                        child:
                            (_elapsedMs > 0 ||
                                _pomoSessionElapsedMs > 0 ||
                                _pomoCurrentCycle > 0)
                            ? Padding(
                                padding: const EdgeInsets.only(right: 24),
                                child: FilledButton.tonal(
                                  onPressed: _reset,
                                  style: FilledButton.styleFrom(
                                    fixedSize: const Size(72, 72),
                                    shape: const CircleBorder(),
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Icon(
                                    Icons.stop_rounded,
                                    size: 32,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      SizedBox(
                        width: 96,
                        height: 96,
                        child: GestureDetector(
                          onTap: (!_isRunning || _isPaused)
                              ? (_isRunning ? _resume : _start)
                              : _pause,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutBack,
                            decoration: BoxDecoration(
                              color: activeColor,
                              borderRadius: BorderRadius.circular(
                                (!_isRunning || _isPaused) ? 40 : 24,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.shadow.withOpacity(
                                    0.3,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                transitionBuilder: (child, anim) {
                                  return ScaleTransition(
                                    scale: anim,
                                    child: FadeTransition(
                                      opacity: anim,
                                      child: child,
                                    ),
                                  );
                                },
                                child: Icon(
                                  (!_isRunning || _isPaused)
                                      ? Icons.play_arrow_rounded
                                      : Icons.pause_rounded,
                                  key: ValueKey(!_isRunning || _isPaused),
                                  size: 48,
                                  color: onActiveColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutQuint,
                        child: (_mode == TimerKind.stopwatch && _isRunning && !_isPaused)
                            ? Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: FilledButton.tonal(
                                  onPressed: _lap,
                                  style: FilledButton.styleFrom(
                                    fixedSize: const Size(72, 72),
                                    shape: const CircleBorder(),
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Icon(Icons.flag_rounded, size: 32),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),

                  if (_mode == TimerKind.stopwatch && _laps.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _laps.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: theme.colorScheme.outlineVariant.withOpacity(0.2),
                        ),
                        itemBuilder: (context, index) {
                          final lapTime = _laps[index];
                          final lapNum = _laps.length - index;
                          return ListTile(
                            dense: true,
                            leading: Text(
                              'Lap $lapNum',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: Text(
                              _formatHMS(lapTime, includeMillis: true),
                              style: GoogleFonts.gabarito(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openModeSheet,
        child: const Icon(Icons.tune_rounded),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

enum _DotFill { empty, half, full }

class _HalfFillDot extends StatelessWidget {
  final double size;
  final Color color;
  final Color track;
  final _DotFill fill;

  const _HalfFillDot({
    required this.size,
    required this.color,
    required this.track,
    required this.fill,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _HalfFillDotPainter(color: color, track: track, fill: fill),
    );
  }
}

class _HalfFillDotPainter extends CustomPainter {
  final Color color;
  final Color track;
  final _DotFill fill;

  _HalfFillDotPainter({
    required this.color,
    required this.track,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final trackPaint = Paint()..color = track;
    canvas.drawCircle(center, r, trackPaint);

    if (fill == _DotFill.full) {
      final p = Paint()..color = color;
      canvas.drawCircle(center, r, p);
    } else if (fill == _DotFill.half) {
      final p = Paint()..color = color;
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawArc(rect, -math.pi / 2, math.pi, true, p);
    }
  }

  @override
  bool shouldRepaint(covariant _HalfFillDotPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.track != track ||
        oldDelegate.fill != fill;
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final double thickness;
  final bool rounded;

  _RingPainter({
    required this.value,
    required this.color,
    required this.thickness,
    required this.rounded,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - thickness / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = rounded ? StrokeCap.round : StrokeCap.butt
      ..color = color;

    if (value >= 1.0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi,
        false,
        paint,
      );
    } else if (value > 0.0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        value * 2 * math.pi,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.thickness != thickness ||
        oldDelegate.rounded != rounded;
  }
}
