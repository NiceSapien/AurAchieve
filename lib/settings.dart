import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

class SettingsScreen extends StatefulWidget {
  final bool showQuote;
  final bool smartSuggestions;
  final Set<String> enabledTabs;
  final ValueChanged<bool> onShowQuoteChanged;
  final ValueChanged<bool> onSmartSuggestionsChanged;
  final ValueChanged<Set<String>> onEnabledTabsChanged;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.showQuote,
    required this.smartSuggestions,
    required this.enabledTabs,
    required this.onShowQuoteChanged,
    required this.onSmartSuggestionsChanged,
    required this.onEnabledTabsChanged,
    required this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _showQuote;
  late bool _smartSuggestions;
  late Set<String> _tabs;
  String? _jwt;

  bool _immersiveMode = true;
  bool _soundVibration = true;

  bool _dynamicColor = true;
  String _themeMode = 'auto';

  @override
  void initState() {
    super.initState();
    _showQuote = widget.showQuote;
    _smartSuggestions = widget.smartSuggestions;
    _tabs = {...widget.enabledTabs};
    _safeLoadJwt();
    _safeLoadTimerSettings();
    _safeLoadThemeSettings();
  }

  Future<void> _safeLoadThemeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _dynamicColor = prefs.getBool('dynamic_color') ?? true;
          _themeMode = prefs.getString('theme_mode') ?? 'auto';
        });
      }
    } catch (_) {}
  }

  Future<void> _updateThemeSettings(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
    if (mounted) {
      setState(() {
        if (key == 'dynamic_color') _dynamicColor = value;
        if (key == 'theme_mode') _themeMode = value;
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restart app to apply theme changes fully.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _safeLoadTimerSettings() async {
    try {
      await _loadTimerSettings();
    } catch (e) {
      debugPrint('Error loading timer settings: $e');
    }
  }

  Future<void> _safeLoadJwt() async {
    try {
      await _loadJwt();
    } catch (e) {
      debugPrint('Error loading JWT: $e');
    }
  }

  Future<void> _loadTimerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _immersiveMode = prefs.getBool('timer_immersive') ?? true;
      _soundVibration = prefs.getBool('timer_sound_vibration') ?? true;
    });
  }

  Future<void> _toggleTimerSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    setState(() {
      if (key == 'timer_immersive') _immersiveMode = value;
      if (key == 'timer_sound_vibration') _soundVibration = value;
    });
  }

  Future<void> _loadJwt() async {
    const storage = FlutterSecureStorage();
    final t = await storage.read(key: 'jwt_token');
    if (!mounted) return;
    setState(() => _jwt = t);
  }

  void _toggleTab(String key, bool value) {
    final next = {..._tabs};
    if (value) {
      next.add(key);
    } else {
      if (next.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Atleast one feature should remain enabled alongside home.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      next.remove(key);
    }
    setState(() => _tabs = next);
    widget.onEnabledTabsChanged(next);
  }

  Future<void> _confirmAndLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dCtx) {
        final cs2 = Theme.of(dCtx).colorScheme;
        return AlertDialog(
          backgroundColor: cs2.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.logout_rounded, color: cs2.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Log out?',
                  style: GoogleFonts.gabarito(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs2.onSurface,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'You will be logged out of this account. You\'ll need your email and password to log back in.',
            style: GoogleFonts.gabarito(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: cs2.onSurfaceVariant,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: cs2.onSurfaceVariant,
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
                backgroundColor: cs2.errorContainer,
                foregroundColor: cs2.error,
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
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
    try {
      const storage = FlutterSecureStorage();
      await storage.deleteAll();
    } catch (_) {}

    if (mounted) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    const tilePadding = EdgeInsets.symmetric(horizontal: 16);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'General',
            style: GoogleFonts.gabarito(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: tilePadding,
                  title: const Text('Show quote on Home'),
                  value: _showQuote,
                  onChanged: (v) {
                    setState(() => _showQuote = v);
                    widget.onShowQuoteChanged(v);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: tilePadding,
                  title: const Text('Smart Suggestions'),
                  subtitle: const Text('Show suggestions for habits'),
                  value: _smartSuggestions,
                  onChanged: (v) {
                    setState(() => _smartSuggestions = v);
                    widget.onSmartSuggestionsChanged(v);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Text(
            'Appearance',
            style: GoogleFonts.gabarito(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  title: const Text('Dynamic Theme'),
                  subtitle: const Text('Use wallpaper colors'),
                  value: _dynamicColor,
                  onChanged: (v) => _updateThemeSettings('dynamic_color', v),
                ),
                if (!_dynamicColor)
                  ListTile(
                    title: const Text('Dark Mode'),
                    trailing: DropdownButton<String>(
                      value: _themeMode,
                      underline: const SizedBox(),
                      dropdownColor: cs.surfaceContainerHigh,
                      style: GoogleFonts.gabarito(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('Auto')),
                        DropdownMenuItem(value: 'light', child: Text('Off')),
                        DropdownMenuItem(value: 'dark', child: Text('On')),
                      ],
                      onChanged: (v) {
                        if (v != null) _updateThemeSettings('theme_mode', v);
                      },
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Text(
            'Timer & Focus',
            style: GoogleFonts.gabarito(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: tilePadding,
                  title: const Text('Immersive Blackout'),
                  subtitle: const Text('Hide system UI in blackout mode'),
                  value: _immersiveMode,
                  onChanged: (v) => _toggleTimerSetting('timer_immersive', v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: tilePadding,
                  title: const Text('Sound & Vibration'),
                  subtitle: const Text('Play sound and vibrate on finish'),
                  value: _soundVibration,
                  onChanged: (v) =>
                      _toggleTimerSetting('timer_sound_vibration', v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Text(
            'Navigation',
            style: GoogleFonts.gabarito(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: tilePadding,
                  title: const Text('Home'),
                  value: true,
                  onChanged: null,
                ),
                SwitchListTile.adaptive(
                  contentPadding: tilePadding,
                  title: const Text('Timer'),
                  value: _tabs.contains('timer'),
                  onChanged: (v) => _toggleTab('timer', v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: tilePadding,
                  title: const Text('Habits'),
                  value: _tabs.contains('habits'),
                  onChanged: (v) => _toggleTab('habits', v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: tilePadding,
                  title: const Text('Blocker'),
                  value: _tabs.contains('blocker'),
                  onChanged: (v) => _toggleTab('blocker', v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: tilePadding,
                  title: const Text('Planner'),
                  value: _tabs.contains('planner'),
                  onChanged: (v) => _toggleTab('planner', v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Text(
            'Account',
            style: GoogleFonts.gabarito(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Log out of this account',
                      style: GoogleFonts.gabarito(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.errorContainer,
                      foregroundColor: cs.error,
                      textStyle: GoogleFonts.gabarito(
                        fontWeight: FontWeight.w700,
                        color: cs.onErrorContainer,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _confirmAndLogout,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Text(
            'Development Features',
            style: GoogleFonts.gabarito(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                if (_jwt == null || _jwt!.isEmpty) return;
                await Clipboard.setData(ClipboardData(text: _jwt!));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('JWT copied to clipboard'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: ListTile(
                leading: const Icon(Icons.key_rounded),
                title: const Text('JWT Token'),
                subtitle: Text(
                  _jwt ?? 'No token available',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                trailing: const Icon(Icons.copy_rounded),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (AppConfig.baseUrl != AppConfig.defaultBaseUrl)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Center(
                child: Text(
                  'Connected to ${AppConfig.baseUrl}',
                  style: GoogleFonts.gabarito(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withOpacity(0.6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
