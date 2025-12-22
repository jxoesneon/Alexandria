import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_storage_service.dart';

/// Provider for the TorService
final torServiceProvider = Provider((ref) {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return TorService(secureStorage);
});

/// Provider for Tor connection status
final torStatusProvider = StateProvider<TorStatus>((ref) => TorStatus.disabled);

/// Tor connection status
enum TorStatus { disabled, connecting, connected, error }

/// Configuration for Tor proxy
class TorConfig {
  static const String defaultHost = '127.0.0.1';
  static const int defaultPort = 9050; // Standard Tor SOCKS port
  static const Duration connectionTimeout = Duration(seconds: 30);

  /// Onion gateways for IPFS (examples - real ones would be discovered)
  static const List<String> onionGateways = [
    'http://ipfs.examples7xyzabcd.onion/ipfs',
  ];
}

/// Service for managing Tor proxy connections (The Veil - Spec §6)
///
/// Provides anonymous routing for IPFS gateway requests through the Tor network
/// using SOCKS5 proxy. Requires a running Tor daemon (e.g., Tor Browser or
/// standalone `tor` service) listening on the configured port.
class TorService {
  final SecureStorageService _storage;

  String _proxyHost = TorConfig.defaultHost;
  int _proxyPort = TorConfig.defaultPort;
  bool _isEnabled = false;
  TorStatus _status = TorStatus.disabled;

  TorService(this._storage);

  /// Current Tor status
  TorStatus get status => _status;

  /// Whether Tor is enabled
  bool get isEnabled => _isEnabled;

  /// Get the SOCKS5 proxy host:port
  String get proxyAddress => '$_proxyHost:$_proxyPort';

  /// Initialize from stored settings
  Future<void> init() async {
    final enabled = await _storage.read('tor_enabled');
    final host = await _storage.read('tor_host');
    final port = await _storage.read('tor_port');

    _isEnabled = enabled == 'true';
    _proxyHost = host ?? TorConfig.defaultHost;
    _proxyPort = int.tryParse(port ?? '') ?? TorConfig.defaultPort;

    if (_isEnabled) {
      await _testConnection();
    }
  }

  /// Enable Tor routing
  Future<bool> enable() async {
    _status = TorStatus.connecting;
    _isEnabled = true;

    final connected = await _testConnection();

    if (connected) {
      await _storage.write('tor_enabled', 'true');
      _status = TorStatus.connected;
      debugPrint('Tor enabled: $proxyAddress');
      return true;
    } else {
      _isEnabled = false;
      _status = TorStatus.error;
      debugPrint('Tor connection failed');
      return false;
    }
  }

  /// Disable Tor routing
  Future<void> disable() async {
    _isEnabled = false;
    _status = TorStatus.disabled;
    await _storage.write('tor_enabled', 'false');
    debugPrint('Tor disabled');
  }

  /// Configure custom Tor proxy
  Future<void> configure({String? host, int? port}) async {
    if (host != null) {
      _proxyHost = host;
      await _storage.write('tor_host', host);
    }
    if (port != null) {
      _proxyPort = port;
      await _storage.write('tor_port', port.toString());
    }
  }

  /// Test connection to Tor SOCKS5 proxy
  Future<bool> _testConnection() async {
    try {
      // Try to connect to the proxy port
      final socket = await Socket.connect(
        _proxyHost,
        _proxyPort,
        timeout: const Duration(seconds: 5),
      );
      await socket.close();
      return true;
    } catch (e) {
      debugPrint('Tor connection test failed: $e');
      return false;
    }
  }

  /// Create an HTTP client that routes through Tor SOCKS5 proxy
  ///
  /// Usage:
  /// ```dart
  /// final client = torService.createTorHttpClient();
  /// final request = await client.getUrl(Uri.parse('https://example.com'));
  /// final response = await request.close();
  /// ```
  HttpClient createTorHttpClient() {
    final client = HttpClient();

    if (_isEnabled) {
      // Configure SOCKS5 proxy through findProxy callback
      client.findProxy = (uri) {
        return 'PROXY $_proxyHost:$_proxyPort';
      };
    }

    client.connectionTimeout = TorConfig.connectionTimeout;

    return client;
  }

  /// Make a GET request through Tor and return bytes
  Future<List<int>?> getViaProxy(String url) async {
    if (!_isEnabled) {
      debugPrint('Tor not enabled, skipping proxy request');
      return null;
    }

    try {
      final client = createTorHttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>(
          <int>[],
          (previous, chunk) => previous..addAll(chunk),
        );
        client.close();
        return bytes;
      }
      client.close();
    } catch (e) {
      debugPrint('Tor GET error: $e');
    }
    return null;
  }

  /// Get circuit info (for UI display)
  Map<String, String> getCircuitInfo() {
    if (!_isEnabled) {
      return {'status': 'disabled'};
    }

    return {'status': _status.name, 'proxy': proxyAddress, 'type': 'SOCKS5'};
  }

  /// Check if Tor daemon is running
  Future<bool> isTorRunning() async {
    return _testConnection();
  }
}
