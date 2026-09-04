import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/security_models.dart';
import '../../providers/security_providers.dart';
import '../../services/encryption_service.dart';

class AccessControlScreen extends ConsumerWidget {
  const AccessControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCid = ref.watch(selectedCidProvider);
    final aclAsync = selectedCid != null
        ? ref.watch(documentAclProvider(selectedCid))
        : const AsyncData<List<AccessPolicy>>([]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Control'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, 'Document'),
            const SizedBox(height: 16),
            _buildDocumentSelector(context, ref),
            const SizedBox(height: 48),
            _buildSectionTitle(context, 'Grant Access'),
            const SizedBox(height: 16),
            _buildPeerInputCard(context, ref, selectedCid ?? ''),
            const SizedBox(height: 48),
            _buildSectionTitle(context, 'Current Permissions'),
            const SizedBox(height: 16),
            aclAsync.when(
              data: (policies) => _buildAclList(context, ref, policies),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Failed to load access list: $err'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildDocumentSelector(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final documentsAsync = ref.watch(documentsProvider);
    final selectedCid = ref.watch(selectedCidProvider);

    return documentsAsync.when(
      data: (documents) {
        if (documents.isEmpty) {
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No documents available'),
            ),
          );
        }

        if (selectedCid == null) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedCidProvider.notifier).state = documents.first.cid;
          });
        }

        final validValue =
            documents.any((d) => d.cid == selectedCid) ? selectedCid : null;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Selected document',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
              ),
              isEmpty: validValue == null,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: validValue,
                  isExpanded: true,
                  isDense: true,
                  hint: const Text('Select a document'),
                  items: documents.map((document) {
                    return DropdownMenuItem<String>(
                      value: document.cid,
                      child: Text('${document.title} (${document.cid})'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(selectedCidProvider.notifier).state = value;
                  },
                ),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Failed to load documents: $err')),
    );
  }

  Widget _buildPeerInputCard(
    BuildContext context,
    WidgetRef ref,
    String selectedCid,
  ) {
    final theme = Theme.of(context);
    final peerDid = ref.watch(peerDidProvider);
    final hasDocuments =
        ref.watch(documentsProvider).valueOrNull?.isNotEmpty ?? false;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Peer DID',
                hintText: 'did:peer:example',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                ref.read(peerDidProvider.notifier).state = value;
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: peerDid.isEmpty || !hasDocuments
                      ? null
                      : () async {
                          await ref
                              .read(accessControlServiceProvider)
                              .grantAccess(selectedCid, peerDid);
                          ref.read(peerDidProvider.notifier).state = '';
                          ref.invalidate(documentAclProvider(selectedCid));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Access granted')),
                          );
                        },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Grant'),
                ),
                OutlinedButton.icon(
                  onPressed: peerDid.isEmpty || !hasDocuments
                      ? null
                      : () async {
                          final data = Uint8List.fromList(
                            List.generate(32, (index) => index),
                          );
                          final encrypted = await ref
                              .read(encryptionServiceProvider)
                              .encryptForPeer(data, peerDid);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Encrypted ${encrypted.length} bytes for peer',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Encrypt for peer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAclList(
    BuildContext context,
    WidgetRef ref,
    List<AccessPolicy> policies,
  ) {
    if (policies.isEmpty) {
      return Text(
        'No permissions granted for this document',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: policies.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final policy = policies[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              child: const Icon(Icons.person_outline),
            ),
            title: Text(
              policy.peerDid,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            subtitle: Text(
              'Granted: ${_formatTimestamp(policy.grantedAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Revoke access',
              onPressed: () async {
                await ref
                    .read(accessControlServiceProvider)
                    .revokeAccess(policy.cid, policy.peerDid);
                ref.invalidate(documentAclProvider(policy.cid));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Access revoked')),
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
