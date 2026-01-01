import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';

class ShopPage extends StatefulWidget {
  final ApiService apiService;
  final int currentAura;
  final Function(int) onAuraSpent;

  const ShopPage({
    super.key,
    required this.apiService,
    required this.currentAura,
    required this.onAuraSpent,
  });

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  List<String> _purchasedThemes = [];
  String? _currentTheme;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAuraPageData();
  }

  Future<void> _fetchAuraPageData() async {
    try {
      final data = await widget.apiService.getAuraPage();
      if (mounted) {
        setState(() {
          _purchasedThemes = List<String>.from(data['purchasedThemes'] ?? []);
          _currentTheme = data['theme'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _purchaseOrEquipTheme(String themeKey, int cost) async {
    final isOwned = _purchasedThemes.contains(themeKey);
    final isEquipped = _currentTheme == themeKey;

    if (isEquipped) return;

    if (isOwned) {
      
      try {
        await widget.apiService.updateAuraTheme(themeKey);
        if (mounted) {
          setState(() => _currentTheme = themeKey);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Theme equipped!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to equip theme: $e')),
          );
        }
      }
    } else {
      
      if (widget.currentAura < cost) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Insufficient Aura!')),
        );
        return;
      }

      try {
        final result = await widget.apiService.updateAuraTheme(themeKey);
        if (mounted) {
          setState(() {
            _purchasedThemes =
                List<String>.from(result['purchasedThemes'] ?? []);
            _currentTheme = result['theme'];
          });
          widget.onAuraSpent(cost);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Theme purchased and equipped!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to purchase theme: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Shop',
          style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.currentAura}',
                  style: GoogleFonts.gabarito(
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          Text(
            'Power-ups',
            style: GoogleFonts.gabarito(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _buildShopItem(
            context,
            title: 'Streak Freeze',
            description: 'Protect your streak for one day if you miss a habit.',
            cost: 30,
            icon: Icons.ac_unit_rounded,
            color: Colors.cyan,
            maxQuantity: 5,
            currentQuantity: 0,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Coming soon!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          Text(
            'AuraPage themes',
            style: GoogleFonts.gabarito(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _buildThemeItem(
            context,
            title: 'Peace',
            description: 'Japanese cherry blossom pink theme.',
            cost: 250,
            icon: Icons.spa_rounded,
            color: Colors.pinkAccent,
            themeKey: 'peace',
          ),
          _buildThemeItem(
            context,
            title: 'Midnight',
            description: 'Deep purple and starry night theme.',
            cost: 500,
            icon: Icons.nightlight_round,
            color: Colors.deepPurple,
            themeKey: 'midnight',
          ),
          _buildThemeItem(
            context,
            title: 'Hacker',
            description: 'Green terminal vibes for your aura page.',
            cost: 750,
            icon: Icons.terminal_rounded,
            color: Colors.green,
            themeKey: 'hacker',
          ),
          _buildThemeItem(
            context,
            title: 'Gold',
            description: 'Luxurious and elegant theme.',
            cost: 750,
            icon: Icons.monetization_on_rounded,
            color: Colors.amber,
            themeKey: 'gold',
          ),
        ],
      ),
    );
  }

  Widget _buildThemeItem(
    BuildContext context, {
    required String title,
    required String description,
    required int cost,
    required IconData icon,
    required Color color,
    required String themeKey,
  }) {
    final isOwned = _purchasedThemes.contains(themeKey);
    final isEquipped = _currentTheme == themeKey;

    return _buildShopItem(
      context,
      title: title,
      description: description,
      cost: cost,
      icon: icon,
      color: color,
      isOwned: isOwned,
      isEquipped: isEquipped,
      onTap: () => _purchaseOrEquipTheme(themeKey, cost),
    );
  }

  Widget _buildShopItem(
    BuildContext context, {
    required String title,
    required String description,
    required int cost,
    required IconData icon,
    required Color color,
    int? maxQuantity,
    int currentQuantity = 0,
    bool isOwned = false,
    bool isEquipped = false,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isMaxedOut = maxQuantity != null && currentQuantity >= maxQuantity;
    final canAfford = widget.currentAura >= cost && !isMaxedOut;

    
    
    final isTheme = maxQuantity == null;
    final canInteract = isTheme ? true : canAfford;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isEquipped
              ? scheme.primary
              : scheme.outlineVariant.withOpacity(0.3),
          width: isEquipped ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: canInteract ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.gabarito(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          if (maxQuantity != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$currentQuantity/$maxQuantity',
                                style: GoogleFonts.gabarito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                          if (isEquipped) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'EQUIPPED',
                                style: GoogleFonts.gabarito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: GoogleFonts.gabarito(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMaxedOut
                        ? scheme.surfaceContainerHighest
                        : (isOwned
                            ? (isEquipped
                                ? scheme.surfaceContainerHighest
                                : scheme.primaryContainer)
                            : (canAfford
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMaxedOut)
                        Text(
                          'Maxed',
                          style: GoogleFonts.gabarito(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else if (isOwned)
                        Text(
                          isEquipped ? 'Equipped' : 'Equip',
                          style: GoogleFonts.gabarito(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isEquipped
                                ? scheme.onSurfaceVariant
                                : scheme.onPrimaryContainer,
                          ),
                        )
                      else ...[
                        Text(
                          '$cost',
                          style: GoogleFonts.gabarito(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: canAfford
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Aura',
                          style: GoogleFonts.gabarito(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: canAfford
                                ? scheme.onPrimaryContainer.withOpacity(0.8)
                                : scheme.onSurfaceVariant.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ],
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
