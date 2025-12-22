import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:alexandria/ui/home_screen.dart';
import 'package:alexandria/ui/add_content_screen.dart';
import 'package:alexandria/ui/profile_screen.dart';
import 'package:alexandria/ui/codex/search_screen.dart';
import 'package:alexandria/ui/scriptorium/creation_wizard.dart';
import 'package:alexandria/ui/settings/settings_screen.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:flutter_animate/flutter_animate.dart';

// View State Provider
final currentTabProvider = StateProvider<int>((ref) => 0);

class MainScaffold extends ConsumerWidget {
  const MainScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(currentTabProvider);

    // Tab Views
    final List<Widget> tabs = [
      const HomeScreen(), // 0: The Atrium
      const SearchScreen(), // 1: The Codex (Search)
      const AddContentScreen(), // 2: The Scriptorium (Add) - Usually pushed as modal, but here for now
      const ProfileScreen(), // 3: Identity
    ];

    return Scaffold(
      extendBody: true, // Allow body to extend behind the fab/bottom bar
      body: Stack(
        children: [
          // Background (Persistent)
          Container(
            decoration: const BoxDecoration(
              color: AppTheme.canvasColor,
              // Optional: Add starfield or subtle gradient here
            ),
          ),

          // Tab Content
          // Using IndexedStack for state preservation, or custom switcher
          IndexedStack(index: currentTab, children: tabs),
        ],
      ),
      bottomNavigationBar: _GlassBottomNav(
        currentIndex: currentTab,
        onTap: (index) {
          if (index == 2) {
            // Special case for Add: Push as modal?
            // For now, let's keep it in tab or push
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreationWizard()),
            );
          } else {
            ref.read(currentTabProvider.notifier).state = index;
          }
        },
      ),
    );
  }
}

class _GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const _GlassBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: GlassmorphicContainer(
        width: double.infinity,
        height: 80,
        borderRadius: 40,
        blur: 20,
        alignment: Alignment.center,
        border: 2,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surfaceColor.withValues(alpha: 0.7),
            AppTheme.surfaceColor.withValues(alpha: 0.4),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.3),
            AppTheme.primaryColor.withValues(alpha: 0.1),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _NavIcon(
              icon: Icons.temple_buddhist, // Atrium
              label: 'Atrium',
              isSelected: currentIndex == 0,
              onTap: () => onTap(0),
            ),
            _NavIcon(
              icon: Icons.search, // Codex
              label: 'Codex',
              isSelected: currentIndex == 1,
              onTap: () => onTap(1),
            ),
            // Middle Action Button
            _AddButton(onTap: () => onTap(2)),

            _NavIcon(
              icon: Icons.person, // Identity
              label: 'Identity',
              isSelected: currentIndex == 3,
              onTap: () => onTap(3),
            ),
            _NavIcon(
              icon: Icons.settings,
              label: 'Settings',
              isSelected: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavIcon({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
                icon,
                color: isSelected ? AppTheme.primaryColor : Colors.white38,
                size: 28,
              )
              .animate(target: isSelected ? 1 : 0)
              .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2)),
          const SizedBox(height: 4),
          if (isSelected)
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ).animate().fadeIn().moveY(begin: 5, end: 0),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child:
          Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.white),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .boxShadow(
                begin: BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  blurRadius: 4,
                ),
                end: BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.6),
                  blurRadius: 12,
                ),
                duration: 2.seconds,
              ),
    );
  }
}
