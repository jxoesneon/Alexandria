import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ui/theme/app_theme.dart';
import 'ui/app_entry_gate.dart';
import 'logic/settings_logic.dart';
import 'services/network_overview_service.dart';
import 'services/preservation_service.dart';
import 'services/web_node_service.dart';
import 'data/database.dart';
import 'services/seed/starter_seed_service.dart';

import 'providers/library_providers.dart';
import 'providers/workspace_providers.dart';

void main() {
  // (round-6 red finding) Never fetch fonts at runtime: google_fonts'
  // first-render download from fonts.gstatic.com uses a direct
  // connection - bypassing Tor and leaking the real IP - and fails
  // offline. Every family the UI references is bundled under
  // assets/fonts/, so disabling runtime fetching loses nothing; any
  // missing font now fails visibly instead of leaking.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const ProviderScope(child: AlexandriaApp()));
}

class AlexandriaApp extends ConsumerStatefulWidget {
  const AlexandriaApp({super.key});

  @override
  ConsumerState<AlexandriaApp> createState() => _AlexandriaAppState();
}

class _AlexandriaAppState extends ConsumerState<AlexandriaApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Restore persisted settings (theme/motion); defaults apply if
      // the read fails - node startup must not depend on it.
      try {
        await ref.read(settingsProvider.notifier).loadSettings();
      } catch (_) {
        // Non-fatal: AppSettings defaults still apply.
      }
      // Full node start: IPFS engine + mesh listener + bootstrap
      // auto-dial + rendezvous announce (see NetworkOverviewService).
      await ref.read(networkOverviewServiceProvider).startNode();
      await ref.read(webNodeServiceProvider).initializeWebNode();
      ref.read(preservationServiceProvider).startBackgroundPreservation();

      // Bootstrap initial landmark content if library is empty
      final db = ref.read(databaseProvider);
      final manifests = await db.getAllManifests();
      if (manifests.isEmpty) {
        final seedService = ref.read(starterSeedServiceProvider);
        await seedService.ingestSeedPack('open-science-landmarks');
        await seedService.ingestSeedPack('classical-commons');
        ref.invalidate(libraryDashboardProvider);
        ref.invalidate(recentItemsProvider);
        ref.invalidate(newArrivalsProvider);
        ref.invalidate(activeWorkspacesProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Alexandria',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      home: const AppEntryGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}
