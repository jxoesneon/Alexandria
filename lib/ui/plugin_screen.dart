import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/plugin_service.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_card.dart';
import 'widgets/info_glass.dart';

/// Tab selection for plugin screen
enum PluginTab { plugins, themes }

final pluginTabProvider = StateProvider<PluginTab>((ref) => PluginTab.plugins);

class PluginScreen extends ConsumerWidget {
  const PluginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pluginService = ref.watch(pluginServiceProvider);
    final selectedTab = ref.watch(pluginTabProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Row(
          children: [
            Text('THE GARDEN'),
            SizedBox(width: 8),
            InfoGlass(
              title: 'Plugins & Themes',
              description:
                  'Extend Alexandria with community plugins and customize '
                  'your experience with themes.',
              small: true,
              color: AppTheme.primaryColor,
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.secondaryColor.withValues(alpha: 0.1),
              AppTheme.canvasColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Tab Bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _TabButton(
                      label: 'Plugins',
                      isSelected: selectedTab == PluginTab.plugins,
                      onTap: () => ref.read(pluginTabProvider.notifier).state =
                          PluginTab.plugins,
                    ),
                    const SizedBox(width: 12),
                    _TabButton(
                      label: 'Themes',
                      isSelected: selectedTab == PluginTab.themes,
                      onTap: () => ref.read(pluginTabProvider.notifier).state =
                          PluginTab.themes,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle,
                        color: AppTheme.primaryColor,
                      ),
                      onPressed: () =>
                          _showInstallDialog(context, ref, selectedTab),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: selectedTab == PluginTab.plugins
                    ? _PluginsList(plugins: pluginService.plugins)
                    : _ThemesList(themes: pluginService.themes),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInstallDialog(BuildContext context, WidgetRef ref, PluginTab tab) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          tab == PluginTab.plugins ? 'Install Plugin' : 'Install Theme',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste the manifest JSON:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 8,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: '{\n  "id": "...",\n  "name": "...",\n  ...\n}',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Example buttons
              Wrap(
                spacing: 8,
                children: [
                  if (tab == PluginTab.plugins) ...[
                    _ExampleButton(
                      label: 'Zotero',
                      onTap: () {
                        final pluginService = ref.read(pluginServiceProvider);
                        controller.text = pluginService.zoteroConnectorTemplate;
                      },
                    ),
                    _ExampleButton(
                      label: 'Calibre',
                      onTap: () {
                        final pluginService = ref.read(pluginServiceProvider);
                        controller.text =
                            pluginService.calibreConnectorTemplate;
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final pluginService = ref.read(pluginServiceProvider);
              if (tab == PluginTab.plugins) {
                final result = pluginService.installPlugin(controller.text);
                if (result != null) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Installed: ${result.name}')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid manifest'),
                      backgroundColor: AppTheme.dangerColor,
                    ),
                  );
                }
              } else {
                final result = pluginService.installTheme(controller.text);
                if (result != null) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Installed: ${result.name}')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid theme manifest'),
                      backgroundColor: AppTheme.dangerColor,
                    ),
                  );
                }
              }
            },
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.white24,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isSelected ? AppTheme.primaryColor : Colors.white54,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _ExampleButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ExampleButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
      labelStyle: const TextStyle(color: AppTheme.primaryColor),
      side: BorderSide.none,
    );
  }
}

class _PluginsList extends StatelessWidget {
  final List<InstalledPlugin> plugins;

  const _PluginsList({required this.plugins});

  @override
  Widget build(BuildContext context) {
    if (plugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.extension_outlined,
              size: 64,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              'No plugins installed',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to install plugins like Zotero or Calibre connectors',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white38),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PluginCard(plugin: plugin),
        ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1);
      },
    );
  }
}

class _PluginCard extends ConsumerWidget {
  final InstalledPlugin plugin;

  const _PluginCard({required this.plugin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.extension,
                color: AppTheme.primaryColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.manifest.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plugin.manifest.description,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      _PermissionChip(label: 'v${plugin.manifest.version}'),
                      ...plugin.manifest.permissions
                          .take(2)
                          .map((p) => _PermissionChip(label: p.name)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: plugin.enabled,
              onChanged: (value) {
                final pluginService = ref.read(pluginServiceProvider);
                pluginService.togglePlugin(plugin.id, value);
              },
              activeThumbColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionChip extends StatelessWidget {
  final String label;

  const _PermissionChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white38, fontSize: 10),
      ),
    );
  }
}

class _ThemesList extends StatelessWidget {
  final List<ThemeManifest> themes;

  const _ThemesList({required this.themes});

  @override
  Widget build(BuildContext context) {
    if (themes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.palette_outlined, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              'No custom themes',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to install custom color themes',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white38),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: themes.length,
      itemBuilder: (context, index) {
        final theme = themes[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ThemeCard(theme: theme),
        ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1);
      },
    );
  }
}

class _ThemeCard extends ConsumerWidget {
  final ThemeManifest theme;

  const _ThemeCard({required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pluginService = ref.watch(pluginServiceProvider);
    final isActive = pluginService.activeTheme?.id == theme.id;

    return GlassCard(
      onTap: () {
        final service = ref.read(pluginServiceProvider);
        service.setActiveTheme(theme.id);
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Color Preview
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: theme.colors.values.take(3).map((hex) {
                    try {
                      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
                    } catch (_) {
                      return Colors.grey;
                    }
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theme.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'by ${theme.author}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.honorColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check, size: 14, color: AppTheme.honorColor),
                    SizedBox(width: 4),
                    Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: AppTheme.honorColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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
