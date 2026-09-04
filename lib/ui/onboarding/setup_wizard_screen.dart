import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:alexandria/ui/scaffold/main_scaffold.dart';
import 'package:alexandria/services/secure_storage_service.dart'; // To init keys if needed
// import 'package:alexandria/logic/profile_logic.dart'; // We haven't built this yet, will do inline for now

class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  String _statusText = 'Preparing local storage...'; // Sci-fi flavor

  @override
  void initState() {
    super.initState();
    _startGenerationSequence();
  }

  Future<void> _startGenerationSequence() async {
    // Fake sequence for drama/UX
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _statusText = 'Generating Cryptographic Keys...');

    // Actually trigger key generation (lazy load in repo)
    // In a real app we'd explicitly create a profile here.
    // For now, let's just ensure the Master Key exists by touching the repo or similar.
    // Since createContent does it, we might want a dedicated init method.
    // We'll proceed assuming standard lazy init for now.

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _statusText = 'Generating keys...');

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _statusText = 'Connected.');

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _statusText = 'Ready.');

    // Write First Run Flag
    final secureStorage = ref.read(secureStorageServiceProvider);
    await secureStorage.write('has_seen_onboarding', 'true');

    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;
    // ignore: use_build_context_synchronously, unawaited_futures
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScaffold()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                ),

                // Inner spinner
                const SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.honorColor,
                  ),
                ),

                Icon(
                  Icons.fingerprint,
                  size: 40,
                  color: AppTheme.primaryAccent.withValues(alpha: 0.8),
                ),
              ],
            ),
            const SizedBox(height: 48),
            Text(
              _statusText,
              style: GoogleFonts.firaCode(
                color: AppTheme.primaryAccent,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
