import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:alexandria/l10n/app_localizations.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'data/database.dart';
import 'services/preservation_service.dart';
import 'services/secure_storage_service.dart';
import 'ui/scaffold/main_scaffold.dart';
import 'ui/theme/app_theme.dart';
import 'ui/onboarding/welcome_screen.dart';
import 'logic/settings_logic.dart';

// Global provider for Drift database
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

void main() async {
  SentryWidgetsFlutterBinding.ensureInitialized();

  await SentryFlutter.init((options) {
    options.dsn =
        'https://examplePublicKey@o0.ingest.sentry.io/0'; // Placeholder DSN
    options.tracesSampleRate = 1.0;
  }, appRunner: () => runApp(const ProviderScope(child: AlexandriaApp())));
}

class AlexandriaApp extends ConsumerStatefulWidget {
  const AlexandriaApp({super.key});

  @override
  ConsumerState<AlexandriaApp> createState() => _AlexandriaAppState();
}

// ... (imports remain)

class _AlexandriaAppState extends ConsumerState<AlexandriaApp> {
  PreservationService? _preservationService;
  AppStatus _status = AppStatus.loading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initApp());
  }

  Future<void> _initApp() async {
    // 1. Check Onboarding
    final secureStorage = ref.read(secureStorageServiceProvider);
    final hasSeenOnboarding = await secureStorage.read('has_seen_onboarding');

    if (hasSeenOnboarding != 'true') {
      if (mounted) setState(() => _status = AppStatus.onboarding);
      return;
    }

    // 2. Start Background Services
    ref.read(databaseProvider);
    _preservationService = ref.read(preservationServiceProvider);
    _preservationService?.startBackgroundPreservation();

    // 3. Check Auth
    await _checkAuth();
  }

  Future<void> _checkAuth() async {
    final bioService = ref.read(biometricServiceProvider);
    final isAuthenticated = await bioService.authenticate();

    if (isAuthenticated) {
      if (mounted) setState(() => _status = AppStatus.unlocked);
    } else {
      if (mounted) setState(() => _status = AppStatus.locked);
    }
  }

  @override
  void dispose() {
    _preservationService?.stopBackgroundPreservation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch settings for theme changes
    final settings = ref.watch(settingsProvider);

    // Common Theme Setup
    final lightTheme = AppTheme.lightTheme;
    final darkTheme = AppTheme.darkTheme;
    final themeMode = settings.themeMode;

    final localizations = const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

    switch (_status) {
      case AppStatus.loading:
        return MaterialApp(
          home: const Scaffold(
            backgroundColor: AppTheme.canvasColor,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            ),
          ),
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
        );

      case AppStatus.onboarding:
        return MaterialApp(
          home: const WelcomeScreen(),
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
        );

      case AppStatus.locked:
        return MaterialApp(
          home: Scaffold(
            // Use Builder to separate context for Theme inheritance if needed,
            // but here we just need to ensure background color matches theme or is hardcoded.
            // Since locked screen is stylized, we might want to keep it consistent
            // or adapt. Let's adapt to surface color of current brightness?
            // Actually, keep it simple for now, use theme's scaffold background.
            body: Builder(
              builder: (context) => Scaffold(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Alexandria Locked',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                        ),
                        onPressed: _checkAuth,
                        child: const Text('Unlock'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
        );

      case AppStatus.unlocked:
        return MaterialApp(
          title: 'Alexandria',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          home: const MainScaffold(),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: localizations,
          supportedLocales: const [Locale('en')],
        );
    }
  }
}

enum AppStatus { loading, onboarding, locked, unlocked }
