import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/security_providers.dart';
import '../services/identity_service.dart';
import '../services/mnemonic_service.dart';
import '../services/biometric_service.dart';
import '../services/secure_storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_card.dart';
import 'onboarding/first_run_wizard_dialog.dart';
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
  bool _isImporting = false;
  final _mnemonicController = TextEditingController();
  final _pasteAllController = TextEditingController();
  final List<TextEditingController> _wordControllers = List.generate(
    24,
    (_) => TextEditingController(),
  );

  @override
  void dispose() {
    _mnemonicController.dispose();
    _pasteAllController.dispose();
    for (final controller in _wordControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(onboardingStepProvider);

    return Scaffold(
      backgroundColor: AppTheme.canvasColor,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _buildStep(step),
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
            Icons.auto_stories,
            size: 120,
            color: AppTheme.primaryAccent,
          ),
          const SizedBox(height: 32),
          const Text(
            'Alexandria',
            style: TextStyle(
              fontFamily: 'Newsreader',
              fontSize: 36,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.5,
              color: AppTheme.textColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Preserve Human Knowledge',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Text(
            'A decentralized library where every edition is content-addressed and verified against its CID.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppTheme.secondaryColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 64),
          ElevatedButton(
            onPressed: () => ref.read(onboardingStepProvider.notifier).state =
                OnboardingStep.identity,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            child: const Text('Begin', style: TextStyle(letterSpacing: 0)),
          ),
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
            color: AppTheme.primaryAccent,
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
            ).textTheme.bodyLarge?.copyWith(color: AppTheme.secondaryColor),
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
                      color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_circle_outline,
                      color: AppTheme.primaryAccent,
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
                              ?.copyWith(color: AppTheme.secondaryColor),
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
                    const Icon(Icons.arrow_forward_ios,
                        color: AppTheme.secondaryColor),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            onTap: (_isCreating || _isImporting)
                ? null
                : () => _showImportDialog(),
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
                              ?.copyWith(color: AppTheme.secondaryColor),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      color: AppTheme.secondaryColor),
                ],
              ),
            ),
          ),
          // Upgrade path: an identity already exists on this device, so
          // offer a non-destructive way through instead of forcing
          // replace-or-import.
          if (ref.watch(identityStateProvider).valueOrNull != null) ...[
            const SizedBox(height: 16),
            GlassCard(
              onTap: () => ref.read(onboardingStepProvider.notifier).state =
                  OnboardingStep.biometric,
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: AppTheme.honorColor,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Continue with existing identity',
                      style: TextStyle(color: AppTheme.honorColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
            ).textTheme.bodyLarge?.copyWith(color: AppTheme.secondaryColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: AppTheme.honorColor),
                const SizedBox(width: 12),
                Text(
                  'Ed25519 Keypair Generated',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            child: const Text(
              'Backup your key',
              style: TextStyle(letterSpacing: 0),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.read(onboardingStepProvider.notifier).state =
                OnboardingStep.biometric,
            child: const Text(
              'Skip for now',
              style: TextStyle(color: AppTheme.secondaryColor),
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
                                      style: const TextStyle(
                                        fontFamily: 'JetBrainsMono',
                                        color: Colors.white,
                                        fontSize: 14,
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
                            foregroundColor:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            // The backup marker is written only on this
                            // explicit confirmation - not when the phrase
                            // is merely shown - so the security
                            // dashboard's "back up your identity" alert
                            // tracks what the user actually did.
                            try {
                              await ref
                                  .read(mnemonicServiceProvider)
                                  .markBackupConfirmed(mnemonic.join(' '));
                            } catch (_) {
                              // Non-fatal: the phrase was shown; the
                              // security screen will keep warning.
                            }
                            ref.read(mnemonicProvider.notifier).state = null;
                            ref.read(onboardingStepProvider.notifier).state =
                                OnboardingStep.biometric;
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryAccent,
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
            color: AppTheme.primaryAccent,
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
            ).textTheme.bodyLarge?.copyWith(color: AppTheme.secondaryColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: _enableBiometric,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Enable Biometrics'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () async {
              // Skipping still ends onboarding - record it so the gate
              // doesn't loop back to the welcome flow on next launch.
              final secureStorage = ref.read(secureStorageServiceProvider);
              await secureStorage.write('has_seen_onboarding', 'true');
              ref.read(onboardingStepProvider.notifier).state =
                  OnboardingStep.complete;
            },
            child: const Text('Skip',
                style: TextStyle(color: AppTheme.secondaryColor)),
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
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome, Archivist',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'You are ready. Editions you publish are content-addressed and signed by your key.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppTheme.secondaryColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () async {
              // Mark onboarding as complete so app doesn't loop back
              final secureStorage = ref.read(secureStorageServiceProvider);
              await secureStorage.write('has_seen_onboarding', 'true');

              if (!mounted) return;
              // First-run setup (credits/PoCH/seed ingest) runs as a
              // dialog before landing on the library.
              await FirstRunWizardDialog.show(context);
              if (mounted) {
                await Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainScaffold()),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            child: const Text(
              'Enter the library',
              style: TextStyle(letterSpacing: 0),
            ),
          ),
        ],
      ),
    );
  }

  /// Warn before destroying an existing (possibly funded) keypair.
  /// Returns true when the user explicitly confirms the replacement.
  Future<bool> _confirmIdentityReplacement() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text(
          'Replace existing identity?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'An identity already exists on this device. Replacing it '
          'permanently loses the old keypair and every claim bound to '
          'its public key — unless you saved the recovery phrase.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            child: const Text('Replace identity'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _createNewIdentity() async {
    final identityService = ref.read(identityServiceProvider);
    // Never silently overwrite a stored identity - it may be funded or
    // bound to claims. If we cannot determine whether one exists, warn
    // rather than risk destroying it.
    bool identityExists;
    try {
      identityExists = await identityService.hasIdentity();
    } catch (_) {
      identityExists = true;
    }
    if (identityExists && !(await _confirmIdentityReplacement())) {
      return;
    }
    if (!mounted) return;
    setState(() => _isCreating = true);
    try {
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
      // Derive the phrase FROM the stored private key so it actually
      // backs up the identity created above. A fresh random mnemonic
      // (generateMnemonic) would silently recover a DIFFERENT keypair.
      final result = await mnemonicService.backupCurrentIdentity();
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No identity found to back up.'),
          ),
        );
        return;
      }
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
        backgroundColor: AppTheme.surfaceColor,
        title: const Text(
          'Import Recovery Phrase',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 400,
          height: 440,
          child: Column(
            children: [
              Text(
                'Enter your 24-word recovery phrase:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pasteAllController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Paste all 24 words separated by spaces',
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 14),
                  prefixIcon: const Icon(
                    Icons.content_paste,
                    size: 18,
                    color: Colors.white38,
                  ),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onChanged: (text) {
                  if (text.trim().split(RegExp(r'\s+')).length > 1) {
                    _distributePastedWords(text);
                  }
                },
                onSubmitted: _distributePastedWords,
              ),
              const SizedBox(height: 12),
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
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        prefixText: '${index + 1}. ',
                        prefixStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
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
            onPressed: _isImporting
                ? null
                : () async {
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

  /// Distributes a pasted phrase across the per-word fields so users can
  /// paste the whole recovery phrase at once instead of typing 24 cells.
  void _distributePastedWords(String raw) {
    final words = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return;
    for (var i = 0; i < _wordControllers.length; i++) {
      _wordControllers[i].text = i < words.length ? words[i] : '';
    }
    _pasteAllController.clear();
  }

  Future<void> _importMnemonic(List<String> words) async {
    // Debounce: a double-tap on Import must not interleave two identity
    // replacements (the writes are serialized in IdentityService, but a
    // second call would still redundantly re-import).
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      // Recovering REPLACES any stored identity - confirm before
      // destroying a possibly funded keypair, even if the UI believes
      // none exists (stale cache). If existence cannot be determined,
      // proceed: the write itself is verified by IdentityService.
      try {
        if (await ref.read(identityServiceProvider).hasIdentity()) {
          if (!mounted) return;
          if (!(await _confirmIdentityReplacement())) return;
        }
      } catch (_) {
        // hasIdentity failed - proceed with the user-initiated import.
      }
      if (!mounted) return;
      final mnemonicService = ref.read(mnemonicServiceProvider);
      final identity = await mnemonicService.recoverFromMnemonic(words);
      if (!mounted) return;
      if (identity != null) {
        // The stored identity was just replaced - refresh every
        // identity-derived provider so the rest of the app sees the
        // recovered keypair, not a previously cached one.
        ref.invalidate(identityStateProvider);
        ref.invalidate(activeIdentitiesProvider);
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
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }
}
