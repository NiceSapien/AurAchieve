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
  bool _gaveUp = false;
  bool _isOfflineMode = false;

  String? _generatedPassword;
  String? _finishedPassword;
  DateTime? _timeoutDate;
  DateTime? _setupDate;
  int? _blockerDays = 7;
  int? _completedDaysOnFinish;
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
    final isOffline = prefs.getBool('sm_blocker_is_offline') ?? false;

    if (isFinished) {
      setState(() {
        _isChallengeFinished = true;
        _finishedPassword = prefs.getString('sm_blocker_finished_password');
        _gaveUp = prefs.getBool('sm_blocker_gave_up') ?? false;
        _completedDaysOnFinish = prefs.getInt('sm_blocker_completed_days');
        _isOfflineMode = isOffline;
        _isLoading = false;
      });
      return;
    }

    if (isOffline) {
      final setupDateStr = prefs.getString('sm_blocker_setup_date');
      final timeoutDateStr = prefs.getString('sm_blocker_timeout_date');
      if (setupDateStr != null && timeoutDateStr != null) {
        _timeoutDate = DateTime.parse(timeoutDateStr);
        _setupDate = DateTime.parse(setupDateStr);
        final isTimeUp = DateTime.now().isAfter(_timeoutDate!);
        setState(() {
          _isSetupComplete = true;
          _isTimeUp = isTimeUp;
          _isOfflineMode = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isSetupComplete = false;
          _isOfflineMode = false;
          _isLoading = false;
        });
      }
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

    if (_isOfflineMode) {
      final prefs = await SharedPreferences.getInstance();
      final password = prefs.getString('sm_blocker_password');
      final completed = _calculateCompletedDays();

      await prefs.setBool('sm_blocker_is_finished', true);
      await prefs.setString(
        'sm_blocker_finished_password',
        password ?? 'Error',
      );
      await prefs.setBool('sm_blocker_gave_up', false);
      await prefs.setInt('sm_blocker_completed_days', completed);

      setState(() {
        _isChallengeFinished = true;
        _finishedPassword = password;
        _completedDaysOnFinish = completed;
        _gaveUp = false;
        _isCompleting = false;
      });
      _confettiController.play();
      return;
    }

    try {
      final result = await widget.apiService.completeSocialBlocker();
      final auraGained = result['aura'] ?? 15;
      final finishedPassword = result['socialPassword'] as String?;
      final completedDays = result['completedDays'] as int?;

      if (finishedPassword == null) {
        throw Exception("Password not received from server on completion.");
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sm_blocker_is_finished', true);
      await prefs.setString('sm_blocker_finished_password', finishedPassword);
      await prefs.setBool('sm_blocker_gave_up', false);
      if (completedDays != null) {
        await prefs.setInt('sm_blocker_completed_days', completedDays);
      }

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
          _completedDaysOnFinish = completedDays;
          _gaveUp = false;
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

  Future<void> _handleGiveUp() async {
    if (_isCompleting || _isChallengeFinished) return;

    setState(() => _isCompleting = true);

    if (_isOfflineMode) {
      final prefs = await SharedPreferences.getInstance();
      final password = prefs.getString('sm_blocker_password');
      final completed = _calculateCompletedDays();

      await prefs.setBool('sm_blocker_is_finished', true);
      await prefs.setString(
        'sm_blocker_finished_password',
        password ?? 'Error',
      );
      await prefs.setBool('sm_blocker_gave_up', true);
      await prefs.setInt('sm_blocker_completed_days', completed);

      setState(() {
        _isChallengeFinished = true;
        _finishedPassword = password;
        _completedDaysOnFinish = completed;
        _gaveUp = true;
        _isCompleting = false;
      });
      return;
    }

    try {
      final result = await widget.apiService.giveUpSocialBlocker();
      final auraGained = result['aura'] ?? 0;
      final finishedPassword = result['socialPassword'] as String?;
      final completedDays = result['completedDays'] as int?;

      if (finishedPassword == null) {
        throw Exception("Password not received from server on give up.");
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sm_blocker_is_finished', true);
      await prefs.setString('sm_blocker_finished_password', finishedPassword);
      await prefs.setBool('sm_blocker_gave_up', true);
      if (completedDays != null) {
        await prefs.setInt('sm_blocker_completed_days', completedDays);
      }

      if (mounted) {
        widget.onChallengeCompleted();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Challenge ended. You have gained $auraGained aura.'),
            backgroundColor: Colors.orange,
          ),
        );

        setState(() {
          _isChallengeFinished = true;
          _finishedPassword = finishedPassword;
          _completedDaysOnFinish = completedDays;
          _gaveUp = true;
          _isCompleting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error giving up: $e'),
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

    if (_isOfflineMode) {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final timeout = now.add(Duration(days: _blockerDays!));

      await prefs.setBool('sm_blocker_is_offline', true);
      await prefs.setString('sm_blocker_password', _generatedPassword!);
      await prefs.setString('sm_blocker_setup_date', now.toIso8601String());
      await prefs.setString(
        'sm_blocker_timeout_date',
        timeout.toIso8601String(),
      );

      setState(() {
        _isSetupComplete = true;
        _isTimeUp = false;
        _setupDate = now;
        _timeoutDate = timeout;
        _isLoading = false;
      });
      return;
    }

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

  int _calculateCompletedDays() {
    if (_setupDate == null) return 0;
    final today = DateTime.now();
    final start = _setupDate!;

    final startDate = DateTime(start.year, start.month, start.day);
    final todayDate = DateTime(today.year, today.month, today.day);

    final difference = todayDate.difference(startDate).inDays;
    return difference >= 0 ? difference : 0;
  }

  Future<void> _showGiveUpDialog() async {
    final estimatedAura = _calculateCompletedDays() * 10;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Text(
            'Are you sure?',
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'Giving up now will end the challenge. You will get your password back, but you will only receive a fraction of the aura.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Text(
                  'Estimated aura gain: ${_isOfflineMode ? 0 : estimatedAura}',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
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
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _handleGiveUp();
              },
              child: const Text('Give Up'),
            ),
          ],
        );
      },
    );
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

  Future<void> _showContinueDialog() async {
    final TextEditingController daysController = TextEditingController(
      text: '7',
    );
    String? errorText;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final theme = Theme.of(context);
            return AlertDialog(
              backgroundColor: theme.colorScheme.surface,
              title: Text(
                'Continue Challenge?',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    Text(
                      'We will use your current password to start a new challenge immediately. Enter how many days to continue.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: daysController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      autofocus: true,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Days',
                        errorText: errorText,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                  child: const Text('Start'),
                  onPressed: () {
                    final days = int.tryParse(daysController.text);
                    if (days == null || days <= 0) {
                      setStateDialog(() => errorText = 'Invalid days');
                      return;
                    }
                    if (days > 365) {
                      setStateDialog(() => errorText = 'Max 365 days');
                      return;
                    }
                    if (_finishedPassword == null ||
                        _finishedPassword!.isEmpty) {
                      setStateDialog(() => errorText = 'No password available');
                      return;
                    }
                    Navigator.of(context).pop();
                    _continueChallenge(days);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _continueChallenge(int days) async {
    final wasOffline = _isOfflineMode;
    final samePassword = _finishedPassword;
    await _resetBlocker(fullReset: false, preserveOfflineFlag: wasOffline);
    setState(() {
      _isOfflineMode = wasOffline;
      _blockerDays = days;
      _generatedPassword = samePassword;
    });
    await _setupBlocker();
  }

  Future<void> _resetBlocker({
    bool fullReset = true,
    bool preserveOfflineFlag = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sm_blocker_is_finished');
    await prefs.remove('sm_blocker_finished_password');
    await prefs.remove('sm_blocker_gave_up');
    await prefs.remove('sm_blocker_completed_days');
    await prefs.remove('sm_blocker_password');
    await prefs.remove('sm_blocker_setup_date');
    await prefs.remove('sm_blocker_timeout_date');
    await prefs.remove('sm_blocker_is_offline');

    setState(() {
      _isSetupComplete = false;
      _isChallengeFinished = false;
      _isTimeUp = false;
      _generatedPassword = null;
      _finishedPassword = null;
      _timeoutDate = null;
      _setupDate = null;
      _blockerDays = 7;
      _completedDaysOnFinish = null;
      _gaveUp = false;
      _isOfflineMode = preserveOfflineFlag ? true : false;
      _durationController.text = '7';
      _calculateInitialEndDate();
      if (fullReset) {
        _currentPage = 0;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
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
            "You'll let us know how many days you want to stay away from social media. We'll give you the password back only after the timeout ends.",
      },
    ];

    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (page) {
              setState(() {
                _currentPage = page;
              });
            },
            children: [
              ...features.map((feature) {
                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DynamicColorSvg(
                        assetName: feature['svg']!,
                        color: Theme.of(context).colorScheme.primary,
                        height: 200,
                      ),
                      const SizedBox(height: 32),
                      Text(
                        feature['title']!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.gabarito(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        feature['desc']!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              _buildDurationPage(),
              _buildSecurityPage(),
              _buildPasswordPage(),
            ],
          ),
        ),
        _buildNavigationControls(),
      ],
    );
  }

  Widget _buildDurationPage() {
    final auraGain = (_blockerDays ?? 0) * 3;
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_rounded, size: 64),
          const SizedBox(height: 24),
          Text(
            'Set your timeout',
            style: GoogleFonts.gabarito(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'How many days do you want to stay away from social media?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _durationController,
            onChanged: (value) {
              setState(() {
                final days = int.tryParse(value);
                if (days != null) {
                  _blockerDays = days;
                  if (days > 365) {
                    _durationErrorText = 'Cannot exceed 365 days';
                    _calculatedEndDate = null;
                  } else if (days <= 0) {
                    _durationErrorText = 'Must be at least 1 day';
                    _calculatedEndDate = null;
                  } else {
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
                  }
                } else {
                  _blockerDays = null;
                  _durationErrorText = 'Please enter a valid number';
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
              'Approximate aura gain: ${_isOfflineMode ? 0 : auraGain}',
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _showOfflineModeDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Text(
            'Enable Offline Mode?',
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'Your password will be stored securely on this device. If you uninstall the app or lose your device, the password will be permanently lost.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Text(
                  'You will not earn any aura for completing the challenge in offline mode.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
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
              onPressed: () {
                setState(() {
                  _isOfflineMode = true;
                });
                Navigator.of(context).pop();
              },
              child: const Text('I Understand'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSecurityPage() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DynamicColorSvg(
                  assetName: 'assets/img/offline_mode.svg',
                  color: theme.colorScheme.primary,
                  height: 200,
                ),
                const SizedBox(height: 32),
                Text(
                  'Your data, truly yours.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.gabarito(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'We will securely store your password on our server, away from any third party\'s access. You can go offline for even more security.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 0,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            tileColor: theme.colorScheme.secondaryContainer,
            title: const Text('Offline Mode'),
            subtitle: Text(
              'No internet needed. No aura gained.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            value: _isOfflineMode,
            onChanged: (bool value) {
              if (value) {
                _showOfflineModeDialog();
              } else {
                setState(() {
                  _isOfflineMode = false;
                });
              }
            },
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

              if (_currentPage < 5) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.ease,
                );
              } else {
                _setupBlocker();
              }
            },
            child: Text(_currentPage < 5 ? 'Next' : 'Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressView() {
    double progress = 0.0;
    String timeValue = "Time's up!";
    String timeDescription = "You can now get your password.";

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
        timeValue = "Time's up!";
        timeDescription = "You can now get your password.";
      } else {
        final d = remaining.inDays;
        final h = remaining.inHours % 24;
        final m = remaining.inMinutes % 60;
        timeValue = '${d}d ${h}h ${m}m';
        timeDescription = 'remaining until your password is revealed';
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: _isTimeUp
            ? _buildCongratulationsView()
            : _buildInProgressView(progress, timeValue, timeDescription),
      ),
    );
  }

  Widget _buildInProgressView(
    double progress,
    String timeValue,
    String timeDescription,
  ) {
    final theme = Theme.of(context);
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
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              Center(
                child: Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.gabarito(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text(
          timeValue,
          textAlign: TextAlign.center,
          style: GoogleFonts.gabarito(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          timeDescription,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _isCompleting ? null : _showGiveUpDialog,
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error.withOpacity(0.5)),
          ),
          child: const Text('Give Up'),
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
                    _gaveUp
                        ? "You've completed the challenge for ${_completedDaysOnFinish ?? 0} days. Here is your password:"
                        : "You've completed the challenge. Here is your password:",
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
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: _finishedPassword == null
                                ? null
                                : () {
                                    Clipboard.setData(
                                      ClipboardData(text: _finishedPassword!),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Password copied!'),
                                      ),
                                    );
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Continue again'),
                        onPressed: _showContinueDialog,
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Start New'),
                        onPressed: _showRestartDialog,
                      ),
                    ],
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
