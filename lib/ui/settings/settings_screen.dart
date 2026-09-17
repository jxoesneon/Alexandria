import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/settings_logic.dart';
import '../../services/data_wipe_service.dart';
import '../../services/tor_service.dart';
import '../agent/agent_network_dialog.dart';
import '../alexandria_root.dart';
import '../common/alexandria_app_bar.dart';
import '../credits/credit_wallet_dialog.dart';
import '../plugin_screen.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final torService = ref.watch(torServiceProvider);
    final torStatus = ref.watch(torStatusProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: alexandriaAppBar(
        title: 'Settings',
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: 'Autonomous Agent Network (Moltbook & MCP)',
            onPressed: () => AgentNetworkDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Common Heritage Wallet (Credits & PoCH)',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const CreditWalletDialog(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.extension_outlined),
            tooltip: 'The Garden (Plugins & Themes)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PluginScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section 1: Appearance
          _buildSectionHeader(theme, 'Appearance'),
          GlassCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                ListTile(
                  title: const Text('Theme Mode'),
                  subtitle: const Text(
                      'Choose between system, dark void, or light themes'),
                  trailing: DropdownButton<ThemeMode>(
                    value: settings.themeMode,
                    underline: const SizedBox(),
                    onChanged: (mode) {
                      if (mode != null) settingsNotifier.setThemeMode(mode);
                    },
                    items: const [
                      DropdownMenuItem(
                          value: ThemeMode.system, child: Text('System')),
                      DropdownMenuItem(
                          value: ThemeMode.light, child: Text('Light')),
                      DropdownMenuItem(
                          value: ThemeMode.dark, child: Text('Dark Void')),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Reduced Motion'),
                  subtitle: const Text(
                      'Minimize interface animations and transitions'),
                  value: settings.reducedMotion,
                  onChanged: (val) => settingsNotifier.setReducedMotion(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 2: Network & Privacy
          _buildSectionHeader(theme, 'Network & Privacy'),
          GlassCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Route via Tor Proxy (SOCKS5)'),
                  subtitle: const Text(
                      'Enhance privacy by tunneling all P2P discovery through Tor (127.0.0.1:9050)'),
                  value: torService.isEnabled,
                  onChanged: (val) async {
                    if (val) {
                      ref.read(torStatusProvider.notifier).state =
                          TorStatus.connecting;
                      final success = await torService.enable();
                      ref.read(torStatusProvider.notifier).state =
                          success ? TorStatus.connected : TorStatus.error;
                    } else {
                      await torService.disable();
                      ref.read(torStatusProvider.notifier).state =
                          TorStatus.disabled;
                    }
                  },
                ),
                _buildTorStatusRow(torStatus),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 3: Storage & Maintenance
          _buildSectionHeader(theme, 'Storage & Maintenance'),
          GlassCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Prune Storage Cache'),
                  subtitle: const Text(
                      'Safely cleans up temporary unpinned cache blocks to free disk space'),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      await settingsNotifier.pruneIpfsRepo();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Storage cleanup completed successfully.')),
                        );
                      }
                    },
                    child: const Text('Prune'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined,
                      color: Colors.redAccent),
                  title: const Text('Emergency Data Wipe',
                      style: TextStyle(color: Colors.redAccent)),
                  subtitle: const Text(
                      'Permanently deletes identity, keys and all local data'),
                  onTap: () {
                    _showDataWipeDialog(context, ref);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          const Center(
            child: Text(
              'Alexandria v1.1.0 • P2P Protocol Active',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildTorStatusRow(TorStatus status) {
    final Color dotColor;
    final String label;

    switch (status) {
      case TorStatus.disabled:
        dotColor = Colors.grey;
        label = 'Tor Disabled';
        break;
      case TorStatus.connecting:
        dotColor = Colors.amber;
        label = 'Connecting to Tor Network...';
        break;
      case TorStatus.connected:
        dotColor = const Color(0xFF22C55E);
        label = 'Connected via Tor (127.0.0.1:9050)';
        break;
      case TorStatus.error:
        dotColor = const Color(0xFFEF4444);
        label = 'Tor Connection Failed — Check your Tor daemon';
        break;
    }

    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
      child: Row(
        children: [
          dot,
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: dotColor),
          ),
        ],
      ),
    );
  }

  void _showDataWipeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Emergency Data Wipe'),
        content: const Text(
          'This permanently deletes all local data on this device — identity keys, recovery phrase, library index, credit balance and cached content. It cannot be undone. Content pinned by other nodes on the network remains there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(dataWipeServiceProvider).wipe();
              } catch (e) {
                // Partial state is possible - say so instead of
                // claiming a clean wipe.
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Data wipe incomplete: $e. Some data may remain on this device.',
                    ),
                  ),
                );
                return;
              }
              if (!context.mounted) return;
              // Landing on onboarding IS the success signal: the wiped
              // keychain has no flag, so the rebuilt tree shows the
              // first-run flow.
              AlexandriaRoot.restart(context);
            },
            child: const Text('Confirm Wipe'),
          ),
        ],
      ),
    );
  }
}
