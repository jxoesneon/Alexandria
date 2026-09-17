import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart';
import '../providers/security_providers.dart';
import '../services/identity_service.dart';
import '../services/ledger_service.dart';
import '../services/ipfs_service.dart';
import '../services/mnemonic_service.dart';
import 'widgets/glass_card.dart';
import 'theme/app_theme.dart';
import 'widgets/contribution_graph.dart';
import 'widgets/info_glass.dart';

/// Provider for reputation from ledger
final reputationProvider = Provider<double>((ref) {
  final ledgerService = ref.watch(ledgerServiceProvider);
  return ledgerService.totalReputation;
});

/// Provider for pinned content count
final pinnedCountProvider = Provider<int>((ref) {
  final ipfsService = ref.watch(ipfsServiceProvider);
  return ipfsService.pinnedCids.length;
});

final userActivityProvider = FutureProvider.family<Map<DateTime, int>, String>((
  ref,
  publicKey,
) async {
  final db = ref.watch(databaseProvider);
  final dates = await db.getUserActivityDates(publicKey);
  return ContributionGraph.normalizeData(dates);
});

final myProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.getProfileByPublicKey('me');
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityStateProvider);
    final reputation = ref.watch(reputationProvider);
    final pinnedCount = ref.watch(pinnedCountProvider);
    final theme = AppTheme.darkTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.backup),
            tooltip: 'Backup Identity',
            onPressed: () => _showBackupDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Copy public key',
            onPressed: () => _sharePublicKey(context, identityAsync.value),
          ),
        ],
      ),
      body: identityAsync.when(
        data: (identity) => _buildContent(
          context,
          ref,
          identity,
          reputation,
          pinnedCount,
          theme,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _sharePublicKey(
    BuildContext context,
    AlexandriaIdentity? identity,
  ) async {
    final publicKey = identity?.publicKeyBase58;
    if (publicKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No identity to share yet.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: publicKey));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Public key copied to clipboard')),
      );
    }
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    AlexandriaIdentity? identity,
    double reputation,
    int pinnedCount,
    ThemeData theme,
  ) {
    final publicKeyDisplay = identity?.publicKeyBase58 ?? 'No Identity';
    final shortId = identity?.shortId ?? '???';
    final storedBytesAsync = ref.watch(storedBytesProvider);
    final ipfs = ref.watch(ipfsServiceProvider);
    final storedBytes = storedBytesAsync.valueOrNull ?? ipfs.storedBytes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Profile Header
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: identity != null
                                ? AppTheme.primaryAccent
                                : AppTheme.secondaryColor,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryAccent.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Icon(
                          identity != null
                              ? Icons.verified_user
                              : Icons.person_off,
                          size: 40,
                          color: identity != null
                              ? AppTheme.primaryAccent
                              : AppTheme.secondaryColor,
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  identity != null ? 'ACTIVE' : 'NO IDENTITY',
                                  style: TextStyle(
                                    color: identity != null
                                        ? AppTheme.primaryAccent
                                        : AppTheme.secondaryColor,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: InfoGlass(
                                    title: 'Cryptographic Identity',
                                    description:
                                        'Your identity is derived from your Ed25519 Public Key. It is mathematically unique and cannot be forged.',
                                    small: true,
                                    color: AppTheme.primaryAccent.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              identity != null
                                  ? 'Archivist $shortId'
                                  : 'Create Identity',
                              style: theme.textTheme.displayMedium?.copyWith(
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryAccent.withValues(
                                  alpha: 0.2,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                publicKeyDisplay.length > 20
                                    ? '${publicKeyDisplay.substring(0, 16)}...'
                                    : publicKeyDisplay,
                                style: const TextStyle(
                                  fontFamily: 'JetBrainsMono',
                                  fontSize: 10,
                                  color: AppTheme.primaryAccent,
                                ),
                              ),
                            ),
                            if (identity == null) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        _createIdentity(context, ref),
                                    icon: const Icon(Icons.vpn_key, size: 16),
                                    label: const Text('Generate Identity'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryAccent,
                                      foregroundColor: Colors.black,
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _showRecoverDialog(context, ref),
                                    icon: const Icon(
                                      Icons.restore,
                                      size: 16,
                                    ),
                                    label: const Text('Recover from Mnemonic'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.primaryAccent,
                                      side: BorderSide(
                                        color:
                                            AppTheme.primaryAccent.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: AppTheme.surfaceColor),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatItem(
                        label: 'REPUTATION',
                        value: reputation.toStringAsFixed(0),
                        color: AppTheme.honorColor,
                        hint:
                            'Earned by verifying content. Higher rep = more voting weight.',
                      ),
                      _StatItem(
                        label: 'ARTIFACTS',
                        value: '$pinnedCount',
                        color: AppTheme.primaryAccent,
                        hint:
                            'Number of unique CIDs you have permanently pinned.',
                      ),
                      _StatItem(
                        label: 'STORAGE',
                        value: _formatBytes(storedBytes),
                        color: AppTheme.secondaryColor,
                        hint:
                            'Total disk space used by your pinned IPFS blocks.',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Contribution Graph Section
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preservation activity',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 110,
                    child: identity == null
                        ? const Center(
                            child: Text(
                              'Create an identity to track preservation activity.',
                              style: TextStyle(color: AppTheme.secondaryColor),
                            ),
                          )
                        : ref
                            .watch(
                              userActivityProvider(identity.publicKeyBase58),
                            )
                            .when(
                              data: (data) =>
                                  ContributionGraph(activityData: data),
                              loading: () => const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              error: (_, __) => const Center(
                                child: Text(
                                  'Activity unavailable.',
                                  style:
                                      TextStyle(color: AppTheme.secondaryColor),
                                ),
                              ),
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createIdentity(BuildContext context, WidgetRef ref) async {
    final identityService = ref.read(identityServiceProvider);
    try {
      // Never silently overwrite a stored identity - even when the
      // provider reports none, storage may still hold one (stale
      // cache). If a key exists, require explicit confirmation first.
      var identityExists = false;
      try {
        identityExists = await identityService.hasIdentity();
      } catch (_) {
        // Cannot determine - proceed; generateIdentity is verified.
      }
      if (identityExists) {
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            title: const Text(
              'Replace existing identity?',
              style: TextStyle(color: AppTheme.textColor),
            ),
            content: const Text(
              'An identity already exists on this device. Replacing it '
              'permanently loses the old keypair and every claim bound '
              'to its public key — unless you saved the recovery phrase.',
              style: TextStyle(color: AppTheme.secondaryColor),
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
                  foregroundColor: AppTheme.canvasColor,
                ),
                child: const Text('Replace identity'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }

      await identityService.generateIdentity();
      ref.invalidate(identityStateProvider);
      ref.invalidate(activeIdentitiesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Identity created successfully!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showBackupDialog(BuildContext context, WidgetRef ref) async {
    final mnemonicService = ref.read(mnemonicServiceProvider);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BackupDialog(mnemonicService: mnemonicService),
    );
  }

  Future<void> _showRecoverDialog(BuildContext context, WidgetRef ref) async {
    final mnemonicService = ref.read(mnemonicServiceProvider);
    final controller = TextEditingController();

    // Recovering REPLACES the stored identity - warn first when one
    // exists, even if the UI currently shows none (stale cache).
    var identityExists = false;
    try {
      identityExists = await ref.read(identityServiceProvider).hasIdentity();
    } catch (_) {
      // Cannot determine - proceed; recovery is user-initiated and the
      // write itself is verified by IdentityService.
    }
    if (identityExists) {
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: const Text(
            'Replace existing identity?',
            style: TextStyle(color: AppTheme.textColor),
          ),
          content: const Text(
            'An identity already exists on this device. Recovering '
            'replaces it permanently — the old keypair and every claim '
            'bound to its public key will be lost unless you saved its '
            'recovery phrase.',
            style: TextStyle(color: AppTheme.secondaryColor),
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
                foregroundColor: AppTheme.canvasColor,
              ),
              child: const Text('Replace identity'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!context.mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text(
          'Recover Identity',
          style: TextStyle(color: AppTheme.textColor),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your 24-word recovery phrase, separated by spaces.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 4,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  color: AppTheme.textColor,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'abandon ability able about ...',
                  hintStyle: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    color: AppTheme.secondaryColor,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: AppTheme.canvasColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryAccent,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Recover'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final phrase = controller.text.trim().toLowerCase();
    final words =
        phrase.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    if (words.length != 24) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid mnemonic phrase')),
        );
      }
      return;
    }

    AlexandriaIdentity? identity;
    try {
      identity = await mnemonicService.recoverFromMnemonic(words);
    } catch (e) {
      // Surface persistence/verification failures (e.g. the StateError
      // thrown when an identity write fails post-write verification)
      // instead of an unhandled async error.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Recovery failed: $e',
              style: const TextStyle(color: AppTheme.canvasColor),
            ),
            backgroundColor: AppTheme.dangerColor,
          ),
        );
      }
      return;
    }
    if (identity != null) {
      // The stored identity was replaced: refresh every provider that
      // derives from it (identity, active keypairs) so no stale
      // DID/pubkey survives.
      ref.invalidate(identityStateProvider);
      ref.invalidate(activeIdentitiesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Identity recovered successfully!'),
            backgroundColor: AppTheme.honorColor,
          ),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Invalid mnemonic phrase',
              style: TextStyle(color: AppTheme.canvasColor),
            ),
            backgroundColor: AppTheme.dangerColor,
          ),
        );
      }
    }
  }
}

class _BackupDialog extends StatefulWidget {
  final MnemonicService mnemonicService;

  const _BackupDialog({required this.mnemonicService});

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  MnemonicResult? _mnemonic;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMnemonic();
  }

  Future<void> _loadMnemonic() async {
    try {
      final result = await widget.mnemonicService.backupCurrentIdentity();
      if (mounted) {
        setState(() {
          _mnemonic = result;
          _error = result == null ? 'No identity found to backup.' : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceColor,
      title: const Text(
        'Backup Identity',
        style: TextStyle(color: AppTheme.textColor),
      ),
      content: _buildContent(),
      actions: [
        if (_mnemonic != null)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: _mnemonic!.phrase),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Phrase copied to clipboard')),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
          ),
        if (_mnemonic != null)
          ElevatedButton(
            onPressed: () async {
              // Write the backup marker only on this explicit
              // confirmation - the security dashboard's "back up your
              // identity" alert tracks what the user actually did, not
              // that the dialog was opened.
              try {
                await widget.mnemonicService
                    .markBackupConfirmed(_mnemonic!.phrase);
              } catch (_) {
                // Non-fatal: the phrase was displayed; the security
                // screen will keep warning until a backup is confirmed.
              }
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text("I've saved it"),
          ),
      ],
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return SizedBox(
        width: 320,
        child: Text(
          _error!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (_mnemonic == null) {
      return const SizedBox(
        width: 320,
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final words = _mnemonic!.words;

    return SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your 24-word recovery phrase:',
              style: TextStyle(
                color: AppTheme.primaryAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.canvasColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.3),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: words.length,
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 9,
                          ),
                        ),
                        Text(
                          words[index],
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            color: AppTheme.textColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.dangerColor.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.dangerColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Write these words down and store them safely. '
                      'Anyone with this phrase can recover your identity. '
                      'This will never be shown again.',
                      style: TextStyle(
                        color: AppTheme.dangerColor.withValues(alpha: 0.9),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String hint;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Newsreader',
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: hint,
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.secondaryColor,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
