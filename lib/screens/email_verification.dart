import 'dart:async';
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart' as appwrite;
import 'package:google_fonts/google_fonts.dart';
import '../home.dart';
import '../main.dart';

class EmailVerificationScreen extends StatefulWidget {
  final appwrite.Account account;
  const EmailVerificationScreen({super.key, required this.account});

  static bool _isShowing = false;

  static void show(BuildContext context, appwrite.Account account) {
    if (_isShowing) return;
    _isShowing = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => EmailVerificationScreen(account: account),
          ),
        )
        .then((_) => _isShowing = false);
  }

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  String? _email;
  bool _isLoading = true;
  bool _isChecking = false;
  bool _isResending = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserEmail();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkStatus(silent: true);
    }
  }

  Future<void> _loadUserEmail() async {
    try {
      final user = await widget.account.get();
      if (mounted) {
        setState(() {
          _email = user.email;
          _isLoading = false;
        });
        if (user.emailVerification) {
          _onVerificationSuccess();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Failed to load user info: $e');
      }
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _checkStatus(silent: true);
    });
  }

  Future<void> _checkStatus({bool silent = false}) async {
    if (_isChecking && !silent) return;
    if (mounted && !silent) {
      setState(() => _isChecking = true);
    }

    try {
      final user = await widget.account.get();
      if (mounted) {
        if (user.emailVerification) {
          _onVerificationSuccess();
        } else if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email is still not verified.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        _showError('Error checking status: $e');
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _isChecking = false);
      }
    }
  }

  void _onVerificationSuccess() {
    _pollingTimer?.cancel();
    _cooldownTimer?.cancel();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Email verified successfully! Welcome to AurAchieve.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomePage(account: widget.account),
        ),
      );
    }
  }

  Future<void> _resendVerification() async {
    if (_cooldownSeconds > 0 || _isResending) return;
    setState(() => _isResending = true);

    try {
      await widget.account.createEmailVerification(
        url: 'https://aurachieve.com/account/verify-email',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email sent!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _cooldownSeconds = 60;
        });
        _startCooldownTimer();
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('rate_limit_exceeded') || msg.contains('429')) {
          msg = 'Too many requests. Please wait a bit before resending.';
        }
        _showError('Failed to send verification: $msg');
      }
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_cooldownSeconds > 0) {
            _cooldownSeconds--;
          } else {
            _cooldownTimer?.cancel();
          }
        });
      }
    });
  }

  Future<void> _logout() async {
    _pollingTimer?.cancel();
    _cooldownTimer?.cancel();
    try {
      await widget.account.deleteSession(sessionId: 'current');
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AuthCheck(account: widget.account)),
        (route) => false,
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.mark_email_unread_rounded,
                    size: 64,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Verify your email',
                  style: GoogleFonts.ebGaramond(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    "We've sent a verification link to your email address. Please click on the link to verify your account.",
                    style: GoogleFonts.gabarito(
                      fontSize: 16,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.alternate_email_rounded, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _email ?? '',
                          style: GoogleFonts.gabarito(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                FilledButton.icon(
                  onPressed: _isChecking
                      ? null
                      : () => _checkStatus(silent: false),
                  icon: _isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    _isChecking ? 'Checking status...' : 'Check Status',
                    style: GoogleFonts.gabarito(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: (_cooldownSeconds > 0 || _isResending)
                      ? null
                      : _resendVerification,
                  icon: _isResending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _cooldownSeconds > 0
                        ? 'Resend Link in ${_cooldownSeconds}s'
                        : 'Resend Verification Link',
                    style: GoogleFonts.gabarito(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(
                    'Use a different account',
                    style: GoogleFonts.gabarito(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
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
}
