import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/security_models.dart';
import '../../providers/security_providers.dart';

class KeyManagementScreen extends ConsumerWidget {
  const KeyManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identitiesAsync = ref.watch(activeIdentitiesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Key Management'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    await ref
                        .read(keyManagementServiceProvider)
                        .generateNewKeypair(KeyType.ed25519);
                    if (!context.mounted) return;
                    ref.invalidate(activeIdentitiesProvider);
                    await ref.read(activeIdentitiesProvider.future);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Generate new key'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _showResolveInputDialog(context, ref),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Resolve DID'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Active identities',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: identitiesAsync.when(
                data: (identities) =>
                    _buildIdentitiesList(context, ref, identities),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Text(
                    'Error loading identities: $err',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentitiesList(
    BuildContext context,
    WidgetRef ref,
    List<Keypair> identities,
  ) {
    if (identities.isEmpty) {
      return Text(
        'No identities found',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    return ListView.separated(
      itemCount: identities.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final keypair = identities[index];
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
              child: const Icon(Icons.key_outlined),
            ),
            title: Text(
              keypair.type.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Created: ${_formatDate(keypair.createdAt)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    keypair.did,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.download_outlined),
                  tooltip: 'Export private key',
                  onPressed: () => _showExportDialog(context, ref, keypair),
                ),
                IconButton(
                  icon: const Icon(Icons.verified_user_outlined),
                  tooltip: 'Resolve DID',
                  onPressed: () => _resolveDid(context, ref, keypair.did),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showExportDialog(
    BuildContext context,
    WidgetRef ref,
    Keypair keypair,
  ) async {
    final passwordController = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export private key'),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              hintText: 'Enter a password to protect the export',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final result = await ref
                    .read(keyManagementServiceProvider)
                    .exportPrivateKey(
                      keypair.id,
                      passwordController.text,
                    );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!context.mounted) return;
                await _showResultDialog(context, 'Exported key', result);
              },
              child: const Text('Export'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => passwordController.dispose());
    });
  }

  Future<void> _resolveDid(
    BuildContext context,
    WidgetRef ref,
    String did,
  ) async {
    final document = await ref.read(didServiceProvider).resolveDid(did);
    if (!context.mounted) return;
    await _showResultDialog(
      context,
      'Resolved DID',
      '${document.did}\n\nPublic keys:\n${document.publicKeys.join('\n')}',
    );
  }

  Future<void> _showResolveInputDialog(
      BuildContext context, WidgetRef ref) async {
    final didController = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Resolve DID'),
          content: TextField(
            controller: didController,
            decoration: const InputDecoration(
              labelText: 'DID',
              hintText: 'did:example:123',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final did = didController.text;
                if (did.isEmpty) return;
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!context.mounted) return;
                await _resolveDid(context, ref, did);
              },
              child: const Text('Resolve'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => didController.dispose());
    });
  }

  Future<void> _showResultDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SelectableText(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
