import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/identity_service.dart';
import '../services/mnemonic_service.dart';
import '../services/biometric_service.dart';
import '../services/secure_storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_card.dart';
import 'scaffold/main_scaffold.dart';

/// Onboarding state
enum OnboardingStep { welcome, identity, key, mnemonic, biometric, complete }

/// Provider for onboarding state
final onboardingStepProvider = StateProvider<OnboardingStep>((ref) {
  return OnboardingStep.welcome;
});

/// Provider for generated mnemonic (temporary, cleared after display)
final mnemonicProvider = StateProvider<List<String>?>((ref) => null);

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _isCreating = false;
  final _mnemonicController = TextEditingController();
  final List<TextEditingController> _wordControllers = List.generate(
    24,
    (_) => TextEditingController(),
  );

  @override
  void dispose() {
    _mnemonicController.dispose();
    for (final controller in _wordControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(onboardingStepProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1021), Color(0xFF1E293B)],
          ),
        ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _buildStep(step),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.welcome:
        return _buildWelcomeStep();
      case OnboardingStep.identity:
        return _buildIdentityStep();
      case OnboardingStep.key:
        return _buildKeyStep();
      case OnboardingStep.mnemonic:
        return _buildMnemonicStep();
      case OnboardingStep.biometric:
        return _buildBiometricStep();
      case OnboardingStep.complete:
        return _buildCompleteStep();
    }
  }

  Widget _buildWelcomeStep() {
    return Padding(
      key: const ValueKey('welcome'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.local_library,
            size: 120,
            color: AppTheme.primaryColor,
          ).animate().scale(duration: 600.ms),
          const SizedBox(height: 32),
          Text(
            'ALEXANDRIA',
            style: GoogleFonts.orbitron(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
              letterSpacing: 4,
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 16),
          Text(
            'Preserve Human Knowledge',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 48),
          Text(
            'A decentralized library where every piece of knowledge is immutable, verifiable, and eternal.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 600.ms),
          const SizedBox(height: 64),
          ElevatedButton(
            onPressed: () => ref.read(onboardingStepProvider.notifier).state =
                OnboardingStep.identity,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            child: const Text('BEGIN', style: TextStyle(letterSpacing: 2)),
          ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.2),
        ],
      ),
    );
  }

  Widget _buildIdentityStep() {
    return Padding(
      key: const ValueKey('identity'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.person_outline,
            size: 80,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(height: 24),
          Text(
            'Your Identity',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your identity in Alexandria is a cryptographic keypair. '
            'It cannot be duplicated, forged, or revoked by anyone.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          GlassCard(
            onTap: _isCreating ? null : () => _createNewIdentity(),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_circle_outline,
                      color: AppTheme.primaryColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create New Identity',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        Text(
                          'Generate a fresh Ed25519 keypair',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  if (_isCreating)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.arrow_forward_ios, color: Colors.white54),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            onTap: () => _showImportDialog(),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.download_outlined,
                      color: AppTheme.secondaryColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Import Existing Identity',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        Text(
                          'Restore from 24-word recovery phrase',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white54),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyStep() {
    return Padding(
      key: const ValueKey('key'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.vpn_key, size: 80, color: AppTheme.honorColor),
          const SizedBox(height: 24),
          Text(
            'Identity Created!',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your unique cryptographic identity has been generated and securely stored.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: AppTheme.honorColor),
                const SizedBox(width: 12),
                Text(
                  'Ed25519 Keypair Generated',
                  style: GoogleFonts.firaCode(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () => ref.read(onboardingStepProvider.notifier).state =
                OnboardingStep.mnemonic,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            child: const Text(
              'BACKUP YOUR KEY',
              style: TextStyle(letterSpacing: 2),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.read(onboardingStepProvider.notifier).state =
                OnboardingStep.biometric,
            child: const Text(
              'Skip for now',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMnemonicStep() {
    final mnemonic = ref.watch(mnemonicProvider);

    return Padding(
      key: const ValueKey('mnemonic'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text(
            'Recovery Phrase',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.dangerColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.dangerColor.withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning, color: AppTheme.dangerColor, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Write these words down and store them safely. Never share them.',
                    style: TextStyle(color: AppTheme.dangerColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (mnemonic == null)
            ElevatedButton(
              onPressed: _generateMnemonic,
              child: const Text('Generate Backup Phrase'),
            )
          else
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 2.5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: mnemonic.length,
                          itemBuilder: (context, index) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${index + 1}.',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      mnemonic[index],
                                      style: GoogleFonts.firaCode(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: mnemonic.join(' ')),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            ref.read(mnemonicProvider.notifier).state = null;
                            ref.read(onboardingStepProvider.notifier).state =
                                OnboardingStep.biometric;
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('I\'ve Saved It'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBiometricStep() {
    return Padding(
      key: const ValueKey('biometric'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.fingerprint,
            size: 100,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(height: 32),
          Text(
            'Secure Your Vault',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'Enable biometric authentication to protect your identity and content.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: _enableBiometric,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Enable Biometrics'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.read(onboardingStepProvider.notifier).state =
                OnboardingStep.complete,
            child: const Text('Skip', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteStep() {
    return Padding(
      key: const ValueKey('complete'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.honorColor.withValues(alpha: 0.2),
            ),
            child: const Icon(
              Icons.check_circle,
              size: 80,
              color: AppTheme.honorColor,
            ),
          ).animate().scale(duration: 400.ms),
          const SizedBox(height: 32),
          Text(
            'Welcome, Archivist',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 16),
          Text(
            'You are now part of the eternal library. Your contributions will be immutable and verifiable forever.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () async {
              // Mark onboarding as complete so app doesn't loop back
              final secureStorage = ref.read(secureStorageServiceProvider);
              await secureStorage.write('has_seen_onboarding', 'true');

              if (mounted) {
                await Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainScaffold()),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            child: const Text(
              'ENTER THE LIBRARY',
              style: TextStyle(letterSpacing: 2),
            ),
          ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2),
        ],
      ),
    );
  }

  Future<void> _createNewIdentity() async {
    setState(() => _isCreating = true);
    try {
      final identityService = ref.read(identityServiceProvider);
      await identityService.generateIdentity();
      ref.read(onboardingStepProvider.notifier).state = OnboardingStep.key;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _generateMnemonic() async {
    try {
      final mnemonicService = ref.read(mnemonicServiceProvider);
      final result = await mnemonicService.generateMnemonic();
      ref.read(mnemonicProvider.notifier).state = result.words;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _enableBiometric() async {
    try {
      final biometricService = ref.read(biometricServiceProvider);
      final success = await biometricService.authenticate();
      if (success) {
        ref.read(onboardingStepProvider.notifier).state =
            OnboardingStep.complete;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Biometric not available: $e')));
      }
    }
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Import Recovery Phrase',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 400,
          height: 400,
          child: Column(
            children: [
              const Text(
                'Enter your 24-word recovery phrase:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.5,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 24,
                  itemBuilder: (context, index) {
                    return TextField(
                      controller: _wordControllers[index],
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        prefixText: '${index + 1}. ',
                        prefixStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final words = _wordControllers
                  .map((c) => c.text.trim().toLowerCase())
                  .toList();
              await _importMnemonic(words);
              if (mounted) navigator.pop();
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  Future<void> _importMnemonic(List<String> words) async {
    try {
      final mnemonicService = ref.read(mnemonicServiceProvider);
      final identity = await mnemonicService.recoverFromMnemonic(words);
      if (identity != null) {
        ref.read(onboardingStepProvider.notifier).state =
            OnboardingStep.complete;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid recovery phrase')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
