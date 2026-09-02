import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/sync_service.dart';
import '../home_screen.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _currentIndex = 0;

  final _screens = const [
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final syncStatus = ref.watch(syncStatusProvider);

    return Scaffold(
      body: Stack(
        children: [
          _screens[_currentIndex],
          Positioned(
            top: 20,
            right: 16,
            child: _SyncStatusIndicator(status: syncStatus),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.local_library_outlined), label: 'Library'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

class _SyncStatusIndicator extends StatelessWidget {
  final SyncStatus status;

  const _SyncStatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      SyncStatus.idle => (AppTheme.honorColor, 'Synced'),
      SyncStatus.syncing => (AppTheme.primaryColor, 'Syncing...'),
      SyncStatus.offline => (AppTheme.secondaryColor, 'Offline'),
      SyncStatus.error => (AppTheme.dangerColor, 'Sync Error'),
    };

    final isSyncing = status == SyncStatus.syncing;
    final showLabel = status != SyncStatus.idle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          )
              .animate(
                target: isSyncing ? 1 : 0,
                onPlay: (controller) => controller.repeat(reverse: true),
              )
              .scale(
                duration: 900.ms,
                begin: const Offset(1.0, 1.0),
                end: const Offset(1.6, 1.6),
                curve: Curves.easeInOut,
              ),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
