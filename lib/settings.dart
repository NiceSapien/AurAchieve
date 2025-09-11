import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsScreen extends StatefulWidget {
  final bool showQuote;
  final Set<String> enabledTabs;
  final ValueChanged<bool> onShowQuoteChanged;
  final ValueChanged<Set<String>> onEnabledTabsChanged;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.showQuote,
    required this.enabledTabs,
    required this.onShowQuoteChanged,
    required this.onEnabledTabsChanged,
    required this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _showQuote;
  late Set<String> _tabs;

  @override
  void initState() {
    super.initState();
    _showQuote = widget.showQuote;
    _tabs = {...widget.enabledTabs};
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
    final cs = Theme.of(context).colorScheme;
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
            'About',
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
              onTap: () {},
              child: const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('About AurAchieve'),
                subtitle: Text('App info and credits'),
              ),
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
        ],
      ),
    );
  }
}
