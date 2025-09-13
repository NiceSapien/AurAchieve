import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../api_service.dart';
import '../widgets/dynamic_color_svg.dart';

class SocialMediaBlockerScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onChallengeCompleted;
  const SocialMediaBlockerScreen({
    super.key,
    required this.apiService,
    required this.onChallengeCompleted,
  });

  @override
  State<SocialMediaBlockerScreen> createState() =>
      _SocialMediaBlockerScreenState();
}

class _SocialMediaBlockerScreenState extends State<SocialMediaBlockerScreen>
    with AutomaticKeepAliveClientMixin {
  final PageController _pageController = PageController();
  late ConfettiController _confettiController;
  final TextEditingController _durationController = TextEditingController(
    text: '7',
  );
  int _currentPage = 0;
  bool _isLoading = true;
  bool _isSetupComplete = false;
  bool _isChallengeFinished = false;
  bool _isTimeUp = false;
  bool _isCompleting = false;
  bool _isPasswordVisible = false;

  String? _generatedPassword;
  String? _finishedPassword;
  DateTime? _timeoutDate;
  DateTime? _setupDate;
  int? _blockerDays = 7;
  tz.TZDateTime? _calculatedEndDate;
  String? _durationErrorText;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    _loadBlockerState();
    _calculateInitialEndDate();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _calculateInitialEndDate() {
    if (_blockerDays == null || _blockerDays! <= 0) {
      _calculatedEndDate = null;
      return;
    }
    final serverTimeZone = tz.getLocation('Asia/Kolkata');
    final nowOnServer = tz.TZDateTime.now(serverTimeZone);
    final targetDate = nowOnServer.add(Duration(days: _blockerDays!));
    final endDateOnServer = tz.TZDateTime(
      serverTimeZone,
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    final finalEndDate = tz.TZDateTime.from(endDateOnServer, tz.local);
    _calculatedEndDate = finalEndDate;
  }

  Future<void> _loadBlockerState() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final isFinished = prefs.getBool('sm_blocker_is_finished') ?? false;

    if (isFinished) {
      setState(() {
        _isChallengeFinished = true;
        _finishedPassword = prefs.getString('sm_blocker_finished_password');
        _isLoading = false;
      });
      return;
    }

    try {
      final data = await widget.apiService.getSocialBlockerData();

      if (data != null &&
          data.containsKey('socialEnd') &&
          data.containsKey('socialStart')) {
        _timeoutDate = DateTime.parse(data['socialEnd']);
        _setupDate = DateTime.parse(data['socialStart']);
        final activePassword = data['socialPassword'] as String?;

        final isTimeUp = DateTime.now().isAfter(_timeoutDate!);

        setState(() {
          _isSetupComplete = true;
          _isTimeUp = isTimeUp;
          _generatedPassword = activePassword;
          _isLoading = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _isSetupComplete = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load blocker data: $e')),
        );
        setState(() {
          _isSetupComplete = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _completeBlocker() async {
    if (_isCompleting || _isChallengeFinished) return;

    print("SOCIAL_BLOCKER: Completing challenge...");
    setState(() => _isCompleting = true);

    try {
      final result = await widget.apiService.completeSocialBlocker();
      final auraGained = result['aura'] ?? 15;
      final finishedPassword = result['socialPassword'] as String?;

      if (finishedPassword == null) {
        throw Exception("Password not received from server on completion.");
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sm_blocker_is_finished', true);
      await prefs.setString('sm_blocker_finished_password', finishedPassword);

      if (mounted) {
        widget.onChallengeCompleted();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Congratulations! You have gained $auraGained aura.'),
            backgroundColor: Colors.green,
          ),
        );
        _confettiController.play();

        setState(() {
          _isChallengeFinished = true;
          _finishedPassword = finishedPassword;
          _isCompleting = false;
        });
      }
    } catch (e) {
      print("SOCIAL_BLOCKER: Error completing challenge: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error completing challenge: $e'),
            backgroundColor: Colors.red,
          ),
        );

        setState(() => _isCompleting = false);
      }
    }
  }

  Future<void> _setupBlocker() async {
    print("SOCIAL_BLOCKER: _setupBlocker function has been called.");
    if (_blockerDays == null || _generatedPassword == null) {
      print("SOCIAL_BLOCKER: Aborting setup, days or password is null.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.apiService.setupSocialBlocker(
        socialEndDays: _blockerDays!,
        socialPassword: _generatedPassword!,
      );

      final serverTimeZone = tz.getLocation('Asia/Kolkata');
      final nowOnServer = tz.TZDateTime.now(serverTimeZone);
      final setupTime = nowOnServer.toLocal();

      final targetDate = nowOnServer.add(Duration(days: _blockerDays!));
      final endDateOnServer = tz.TZDateTime(
        serverTimeZone,
        targetDate.year,
        targetDate.month,
        targetDate.day,
      );
      final timeoutDate = endDateOnServer.toLocal();

      setState(() {
        _isSetupComplete = true;
        _isTimeUp = false;
        _setupDate = setupTime;
        _timeoutDate = timeoutDate;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to setup blocker: $e')));
    }
  }

  Future<void> _showRestartDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final textColor = Theme.of(context).colorScheme.onSurface;
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'Start New Challenge?',
            style: TextStyle(color: textColor),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'Please copy your current password before starting a new challenge. It will be permanently replaced and cannot be recovered.',
                  style: TextStyle(color: textColor),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            FilledButton(
              child: const Text('Start New'),
              onPressed: () {
                Navigator.of(context).pop();
                _resetBlocker();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _resetBlocker() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sm_blocker_is_finished');
    await prefs.remove('sm_blocker_finished_password');

    setState(() {
      _isSetupComplete = false;
      _isChallengeFinished = false;
      _isTimeUp = false;
      _generatedPassword = null;
      _finishedPassword = null;
      _timeoutDate = null;
      _setupDate = null;
      _blockerDays = 7;
      _durationController.text = '7';
      _calculateInitialEndDate();
      _currentPage = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
  }

  void _generatePassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()';
    final random = Random.secure();
    setState(() {
      _generatedPassword = String.fromCharCodes(
        Iterable.generate(
          14,
          (_) => chars.codeUnitAt(random.nextInt(chars.length)),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    super.build(context);

    Widget body;
    if (_isChallengeFinished) {
      body = _buildFinishedView();
    } else {
      body = _isSetupComplete ? _buildProgressView() : _buildOnboardingView();
    }

    return Scaffold(body: body);
  }

  Widget _buildOnboardingView() {
    final features = [
      {
        'svg': 'assets/img/social.svg',
        'title': 'Welcome to Social Media Blocker!',
        'desc':
            'This effective social media blocker allows you to remain consistent with your work.',
      },
      {
        'svg': 'assets/img/password.svg',
        'title': 'We\'ll give you a new password',
        'desc':
            'You have to change the password of your social media accounts to what we give and log out.',
      },
      {
        'svg': 'assets/img/timeout.svg',
        'title': 'You\'ll set a timeout',
        'desc':
            "You'll let us know how many days you want to stay away from social media. We'll give you aura and your password after these days are over.",
      },
    ];

    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (page) => setState(() => _currentPage = page),
            children: [
              _buildFeaturePage(
                features[0]['svg']!,
                features[0]['title']!,
                features[0]['desc']!,
              ),
              _buildFeaturePage(
                features[1]['svg']!,
                features[1]['title']!,
                features[1]['desc']!,
              ),
              _buildFeaturePage(
                features[2]['svg']!,
                features[2]['title']!,
                features[2]['desc']!,
              ),
              _buildDurationPickerPage(),
              _buildPasswordPage(),
            ],
          ),
        ),
        SafeArea(top: false, child: _buildNavigationControls()),
      ],
    );
  }

  Widget _buildFeaturePage(String asset, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 240,
              child: DynamicColorSvg(
                assetName: asset,
                color: Theme.of(context).colorScheme.primary,
              ),
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
      ),
    );
  }

  Widget _buildDurationPickerPage() {
    int auraGain = (_blockerDays ?? 0) * 15;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Set a duration',
            style: GoogleFonts.gabarito(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'For how many days do you want to block social media?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _durationController,
            onChanged: (value) {
              final days = int.tryParse(value);
              setState(() {
                _blockerDays = days;
                if (days != null) {
                  if (days > 365) {
                    _durationErrorText = 'Maximum 365 days';
                    _calculatedEndDate = null;
                  } else if (days > 0) {
                    _durationErrorText = null;
                    final serverTimeZone = tz.getLocation('Asia/Kolkata');
                    final nowOnServer = tz.TZDateTime.now(serverTimeZone);
                    final targetDate = nowOnServer.add(Duration(days: days));
                    final endDateOnServer = tz.TZDateTime(
                      serverTimeZone,
                      targetDate.year,
                      targetDate.month,
                      targetDate.day,
                    );
                    final finalEndDate = tz.TZDateTime.from(
                      endDateOnServer,
                      tz.local,
                    );
                    _calculatedEndDate = finalEndDate;
                  } else {
                    _durationErrorText = null;
                    _calculatedEndDate = null;
                  }
                } else {
                  _durationErrorText = null;
                  _calculatedEndDate = null;
                }
              });
            },
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: GoogleFonts.gabarito(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              border: const UnderlineInputBorder(),
              suffixText: 'days',
              suffixStyle: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              errorText: _durationErrorText,
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if ((_blockerDays ?? 0) > 0 && _durationErrorText == null)
            Text(
              'Approximate aura gain: $auraGain',
              style: GoogleFonts.gabarito(
                fontSize: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          if (_calculatedEndDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Builder(
                builder: (context) {
                  final dt = _calculatedEndDate!;
                  final localDateTime = DateTime(
                    dt.year,
                    dt.month,
                    dt.day,
                    dt.hour,
                    dt.minute,
                  );
                  return Text(
                    'Access will be restored on:\n${DateFormat.yMMMMEEEEd().add_jm().format(localDateTime)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPasswordPage() {
    if (_generatedPassword == null) {
      _generatePassword();
    }
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.password_rounded, size: 64),
          const SizedBox(height: 24),
          Text(
            'Here\'s your password',
            style: GoogleFonts.gabarito(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Change your social media password to this and log out. Once your timeout ends, we'll show you the password again.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _generatedPassword ?? '',
              style: GoogleFonts.sourceCodePro(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy Password'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _generatedPassword!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Password copied to clipboard!')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationControls() {
    return Padding(
      padding: const EdgeInsets.only(right: 12.0, left: 12, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _currentPage > 0
              ? TextButton(
                  onPressed: () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.ease,
                    );
                  },
                  child: const Text('Back'),
                )
              : const SizedBox(width: 60),
          FilledButton(
            onPressed: () {
              if (_currentPage == 3) {
                if (_blockerDays == null || _blockerDays! <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid number of days.'),
                    ),
                  );
                  return;
                }
                if (_blockerDays! > 365) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Duration cannot exceed 365 days.'),
                    ),
                  );
                  return;
                }
              }

              if (_currentPage < 4) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.ease,
                );
              } else {
                _setupBlocker();
              }
            },
            child: Text(_currentPage < 4 ? 'Next' : 'Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressView() {
    double progress = 0.0;
    String timeRemaining = "Time's up!";

    if (!_isTimeUp && _setupDate != null && _timeoutDate != null) {
      final totalDuration = _timeoutDate!.difference(_setupDate!).inSeconds;
      if (totalDuration > 0) {
        final elapsedDuration = DateTime.now()
            .difference(_setupDate!)
            .inSeconds;
        progress = (elapsedDuration / totalDuration).clamp(0.0, 1.0);
      }

      final remaining = _timeoutDate!.difference(DateTime.now());
      if (remaining.isNegative) {
        timeRemaining = "Time's up!";
      } else {
        final d = remaining.inDays;
        final h = remaining.inHours % 24;
        final m = remaining.inMinutes % 60;
        timeRemaining =
            '${d}d ${h}h ${m}m remaining until your social media password is shown';
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: _isTimeUp
            ? _buildCongratulationsView()
            : _buildInProgressView(progress, timeRemaining),
      ),
    );
  }

  Widget _buildInProgressView(double progress, String timeRemaining) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 12,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
              Center(
                child: Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.gabarito(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text(
          timeRemaining,
          textAlign: TextAlign.center,
          style: GoogleFonts.gabarito(
            fontSize: 22,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildCongratulationsView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.celebration_rounded, size: 64, color: Colors.amber),
        const SizedBox(height: 24),
        Text(
          "Congratulations!",
          style: GoogleFonts.gabarito(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "You've completed the challenge. Press Finish to get your password and aura.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (_isCompleting)
          const CircularProgressIndicator()
        else
          FilledButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Finish Challenge'),
            onPressed: _completeBlocker,
          ),
      ],
    );
  }

  Widget _buildFinishedView() {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.celebration_rounded,
                    size: 64,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Congratulations!",
                    style: GoogleFonts.gabarito(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "You've completed the challenge. Here is your password:",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _isPasswordVisible
                                  ? (_finishedPassword ?? "Loading...")
                                  : '∗ ∗ ∗ ∗ ∗ ∗ ∗',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.sourceCodePro(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Password'),
                    onPressed: _finishedPassword == null
                        ? null
                        : () {
                            Clipboard.setData(
                              ClipboardData(text: _finishedPassword!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Password copied!')),
                            );
                          },
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Finish & Start New'),
                    onPressed: _showRestartDialog,
                  ),
                ],
              ),
            ),
          ),
        ),
        ConfettiWidget(
          confettiController: _confettiController,
          blastDirectionality: BlastDirectionality.explosive,
          shouldLoop: false,
          colors: const [
            Colors.green,
            Colors.blue,
            Colors.pink,
            Colors.orange,
            Colors.purple,
          ],
        ),
      ],
    );
  }
}
