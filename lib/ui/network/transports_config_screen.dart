import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/network_models.dart';
import '../../providers/network_providers.dart';
import '../../services/network_overview_service.dart';

class TransportsConfigScreen extends ConsumerStatefulWidget {
  const TransportsConfigScreen({super.key});

  @override
  ConsumerState<TransportsConfigScreen> createState() =>
      _TransportsConfigScreenState();
}

class _TransportsConfigScreenState
    extends ConsumerState<TransportsConfigScreen> {
  List<TransportConfig>? _configs;
  final Map<TransportProtocol, TextEditingController> _portControllers = {};
  final Map<TransportProtocol, TextEditingController> _relayControllers = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final configs = await ref.read(transportsConfigProvider.future);
      if (mounted) {
        setState(() {
          _configs = configs.toList();
          _loading = false;
          _error = null;
          _initializeControllers();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _initializeControllers() {
    for (final controller in _portControllers.values) {
      controller.dispose();
    }
    for (final controller in _relayControllers.values) {
      controller.dispose();
    }
    _portControllers.clear();
    _relayControllers.clear();

    for (final config in _configs ?? []) {
      _portControllers[config.protocol] =
          TextEditingController(text: config.port.toString());
      _relayControllers[config.protocol] =
          TextEditingController(text: config.relay);
    }
  }

  @override
  void dispose() {
    for (final controller in _portControllers.values) {
      controller.dispose();
    }
    for (final controller in _relayControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final service = ref.read(networkOverviewServiceProvider);
    final currentConfigs = _configs ?? [];

    for (var i = 0; i < currentConfigs.length; i++) {
      final config = currentConfigs[i];
      final portText = _portControllers[config.protocol]?.text ?? '';
      final relayText = _relayControllers[config.protocol]?.text ?? '';
      final updated = config.copyWith(
        port: int.tryParse(portText) ?? config.port,
        relay: relayText,
      );
      await service.updateTransport(updated);
      currentConfigs[i] = updated;
    }

    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transport settings saved')),
      );
    }
  }

  Future<void> _testConnection() async {
    final service = ref.read(networkOverviewServiceProvider);
    try {
      final result = await service.testConnections();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection test failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transports Configuration')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transports Configuration')),
        body: Center(child: Text('Error: $_error')),
      );
    }

    final configs = _configs!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transports Configuration'),
        actions: [
          TextButton(
            onPressed: () async {
              await _testConnection();
            },
            child: const Text('Test connection'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ListView.builder(
          itemCount: configs.length,
          itemBuilder: (context, index) {
            final config = configs[index];
            return _buildProtocolCard(context, config, index);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await _save();
        },
        icon: const Icon(Icons.save),
        label: const Text('Save'),
      ),
    );
  }

  Widget _buildProtocolCard(
    BuildContext context,
    TransportConfig config,
    int index,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final portController = _portControllers[config.protocol];
    final relayController = _relayControllers[config.protocol];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  config.protocol.displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: config.enabled,
                  onChanged: (value) {
                    setState(() {
                      _configs![index] = config.copyWith(enabled: value);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: relayController,
              decoration: const InputDecoration(
                labelText: 'Relay',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Enabled: ${config.enabled ? 'Yes' : 'No'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
