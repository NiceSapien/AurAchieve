import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:appwrite/models.dart' as models;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:io';
import 'api_service.dart';

import 'shop.dart';
import 'settings.dart';
import 'aurapage.dart';
import 'about.dart';

class ProfilePage extends StatefulWidget {
  final ApiService apiService;
  final int aura;
  final List tasks;
  final List<int> auraHistory;
  final List<DateTime?> auraDates;
  final List completedTasks;
  final bool showQuote;
  final bool smartSuggestions;
  final Set<String> enabledTabs;
  final ValueChanged<bool> onShowQuoteChanged;
  final ValueChanged<bool> onSmartSuggestionsChanged;
  final ValueChanged<Set<String>> onEnabledTabsChanged;
  final VoidCallback onLogout;
  final String? username;
  final ValueChanged<int> onAuraChanged;

  const ProfilePage({
    super.key,
    required this.apiService,
    required this.aura,
    required this.tasks,
    required this.auraHistory,
    required this.auraDates,
    required this.completedTasks,
    required this.showQuote,
    required this.smartSuggestions,
    required this.enabledTabs,
    required this.onShowQuoteChanged,
    required this.onSmartSuggestionsChanged,
    required this.onEnabledTabsChanged,
    required this.onLogout,
    required this.onAuraChanged,
    this.username,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  models.User? _user;
  bool _isLoading = true;
  String _versionName = '';
  Map<String, dynamic>? _userProfile;
  bool _hasAuraPage = false;
  late int _currentAura;

  @override
  void initState() {
    super.initState();
    _currentAura = widget.aura;
    if (widget.username != null && widget.username!.isNotEmpty) {
      _hasAuraPage = true;
      _userProfile = {'username': widget.username};
    }
    _fetchUser();
    _fetchVersion();
  }

  Future<void> _fetchUser() async {
    try {
      final user = await widget.apiService.account.get();

      if (!_hasAuraPage) {
        try {
          final page = await widget.apiService.getAuraPage();
          if (mounted && page.isNotEmpty) {
            setState(() {
              _userProfile = page;
              _hasAuraPage =
                  page['username'] != null &&
                  page['username'].toString().isNotEmpty;
            });
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _user = user;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: picked.path,
      compressFormat: ImageCompressFormat.png,
      compressQuality: 100,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Profile Picture',
          toolbarColor: Theme.of(context).colorScheme.primary,
          toolbarWidgetColor: Theme.of(context).colorScheme.onPrimary,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Crop Profile Picture',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );

    if (croppedFile == null) return;

    setState(() => _isLoading = true);

    try {
      final tempDir = Directory.systemTemp;
      final targetPath = '${tempDir.path}/temp_pfp.webp';

      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      final result = await FlutterImageCompress.compressAndGetFile(
        croppedFile.path,
        targetPath,
        format: CompressFormat.webp,
        quality: 95,
      );

      if (result == null) throw Exception('Failed to compress image');

      final resultFile = File(result.path);
      final length = await resultFile.length();

      if (length > 2 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Resulting image is too large (>2MB). Please pick a smaller image.',
              ),
            ),
          );
        }
        return;
      }

      final username = _userProfile?['username'];
      if (username == null) throw Exception('Username not found');

      await widget.apiService.uploadProfilePicture(resultFile, username);

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Profile picture updated! It may take a few minutes to appear on your Aura Page.',
            ),
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showEditNameDialog() async {
    final controller = TextEditingController(text: _user?.name);
    final scheme = Theme.of(context).colorScheme;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Name', style: TextStyle(color: scheme.onSurface)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: scheme.onSurface),
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await widget.apiService.updateName(controller.text);
                if (mounted) {
                  Navigator.pop(context);
                  _fetchUser();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name updated successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _handleAvatarTap() {
    final scheme = Theme.of(context).colorScheme;
    if (!_hasAuraPage) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Create Aura Page',
            style: TextStyle(color: scheme.onSurface),
          ),
          content: Text(
            'You need to claim your Aura Page username before you can set a profile picture.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AuraPageIntro(
                      apiService: widget.apiService,
                      aura: widget.aura,
                      tasks: widget.tasks,
                      auraHistory: widget.auraHistory,
                      auraDates: widget.auraDates,
                      completedTasks: widget.completedTasks,
                      username: _hasAuraPage && _userProfile != null
                          ? _userProfile!['username']
                          : null,
                    ),
                  ),
                );
              },
              child: const Text('Go to Aura Page'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Public Profile Picture',
          style: TextStyle(color: scheme.onSurface),
        ),
        content: Text(
          'Your profile picture will be visible publicly on your Aura Page. Please choose accordingly.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _pickAndUploadImage();
            },
            child: const Text('I Understand'),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _versionName = info.version;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final username = _userProfile?['username'];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Profile',
          style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: _handleAvatarTap,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: scheme.primaryContainer,
                          foregroundImage: _user != null && username != null
                              ? NetworkImage(
                                  'https://cloud.appwrite.io/v1/storage/buckets/69538a24001337545e6b/files/$username/view?project=6800a2680008a268a6a3',
                                )
                              : null,
                          onForegroundImageError:
                              _user != null && username != null
                              ? (_, __) {}
                              : null,
                          child: Text(
                            _user?.name.isNotEmpty == true
                                ? _user!.name[0].toUpperCase()
                                : 'U',
                            style: GoogleFonts.gabarito(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.surface,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 16,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          _user?.name ?? 'User',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.gabarito(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: IconButton(
                          onPressed: _showEditNameDialog,
                          icon: Icon(
                            Icons.edit_rounded,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          tooltip: 'Edit Name',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _user?.email ?? '',
                    style: GoogleFonts.gabarito(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 48),
                  _buildOption(
                    context,
                    icon: Icons.auto_awesome_rounded,
                    title: 'Aura Page',
                    color: Colors.purple,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'New',
                        style: GoogleFonts.gabarito(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: scheme.onError,
                        ),
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AuraPageIntro(
                            apiService: widget.apiService,
                            aura: widget.aura,
                            tasks: widget.tasks,
                            auraHistory: widget.auraHistory,
                            auraDates: widget.auraDates,
                            completedTasks: widget.completedTasks,
                            username: _hasAuraPage && _userProfile != null
                                ? _userProfile!['username']
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildOption(
                    context,
                    icon: Icons.storefront_rounded,
                    title: 'Shop',
                    color: Colors.orange,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ShopPage(
                            apiService: widget.apiService,
                            currentAura: _currentAura,
                            onAuraSpent: (cost) {
                              setState(() {
                                _currentAura -= cost;
                              });
                              widget.onAuraChanged(_currentAura);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  _buildOption(
                    context,
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    color: Colors.blueGrey,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SettingsScreen(
                            showQuote: widget.showQuote,
                            smartSuggestions: widget.smartSuggestions,
                            enabledTabs: widget.enabledTabs,
                            onShowQuoteChanged: widget.onShowQuoteChanged,
                            onSmartSuggestionsChanged:
                                widget.onSmartSuggestionsChanged,
                            onEnabledTabsChanged: widget.onEnabledTabsChanged,
                            onLogout: widget.onLogout,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildOption(
                    context,
                    icon: Icons.info_rounded,
                    title: 'About',
                    color: Colors.teal,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AboutPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 48),
                  if (_versionName.isNotEmpty)
                    Text(
                      'Version $_versionName',
                      style: GoogleFonts.gabarito(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant.withOpacity(0.5),
                      ),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          title,
          style: GoogleFonts.gabarito(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null) ...[
              trailing,
              const SizedBox(width: 8),
            ],
            Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
