import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/identity_service.dart';
import '../profile_screen.dart';
import '../theme/app_theme.dart';

/// App-bar trailing action reflecting the node's cryptographic identity.
///
/// With an identity it renders an identicon-style avatar seeded from the
/// public key; without one it renders a subtle "Create identity" nudge.
/// Both affordances route to [ProfileScreen], which hosts the full
/// generate/recover/backup flows.
class IdentityAvatarAction extends ConsumerStatefulWidget {
  const IdentityAvatarAction({super.key});

  @override
  ConsumerState<IdentityAvatarAction> createState() =>
      _IdentityAvatarActionState();
}

class _IdentityAvatarActionState extends ConsumerState<IdentityAvatarAction> {
  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identityAsync = ref.watch(identityStateProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Center(
        child: identityAsync.when(
          data: (identity) => identity == null
              ? _buildCreateIdentityNudge(context)
              : _buildAvatar(context, identity),
          loading: () => _buildLoading(),
          // An unreadable keychain is indistinguishable from "no identity
          // yet" for navigation purposes - the Profile screen's own
          // guarded flows handle the underlying state.
          error: (_, __) => _buildCreateIdentityNudge(context),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.4),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.all(7.0),
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: AppTheme.secondaryColor,
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, AlexandriaIdentity identity) {
    final pubkey = identity.publicKeyBase58;
    final initials =
        pubkey.length >= 2 ? pubkey.substring(0, 2).toUpperCase() : '?';

    return Tooltip(
      message: 'Profile — Archivist ${identity.shortId}',
      child: InkWell(
        onTap: _openProfile,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primaryAccent.withValues(alpha: 0.18),
            border: Border.all(
              color: AppTheme.primaryAccent.withValues(alpha: 0.7),
              width: 1.2,
            ),
          ),
          child: Center(
            child: Text(
              initials,
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateIdentityNudge(BuildContext context) {
    return Tooltip(
      message: 'Create your cryptographic identity',
      child: InkWell(
        onTap: _openProfile,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primaryAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.primaryAccent.withValues(alpha: 0.35),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_add_alt_1,
                size: 13,
                color: AppTheme.primaryAccent,
              ),
              SizedBox(width: 6),
              Text(
                'Create Identity',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
