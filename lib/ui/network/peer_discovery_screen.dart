import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/network_models.dart';
import '../../providers/network_providers.dart';
import '../../services/mesh_transport_service.dart';

class PeerDiscoveryScreen extends ConsumerStatefulWidget {
  const PeerDiscoveryScreen({super.key});

  @override
  ConsumerState<PeerDiscoveryScreen> createState() =>
      _PeerDiscoveryScreenState();
}

class _PeerDiscoveryScreenState extends ConsumerState<PeerDiscoveryScreen> {
  final _multiaddrController = TextEditingController();

  @override
  void dispose() {
    _multiaddrController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peersAsync = ref.watch(peerListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peer Discovery & Mesh'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add peer',
        onPressed: () async {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Add peer'),
              content: TextField(
                autofocus: true,
                controller: _multiaddrController,
                decoration: const InputDecoration(
                  labelText: 'Multiaddr',
                  hintText: '/ip4/.../tcp/4001/p2p/...',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final multiaddr = _multiaddrController.text.trim();
                    if (multiaddr.isNotEmpty) {
                      _registerPeer(multiaddr);
                    }
                    _multiaddrController.clear();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: peersAsync.when(
          data: (peers) => _buildPeerList(context, ref, peers),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Text(
              'Error loading peers: $err',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ),
      ),
    );
  }

  void _registerPeer(String multiaddr) {
    final mesh = ref.read(meshTransportServiceProvider);
    var peerId = _peerIdFromMultiaddr(multiaddr);
    peerId ??= const Uuid().v4();
    mesh.registerPeer(
      MeshPeer(
        peerId: peerId,
        address: multiaddr,
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
      ),
    );
  }

  String? _peerIdFromMultiaddr(String multiaddr) {
    final match = RegExp(r'/p2p/([^/]+)$').firstMatch(multiaddr);
    return match?.group(1);
  }

  Widget _buildPeerList(BuildContext context, WidgetRef ref, List<Peer> peers) {
    final theme = Theme.of(context);

    if (peers.isEmpty) {
      return Center(
        child: Text(
          'No peers discovered',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: peers.length,
      itemBuilder: (context, index) {
        final peer = peers[index];
        return _buildPeerCard(context, ref, peer);
      },
    );
  }

  Widget _buildPeerCard(BuildContext context, WidgetRef ref, Peer peer) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (statusColor, statusLabel) = switch (peer.status) {
      PeerStatus.connected => (colorScheme.primary, 'Connected'),
      PeerStatus.pending => (colorScheme.tertiary, 'Pending'),
      PeerStatus.disconnected => (colorScheme.error, 'Disconnected'),
    };

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          child: const Icon(Icons.hub_outlined),
        ),
        title: Text(
          peer.peerId,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                peer.multiaddr,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Latency: ${peer.latencyMs} ms',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                statusLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        trailing: _buildPeerActions(context, ref, peer),
      ),
    );
  }

  Widget _buildPeerActions(BuildContext context, WidgetRef ref, Peer peer) {
    final mesh = ref.read(meshTransportServiceProvider);

    if (peer.status == PeerStatus.pending) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.0),
        ),
      );
    }

    if (peer.status == PeerStatus.connected) {
      return IconButton(
        icon: const Icon(Icons.link_off),
        tooltip: 'Disconnect',
        onPressed: () async {
          await mesh.disconnectPeer(peer.peerId);
        },
      );
    }

    return IconButton(
      icon: const Icon(Icons.link),
      tooltip: 'Connect',
      onPressed: () async {
        await mesh.connectToPeer(peer.multiaddr);
      },
    );
  }
}
