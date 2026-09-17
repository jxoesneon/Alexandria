import 'package:flutter/material.dart';
import '../profile_screen.dart';
import '../theme/app_theme.dart';

/// Why an identity-gated surface is locked.
enum IdentityRequiredReason { noIdentity, insufficientReputation }

/// Gate shown on surfaces that require an identity (or more
/// reputation) before the user can participate. The CTA routes to
/// [ProfileScreen], where identities are created and reputation is
/// tracked.
class IdentityRequiredCta extends StatelessWidget {
  final IdentityRequiredReason reason;

  const IdentityRequiredCta({super.key, required this.reason});

  const IdentityRequiredCta.noIdentity({super.key})
      : reason = IdentityRequiredReason.noIdentity;

  const IdentityRequiredCta.insufficientReputation({super.key})
      : reason = IdentityRequiredReason.insufficientReputation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needsIdentity = reason == IdentityRequiredReason.noIdentity;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.badge_outlined,
            color: AppTheme.secondaryColor,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            'Identity required',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            needsIdentity
                ? 'Create an identity to participate.'
                : 'Earn reputation by preserving and verifying content.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
              );
            },
            icon: Icon(needsIdentity ? Icons.vpn_key : Icons.person, size: 16),
            label: Text(needsIdentity ? 'Create identity' : 'View profile'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: AppTheme.canvasColor,
            ),
          ),
        ],
      ),
    );
  }
}
