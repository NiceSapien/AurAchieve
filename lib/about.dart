import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
      });
    }
  }

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'About',
          style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                image: const DecorationImage(
                  image: AssetImage('assets/icon/icon.jpg'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'AurAchieve',
              style: GoogleFonts.gabarito(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Version $_version',
              style: GoogleFonts.gabarito(
                fontSize: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildSectionTitle(context, 'Founder'),
            ),
            _buildListTile(context, 'NiceSapien', 'Creator & Developer'),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildSectionTitle(context, 'Sponsors'),
            ),
            _buildListTile(context, 'Renarin Kholin', 'Early Supporter, \$15'),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildSectionTitle(context, 'Early Supporters'),
            ),
            _buildListTile(context, 'Xperian', 'Logo Designer & Beta Tester'),
            _buildListTile(context, 'Mochiziku', 'Beta Tester'),
            _buildListTile(context, 'Trindadev', 'Beta Tester'),
            _buildListTile(
              context,
              'Want your name?',
              'Join the Discord and lmk.',
            ),
            const SizedBox(height: 32),
            Center(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _buildActionButton(
                    context,
                    'Website',
                    Icons.language,
                    'https://aurachieve.com',
                  ),
                  _buildActionButton(
                    context,
                    'Sponsor',
                    Icons.favorite,
                    'https://github.com/NiceSapien/AurAchieve?tab=readme-ov-file#sponsors',
                  ),
                  _buildActionButton(
                    context,
                    'Community',
                    Icons.people,
                    'https://discord.gg/p9QQDSURmz',
                  ),
                  _buildActionButton(
                    context,
                    'GitHub',
                    Icons.code,
                    'https://github.com/NiceSapien/AurAchieve',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.gabarito(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildListTile(BuildContext context, String title, String subtitle) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.3)),
      ),
      child: ListTile(
        title: Text(
          title,
          style: GoogleFonts.gabarito(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.gabarito(color: scheme.onSurfaceVariant),
        ),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Text(
            title[0].toUpperCase(),
            style: GoogleFonts.gabarito(
              fontWeight: FontWeight.bold,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    String url,
  ) {
    return FilledButton.tonalIcon(
      onPressed: () => _launchUrl(url),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: GoogleFonts.gabarito(fontWeight: FontWeight.w600),
      ),
    );
  }
}
