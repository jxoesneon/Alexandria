import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/database.dart';
import '../main.dart';
import '../services/identity_service.dart';
import '../services/ledger_service.dart';
import '../services/ipfs_service.dart';
import 'widgets/glass_card.dart';
import 'theme/app_theme.dart';
import 'widgets/contribution_graph.dart';
import 'widgets/info_glass.dart';

/// Provider for identity data
final identityStateProvider = FutureProvider<AlexandriaIdentity?>((ref) async {
  final identityService = ref.watch(identityServiceProvider);
  return identityService.getIdentity();
});

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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'DIGITAL IDENTITY',
          style: theme.textTheme.headlineSmall?.copyWith(
            letterSpacing: 3,
            color: AppTheme.primaryColor,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.backup),
            tooltip: 'Backup Identity',
            onPressed: () => _showBackupDialog(context, ref),
          ),
          IconButton(icon: const Icon(Icons.share), onPressed: () {}),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1021), Color(0xFF1E293B)],
          ),
        ),
        child: identityAsync.when(
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
      ),
    );
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 100, 24, 120),
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
                                ? AppTheme.primaryColor
                                : Colors.grey,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withValues(
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
                              ? AppTheme.primaryColor
                              : Colors.grey,
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
                                  identity != null ? 'VERIFIED' : 'UNVERIFIED',
                                  style: TextStyle(
                                    color: identity != null
                                        ? AppTheme.primaryColor
                                        : Colors.grey,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InfoGlass(
                                  title: 'Cryptographic Identity',
                                  description:
                                      'Your identity is derived from your Ed25519 Public Key. It is mathematically unique and cannot be forged.',
                                  small: true,
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              identity != null
                                  ? 'Archivist $shortId'
                                  : 'Create Identity',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.2,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                publicKeyDisplay.length > 20
                                    ? '${publicKeyDisplay.substring(0, 16)}...'
                                    : publicKeyDisplay,
                                style: GoogleFonts.firaCode(
                                  fontSize: 10,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                            if (identity == null) ...[
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => _createIdentity(context, ref),
                                icon: const Icon(Icons.vpn_key, size: 16),
                                label: const Text('Generate Identity'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryColor,
                                  foregroundColor: Colors.black,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white10),
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
                        color: AppTheme.primaryColor,
                        hint:
                            'Number of unique CIDs you have permanently pinned.',
                      ),
                      const _StatItem(
                        label: 'STORAGE',
                        value: '1.2GB',
                        color: AppTheme.secondaryColor,
                        hint:
                            'Total disk space used by your pinned IPFS blocks.',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
          const SizedBox(height: 24),

          // Contribution Graph Section
          GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRESERVATION ACTIVITY',
                        style: TextStyle(
                          color: AppTheme.primaryColor.withValues(alpha: 0.8),
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(
                        height: 110,
                        child: ContributionGraph(activityData: {}),
                      ),
                    ],
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 100.ms)
              .slideY(begin: 0.1),
          const SizedBox(height: 24),

          // Badges Section
          GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EARNED BADGES',
                        style: TextStyle(
                          color: AppTheme.primaryColor.withValues(alpha: 0.8),
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Badge(
                            icon: Icons.shield,
                            label: 'Guardian',
                            color: Colors.amber,
                          ),
                          _Badge(
                            icon: Icons.auto_stories,
                            label: 'Keeper',
                            color: Colors.blue,
                          ),
                          _Badge(
                            icon: Icons.visibility,
                            label: 'Watchful',
                            color: Colors.green,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 200.ms)
              .slideY(begin: 0.1),
        ],
      ),
    );
  }

  Future<void> _createIdentity(BuildContext context, WidgetRef ref) async {
    final identityService = ref.read(identityServiceProvider);
    try {
      await identityService.generateIdentity();
      ref.invalidate(identityStateProvider);
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
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Backup Identity',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Identity backup with BIP-39 mnemonic will be available in a future update.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
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
              style: GoogleFonts.orbitron(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            InfoGlass(
              title: label,
              description: hint,
              small: true,
              color: color.withValues(alpha: 0.7),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
