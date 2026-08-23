import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_storage_service.dart';

final torServiceProvider = Provider((ref) {
  final storage = ref.watch(secureStorageServiceProvider);
  return TorService(storage);
});

final torStatusProvider = StateProvider<TorStatus>((ref) => TorStatus.disabled);
enum TorStatus { disabled, connecting, connected, error }

class TorService {
  final SecureStorageService _storage;
  String _proxyHost = '127.0.0.1';
  int _proxyPort = 9050;
  bool _isEnabled = false;
  TorStatus _status = TorStatus.disabled;

  TorService(this._storage);

  TorStatus get status => _status;
  bool get isEnabled => _isEnabled;
  String get proxyAddress => '$_proxyHost:$_proxyPort';

  Future<void> init() async {
    final enabled = await _storage.read('tor_enabled');
    final host = await _storage.read('tor_host');
    final port = await _storage.read('tor_port');

    _isEnabled = enabled == 'true';
    _proxyHost = host ?? '127.0.0.1';
    _proxyPort = int.tryParse(port ?? '') ?? 9050;

    if (_isEnabled) {
      await enable();
    }
  }

  Future<bool> enable() async {
    _status = TorStatus.connecting;
    _isEnabled = true;
    final connected = await _testConnection();
    if (connected) {
      await _storage.write('tor_enabled', 'true');
      _status = TorStatus.connected;
      return true;
    } else {
      _isEnabled = false;
      _status = TorStatus.error;
      return false;
    }
  }

  Future<void> disable() async {
    _isEnabled = false;
    _status = TorStatus.disabled;
    await _storage.write('tor_enabled', 'false');
  }

  Future<bool> _testConnection() async {
    try {
      final socket = await Socket.connect(_proxyHost, _proxyPort, timeout: const Duration(seconds: 3));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  HttpClient createTorHttpClient() {
    final client = HttpClient();
    if (_isEnabled) {
      client.findProxy = (uri) => 'PROXY $_proxyHost:$_proxyPort';
    }
    client.connectionTimeout = const Duration(seconds: 30);
    return client;
  }
}
