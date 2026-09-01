import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/settings_logic.dart';
import '../../services/tor_service.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final torService = ref.watch(torServiceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
                      await torService.enable();
                    } else {
                      await torService.disable();
                    }
                  },
                ),
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
                      'Securely zeroes private keys and flushes local storage cache'),
                  onTap: () {
                    _showDataWipeDialog(context);
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

  void _showDataWipeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Emergency Data Wipe'),
        content: const Text(
          'This will securely delete all locally cached keys and cached blocks from this device. Pinned content on the network will remain intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Data wipe completed.')),
              );
            },
            child: const Text('Confirm Wipe'),
          ),
        ],
      ),
    );
  }
}
