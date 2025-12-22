import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:alexandria/ui/widgets/glass_card.dart';
import 'package:alexandria/logic/settings_logic.dart';
import 'package:alexandria/ui/governance_screen.dart';
import 'package:alexandria/ui/plugin_screen.dart';
import 'package:alexandria/ui/collection_screen.dart';
import 'package:alexandria/services/tor_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.canvasColor,
      // ... (AppBar remains same)
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'NETWORK PROTOCOL'),
            GlassCard(
              child: SwitchListTile(
                title: const Text(
                  'IPFS Swarm Mode',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Connect to global peer network',
                  style: TextStyle(color: Colors.white54),
                ),
                value: settings.ipfsSwarmMode,
                onChanged: (v) => settingsNotifier.setSwarmMode(v),
                activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.5),
                activeThumbColor: AppTheme.primaryColor,
              ),
            ).animate().fadeIn().slideX(),

            const SizedBox(height: 16),
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Gateway Selection',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    DropdownButton<String>(
                      value:
                          settings.availableGateways.contains(
                            settings.gatewayUrl,
                          )
                          ? settings.gatewayUrl
                          : null,
                      dropdownColor: AppTheme.surfaceColor,
                      underline: const SizedBox(),
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: AppTheme.primaryColor,
                      ),
                      style: const TextStyle(color: Colors.white),
                      items: [
                        ...settings.availableGateways.map(
                          (gw) => DropdownMenuItem(
                            value: gw,
                            child: Text(
                              gw
                                  .replaceAll('https://', '')
                                  .replaceAll('/ipfs', ''),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        const DropdownMenuItem(
                          value: 'custom_action',
                          child: Text(
                            'Add Custom...',
                            style: TextStyle(color: AppTheme.secondaryColor),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == 'custom_action') {
                          // Show Dialog
                          showDialog(
                            context: context,
                            builder: (context) {
                              final controller = TextEditingController();
                              return AlertDialog(
                                backgroundColor: AppTheme.surfaceColor,
                                title: const Text(
                                  'Add Custom Gateway',
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: TextField(
                                  controller: controller,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: 'https://my-gateway.io/ipfs',
                                    hintStyle: TextStyle(color: Colors.white30),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Colors.white30,
                                      ),
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      if (controller.text.isNotEmpty) {
                                        settingsNotifier.addCustomGateway(
                                          controller.text,
                                        );
                                        Navigator.pop(context);
                                      }
                                    },
                                    child: const Text('Add'),
                                  ),
                                ],
                              );
                            },
                          );
                        } else if (value != null) {
                          settingsNotifier.setGateway(value);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 100.ms).slideX(),

            const SizedBox(height: 32),
            const _SectionHeader(title: 'FEATURES'),

            GlassCard(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.how_to_vote,
                    color: AppTheme.primaryColor,
                  ),
                ),
                title: const Text(
                  'The Parliament',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Governance & proposals',
                  style: TextStyle(color: Colors.white54),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GovernanceScreen()),
                ),
              ),
            ).animate().fadeIn(delay: 150.ms).slideX(),

            const SizedBox(height: 12),
            GlassCard(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.extension,
                    color: AppTheme.secondaryColor,
                  ),
                ),
                title: const Text(
                  'The Garden',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Plugins & themes',
                  style: TextStyle(color: Colors.white54),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PluginScreen()),
                ),
              ),
            ).animate().fadeIn(delay: 175.ms).slideX(),

            const SizedBox(height: 12),
            GlassCard(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.honorColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.collections_bookmark,
                    color: AppTheme.honorColor,
                  ),
                ),
                title: const Text(
                  'The Scriptorium',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Collaborative collections',
                  style: TextStyle(color: Colors.white54),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CollectionScreen()),
                ),
              ),
            ).animate().fadeIn(delay: 200.ms).slideX(),

            const SizedBox(height: 32),
            const _SectionHeader(title: 'APPEARANCE'),
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Theme',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.settings_brightness),
                              label: Text('Auto'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode),
                              label: Text('Light'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode),
                              label: Text('Dark'),
                            ),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (newSelection) {
                            settingsNotifier.setThemeMode(newSelection.first);
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.selected)
                                  ? AppTheme.primaryColor
                                  : null,
                            ),
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.selected)
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10),
                    SwitchListTile(
                      title: const Text(
                        'Reduced Motion',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Disable heavy animations',
                        style: TextStyle(color: Colors.white54),
                      ),
                      value: settings.reducedMotion,
                      onChanged: (v) => settingsNotifier.setReducedMotion(v),
                      activeTrackColor: AppTheme.primaryColor.withValues(
                        alpha: 0.5,
                      ),
                      activeThumbColor: AppTheme.primaryColor,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 200.ms).slideX(),

            const SizedBox(height: 32),
            const _SectionHeader(title: 'STORAGE'),
            GlassCard(
              child: Column(
                children: [
                  ListTile(
                    title: const Text(
                      'Clear Cache',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Free up temporary space',
                      style: TextStyle(color: Colors.white54),
                    ),
                    trailing: const Icon(
                      Icons.cleaning_services,
                      color: AppTheme.primaryColor,
                    ),
                    onTap: () async {
                      await settingsNotifier.clearCache();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cache cleared')),
                        );
                      }
                    },
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  ListTile(
                    title: const Text(
                      'Prune IPFS Repo',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Run garbage collection',
                      style: TextStyle(color: Colors.white54),
                    ),
                    trailing: const Icon(
                      Icons.delete_sweep,
                      color: AppTheme.primaryColor,
                    ),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Running GC...')),
                      );
                      await settingsNotifier.pruneIpfsRepo();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Garbage collection complete'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 250.ms).slideX(),

            const SizedBox(height: 32),
            const _SectionHeader(title: 'SECURITY & PRIVACY'),

            GlassCard(
              child: SwitchListTile(
                title: const Text(
                  'Biometric Authentication',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Require FaceID/TouchID on launch',
                  style: TextStyle(color: Colors.white54),
                ),
                value: settings.biometricEnabled,
                onChanged: (v) => settingsNotifier.setBiometric(v),
                activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.5),
                activeThumbColor: AppTheme.primaryColor,
              ),
            ).animate().fadeIn(delay: 300.ms).slideX(),

            // Tor Toggle
            const SizedBox(height: 16),
            Consumer(
              builder: (context, ref, _) {
                final torService = ref.read(torServiceProvider);
                final torStatus = ref.watch(torStatusProvider);
                final isEnabled = torStatus == TorStatus.connected;

                return GlassCard(
                  child: SwitchListTile(
                    title: const Text(
                      'Tor Anonymous Routing',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      isEnabled
                          ? 'Connected via ${torService.proxyAddress}'
                          : 'Route IPFS requests through Tor',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    secondary: Icon(
                      Icons.security,
                      color: isEnabled ? AppTheme.honorColor : Colors.white38,
                    ),
                    value: isEnabled,
                    onChanged: (v) async {
                      if (v) {
                        ref.read(torStatusProvider.notifier).state =
                            TorStatus.connecting;
                        final success = await torService.enable();
                        ref.read(torStatusProvider.notifier).state = success
                            ? TorStatus.connected
                            : TorStatus.error;
                        if (!success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not connect to Tor. Is Tor running?',
                              ),
                            ),
                          );
                        }
                      } else {
                        await torService.disable();
                        ref.read(torStatusProvider.notifier).state =
                            TorStatus.disabled;
                      }
                    },
                    activeTrackColor: AppTheme.honorColor.withValues(
                      alpha: 0.5,
                    ),
                    activeThumbColor: AppTheme.honorColor,
                  ),
                );
              },
            ).animate().fadeIn(delay: 350.ms).slideX(),

            const SizedBox(height: 16),
            GlassCard(
              child: ListTile(
                title: const Text(
                  'Export Private Key',
                  style: TextStyle(color: AppTheme.honorColor),
                ),
                subtitle: const Text(
                  'View your Identity Key',
                  style: TextStyle(color: Colors.white54),
                ),
                trailing: const Icon(Icons.key, color: AppTheme.honorColor),
                onTap: () async {
                  final key = await settingsNotifier.exportPrivateKey();
                  if (key != null && context.mounted) {
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: AppTheme.surfaceColor,
                        title: const Text(
                          'Your Private Key',
                          style: TextStyle(color: Colors.white),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'WARNING: Never share this key. Anyone with this key controls your identity.',
                              style: TextStyle(
                                color: AppTheme.dangerColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SelectableText(
                              key,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    );
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Authentication failed')),
                    );
                  }
                },
              ),
            ).animate().fadeIn(delay: 400.ms).slideX(),

            const SizedBox(height: 16),
            GlassCard(
              child: ListTile(
                title: const Text(
                  'Burner Mode',
                  style: TextStyle(color: AppTheme.dangerColor),
                ),
                subtitle: const Text(
                  'Wipe all data & reset app',
                  style: TextStyle(color: Colors.white54),
                ),
                trailing: const Icon(
                  Icons.delete_forever,
                  color: AppTheme.dangerColor,
                ),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppTheme.surfaceColor,
                      title: const Text(
                        'Activate Burner Mode?',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: const Text(
                        'This will permanently delete your identity, database, and settings. This action cannot be undone.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final success = await settingsNotifier
                                .performBurnerMode();
                            if (success && context.mounted) {
                              // Reset to root (Onboarding)
                              // In a real app we might use a restarting mechanism.
                              // Here we assume main.dart watches app state or we navigate manually.
                              // Since performBurnerMode clears storage, the app state watcher in Main
                              // should theoretically handle it if it watches storage, but strictly we might need to
                              // trigger a rigorous re-init.
                              await Navigator.of(
                                context,
                                rootNavigator: true,
                              ).pushNamedAndRemoveUntil('/', (route) => false);
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Authentication failed'),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            'BURN EVERYTHING',
                            style: TextStyle(
                              color: AppTheme.dangerColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ).animate().fadeIn(delay: 450.ms).slideX(),

            const SizedBox(height: 32),
            Center(
              child: Text(
                'Alexandria v1.0.0 (Alpha)',
                style: TextStyle(
                  color: AppTheme.textColor.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, left: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.secondaryColor,
          letterSpacing: 2,
          fontSize: 12,
        ),
      ),
    );
  }
}
