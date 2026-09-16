import 'dart:io';
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
  String get proxyHost => _proxyHost;
  int get proxyPort => _proxyPort;

  /// Host grammar shared by [setProxy] and [init]: dotted IPv4,
  /// bracketed IPv6, or DNS hostname. Anything else (spaces, `;`,
  /// directives) could smuggle `findProxy` grammar — e.g. ` PROXY x
  /// DIRECT` — into the proxy string.
  static bool _isValidProxyHost(String h) {
    return RegExp(
      r'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\[[0-9a-fA-F:]+\]|[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?)*)$',
    ).hasMatch(h);
  }

  static bool _isValidProxyPort(int port) => port > 0 && port <= 65535;

  Future<void> setProxy(String host, int port) async {
    // Validate host/port shape (red minor-observation hardening): a
    // malformed host reaches Socket.connect and the proxy string
    // verbatim — restrict to dotted IPv4, [IPv6], or DNS hostname shape,
    // and a real port range.
    final h = host.trim();
    if (h.isEmpty || !_isValidProxyHost(h)) {
      throw ArgumentError('Invalid Tor proxy host: $host');
    }
    if (!_isValidProxyPort(port)) {
      throw ArgumentError('Invalid Tor proxy port: $port');
    }
    _proxyHost = h;
    _proxyPort = port;
    await _storage.write('tor_host', _proxyHost);
    await _storage.write('tor_port', _proxyPort.toString());
  }

  Future<void> init() async {
    final enabled = await _storage.read('tor_enabled');
    final host = await _storage.read('tor_host');
    final port = await _storage.read('tor_port');

    _isEnabled = enabled == 'true';
    // (slot-C sweep) Stored values bypass setProxy()'s grammar — a
    // corrupt or tampered store could smuggle `findProxy` directives
    // (spaces, ';', 'DIRECT') into the proxy string or feed garbage to
    // Socket.connect. Re-validate on load and fail closed to the
    // loopback defaults.
    final h = host?.trim();
    _proxyHost =
        (h != null && h.isNotEmpty && _isValidProxyHost(h)) ? h : '127.0.0.1';
    final p = int.tryParse(port ?? '');
    _proxyPort = (p != null && _isValidProxyPort(p)) ? p : 9050;

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
      final socket = await Socket.connect(_proxyHost, _proxyPort,
          timeout: const Duration(seconds: 3));
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
