import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/secure_storage_service.dart';
import 'onboarding/welcome_screen.dart';
import 'scaffold/main_scaffold.dart';
import 'theme/app_theme.dart';

/// First-run gate: while the stored flag resolves, a branded splash is
/// shown instead of a bare spinner; then first-timers get the welcome
/// flow and everyone else lands on the library.
class AppEntryGate extends ConsumerStatefulWidget {
  const AppEntryGate({super.key});

  @override
  ConsumerState<AppEntryGate> createState() => _AppEntryGateState();
}

class _AppEntryGateState extends ConsumerState<AppEntryGate> {
  bool? _hasSeenOnboarding;

  @override
  void initState() {
    super.initState();
    ref
        .read(secureStorageServiceProvider)
        .read('has_seen_onboarding')
        .then((value) {
      if (mounted) setState(() => _hasSeenOnboarding = value == 'true');
    }).catchError((_) {
      if (mounted) setState(() => _hasSeenOnboarding = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final seen = _hasSeenOnboarding;
    if (seen == null) {
      return const Scaffold(
        backgroundColor: AppTheme.canvasColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_stories,
                size: 64,
                color: AppTheme.primaryAccent,
              ),
              SizedBox(height: 24),
              Text(
                'Alexandria',
                style: TextStyle(
                  fontFamily: 'Newsreader',
                  fontSize: 40,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.5,
                  color: AppTheme.textColor,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return seen ? const MainScaffold() : const WelcomeScreen();
  }
}
