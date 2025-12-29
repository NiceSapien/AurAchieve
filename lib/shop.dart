import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';

class ShopPage extends StatefulWidget {
  final ApiService apiService;
  final int currentAura;

  const ShopPage({
    super.key,
    required this.apiService,
    required this.currentAura,
  });

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Shop',
          style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
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
          _buildShopItem(
            context,
            title: 'Hacker',
            description: 'Green terminal vibes for your aura page.',
            cost: 500,
            icon: Icons.terminal_rounded,
            color: Colors.green,
          ),
          _buildShopItem(
            context,
            title: 'Peace',
            description: 'Calm blue and white aesthetics.',
            cost: 500,
            icon: Icons.spa_rounded,
            color: Colors.blue,
          ),
        ],
      ),
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
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isMaxedOut = maxQuantity != null && currentQuantity >= maxQuantity;
    final canAfford = widget.currentAura >= cost && !isMaxedOut;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: canAfford
              ? () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coming soon!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              : null,
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
                        : (canAfford
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest),
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
