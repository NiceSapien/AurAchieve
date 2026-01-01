import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/dynamic_color_svg.dart';
import 'api_service.dart';
import 'shop.dart';

import 'package:url_launcher/url_launcher.dart';

class AuraPageIntro extends StatefulWidget {
  final ApiService apiService;
  final int aura;
  final List tasks;
  final List<int> auraHistory;
  final List<DateTime?> auraDates;
  final List completedTasks;
  final String? username;

  const AuraPageIntro({
    super.key,
    required this.apiService,
    required this.aura,
    required this.tasks,
    required this.auraHistory,
    required this.auraDates,
    required this.completedTasks,
    this.username,
  });

  @override
  State<AuraPageIntro> createState() => _AuraPageIntroState();
}

class _ThemeInfo {
  final String key;
  final String name;
  final int price;
  final IconData icon;
  final Color color;

  const _ThemeInfo(this.key, this.name, this.price, this.icon, this.color);
}

class _AuraPageIntroState extends State<AuraPageIntro> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  String? _username;
  bool _isLoading = true;
  bool _isEnabled = true;
  List<String> _purchasedThemes = ['default'];
  String? _currentTheme;
  String _bio = '';

  final List<_ThemeInfo> _allThemes = [
    const _ThemeInfo(
      'default',
      'Default',
      0,
      Icons.auto_awesome_outlined,
      Colors.blue,
    ),
    const _ThemeInfo(
      'peace',
      'Peace',
      250,
      Icons.spa_rounded,
      Colors.pinkAccent,
    ),
    const _ThemeInfo(
      'midnight',
      'Midnight',
      500,
      Icons.nightlight_round,
      Colors.deepPurple,
    ),
    const _ThemeInfo(
      'hacker',
      'Hacker',
      750,
      Icons.terminal_rounded,
      Colors.green,
    ),
    const _ThemeInfo(
      'gold',
      'Gold',
      750,
      Icons.monetization_on_rounded,
      Colors.amber,
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.username != null && widget.username!.isNotEmpty) {
      _username = widget.username;
      _checkStatus();
    } else {
      _checkUsername();
    }
  }

  Future<void> _checkStatus() async {
    try {
      final page = await widget.apiService.getAuraPage();
      if (mounted) {
        setState(() {
          _isEnabled = page['enable'] ?? true;
          final themes = List<String>.from(page['purchasedThemes'] ?? []);
          if (!themes.contains('default')) themes.insert(0, 'default');
          _purchasedThemes = themes;
          _currentTheme = page['theme'];
          _bio = page['bio'] ?? '';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkUsername() async {
    try {
      final page = await widget.apiService.getAuraPage();
      if (mounted) {
        setState(() {
          _username = page['username'];
          _isEnabled = page['enable'] ?? true;
          final themes = List<String>.from(page['purchasedThemes'] ?? []);
          if (!themes.contains('default')) themes.insert(0, 'default');
          _purchasedThemes = themes;
          _currentTheme = page['theme'];
          _bio = page['bio'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleEnable(bool value) async {
    if (_username == null) return;
    setState(() => _isEnabled = value);
    try {
      await widget.apiService.updateAuraPage(enable: value);
    } catch (e) {
      if (mounted) {
        setState(() => _isEnabled = !value);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
      }
    }
  }

  bool _isUpdatingTheme = false;

  Future<void> _updateTheme(String? theme) async {
    if (theme == null || _isUpdatingTheme) return;
    setState(() => _isUpdatingTheme = true);
    try {
      await widget.apiService.updateAuraTheme(theme);
      if (mounted) {
        setState(() => _currentTheme = theme);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Theme updated!'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'View page',
              onPressed: () async {
                final url = Uri.parse('https://aurapage.me/$_username');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update theme: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUpdatingTheme = false);
    }
  }

  Future<void> _editBio() async {
    final bioController = TextEditingController(text: _bio);
    final scheme = Theme.of(context).colorScheme;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: Text(
          'Edit Bio',
          style: GoogleFonts.gabarito(
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        content: TextField(
          controller: bioController,
          maxLength: 180,
          maxLines: 3,
          style: TextStyle(color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: 'I am very very cool',
            hintStyle: TextStyle(color: scheme.onSurfaceVariant),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
            counterStyle: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: scheme.primary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, bioController.text),
            child: Text(
              'Save',
              style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (result != null && result != _bio) {
      try {
        await widget.apiService.updateAuraPage(bio: result);
        if (mounted) {
          setState(() => _bio = result);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Bio updated!')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to update bio: $e')));
        }
      }
    }
  }

  final List<Map<String, dynamic>> _pages = [
    {
      'title': 'Welcome to Aura Pages.',
      'desc': 'A web page of your own - built solely to flex your aura',
      'image': 'assets/img/aurapage.svg',
    },
    {
      'title': 'Share your Aura Page',
      'desc': 'Want aurapage.me/yourname? Claim your free Aura Page now.',
      'image': 'assets/img/share_aurapage.svg',
    },
    {
      'title': 'The best of your life.',
      'desc':
          'Share the best of your memories, achievements, and more right on your Aura Page.',
      'image': 'assets/img/memories.svg',
    },
  ];

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _showClaimDialog();
    }
  }

  Future<void> _showClaimDialog() async {
    final usernameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final scheme = Theme.of(context).colorScheme;
          return AlertDialog(
            title: Text(
              'Claim your Aura Page',
              style: GoogleFonts.gabarito(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose a unique username for your page.',
                    style: GoogleFonts.gabarito(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: usernameController,
                    style: TextStyle(color: scheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                      prefixText: 'aurapage.me/',
                      prefixStyle: TextStyle(color: scheme.onSurfaceVariant),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: scheme.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: scheme.primary),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a username';
                      }
                      if (value.length < 3) {
                        return 'Username must be at least 3 characters';
                      }
                      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                        return 'Only letters, numbers, and underscores allowed';
                      }
                      if (widget.apiService.isUsernameReserved(value)) {
                        return 'This username is reserved';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (formKey.currentState!.validate()) {
                          setDialogState(() => isLoading = true);
                          try {
                            await widget.apiService.claimAuraPage(
                              usernameController.text,
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              setState(() {
                                _username = usernameController.text;
                                _isEnabled = true;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Aura Page claimed successfully!',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: ${e.toString()}'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: scheme.error,
                                ),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setDialogState(() => isLoading = false);
                            }
                          }
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Claim'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_username != null && _username!.isNotEmpty) {
      final currentThemeInfo = _allThemes.firstWhere(
        (t) => t.key == _currentTheme,
        orElse: () => _allThemes.first,
      );

      return Scaffold(
        appBar: AppBar(title: const Text('Your Aura Page')),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: scheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          'Enable Aura Page',
                          style: GoogleFonts.gabarito(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                          ),
                        ),
                        subtitle: Text(
                          'Make your page publicly visible',
                          style: GoogleFonts.gabarito(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        value: _isEnabled,
                        onChanged: _toggleEnable,
                        secondary: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _isEnabled
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isEnabled
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: _isEnabled
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: scheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.edit_outlined,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                        title: Text(
                          'Bio',
                          style: GoogleFonts.gabarito(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                          ),
                        ),
                        subtitle: _bio.isNotEmpty
                            ? Text(
                                _bio,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.gabarito(
                                  color: scheme.onSurfaceVariant,
                                ),
                              )
                            : null,
                        onTap: _editBio,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: scheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          shape: const Border(),
                          collapsedShape: const Border(),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          title: Text(
                            'Theme',
                            style: GoogleFonts.gabarito(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                          ),
                          subtitle: Text(
                            currentThemeInfo.name,
                            style: GoogleFonts.gabarito(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: currentThemeInfo.color.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              currentThemeInfo.icon,
                              color: currentThemeInfo.color,
                            ),
                          ),
                          children: [
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _allThemes.length,
                              itemBuilder: (context, index) {
                                final theme = _allThemes[index];
                                final isOwned = _purchasedThemes.contains(
                                  theme.key,
                                );
                                final isSelected =
                                    _currentTheme == theme.key ||
                                    (_currentTheme == null &&
                                        theme.key == 'default');

                                if (!isOwned) return const SizedBox.shrink();

                                return ListTile(
                                  leading: Icon(theme.icon, color: theme.color),
                                  title: Text(theme.name),
                                  trailing: isSelected
                                      ? Icon(
                                          Icons.check_circle,
                                          color: scheme.primary,
                                        )
                                      : (_isUpdatingTheme && isSelected)
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : null,
                                  onTap: () => _updateTheme(theme.key),
                                  selected: isSelected,
                                );
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context)
                                      .push(
                                        MaterialPageRoute(
                                          builder: (context) => ShopPage(
                                            apiService: widget.apiService,
                                            currentAura: widget.aura,
                                            onAuraSpent: (amount) {
                                            },
                                          ),
                                        ),
                                      )
                                      .then((_) => _checkStatus());
                                },
                                icon: const Icon(Icons.shopping_bag_outlined),
                                label: const Text('Buy more themes'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      'Your aura page is available at',
                      style: GoogleFonts.gabarito(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        final url = Uri.parse('https://aurapage.me/$_username');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: Text(
                        'aurapage.me/$_username',
                        style: GoogleFonts.gabarito(
                          fontSize: 18,
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DynamicColorSvg(
                          assetName: page['image'] as String,
                          height: 200,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 48),
                        Text(
                          page['title'] as String,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.gabarito(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page['desc'] as String,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.gabarito(
                            fontSize: 16,
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(
                      _pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? scheme.primary
                              : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _onNext,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      _currentPage == _pages.length - 1 ? 'Claim Page' : 'Next',
                      style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
