import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'cid_service.dart';

/// Provider for the IPFS service
final ipfsServiceProvider = Provider((ref) {
  final cidService = ref.watch(cidServiceProvider);
  return IpfsService(cidService);
});

/// Content health status (Spec §7.3)
enum ContentHealthStatus {
  healthy, // >= 5 peers
  atRisk, // 3-4 peers
  endangered, // < 3 peers
  offline, // No peers
}

/// Network configuration constants
class NetworkConfig {
  static const Duration gatewayTimeout = Duration(seconds: 10);
  static const int maxRetries = 3;
  static const int healthyPeerThreshold = 5;
  static const int endangeredPeerThreshold = 3;

  /// Default gateways in rotation order
  static const List<String> defaultGateways = [
    'https://ipfs.io/ipfs',
    'https://dweb.link/ipfs',
    'https://cloudflare-ipfs.com/ipfs',
    'https://gateway.pinata.cloud/ipfs',
  ];
}

/// Peer info for a CID
class PeerInfo {
  final String cid;
  int peerCount;
  DateTime lastChecked;
  ContentHealthStatus status;

  PeerInfo({
    required this.cid,
    required this.peerCount,
    required this.lastChecked,
  }) : status = _computeStatus(peerCount);

  static ContentHealthStatus _computeStatus(int count) {
    if (count >= NetworkConfig.healthyPeerThreshold) {
      return ContentHealthStatus.healthy;
    }
    if (count >= NetworkConfig.endangeredPeerThreshold) {
      return ContentHealthStatus.atRisk;
    }
    if (count > 0) {
      return ContentHealthStatus.endangered;
    }
    return ContentHealthStatus.offline;
  }

  void updatePeerCount(int newCount) {
    peerCount = newCount;
    lastChecked = DateTime.now();
    status = _computeStatus(newCount);
  }
}

/// Main IPFS service with gateway rotation and health tracking
class IpfsService {
  final CidService _cidService;
  final String _apiBaseUrl = 'http://127.0.0.1:5001/api/v0'; // Kubo API
  final String _gatewayUrl = 'http://127.0.0.1:8080/ipfs'; // Local Gateway

  final List<String> _gateways = List.from(NetworkConfig.defaultGateways);
  final Map<String, PeerInfo> _peerCache = {};
  final Set<String> _pinnedCids = {};
  final List<String> _customGateways = [];

  bool _isReady = false;
  bool get isReady => _isReady;

  IpfsService(this._cidService);

  /// Add a custom gateway to the rotation
  void addCustomGateway(String gateway) {
    if (!_gateways.contains(gateway)) {
      _customGateways.add(gateway);
      _gateways.add(gateway);
    }
  }

  /// Get all gateways (default + custom)
  List<String> get gateways => List.unmodifiable(_gateways);

  // ─────────────────────────────────────────────────────────────────────────
  // Maintenance
  // ─────────────────────────────────────────────────────────────────────────

  /// Run Garbage Collection on the IPFS Repo
  Future<bool> runGc() async {
    try {
      final response = await http.post(Uri.parse('$_apiBaseUrl/repo/gc'));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error running GC: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    debugPrint('IPFS Service Initializing (HTTP Mode)...');
    try {
      final response = await http.post(Uri.parse('$_apiBaseUrl/id'));
      if (response.statusCode == 200) {
        _isReady = true;
        debugPrint('IPFS Service Ready (Connected to Node)');
      } else {
        debugPrint(
          'IPFS Service: Node reachable but returned ${response.statusCode}',
        );
        _isReady = true;
      }
    } catch (e) {
      debugPrint('IPFS Service: Could not connect to local node: $e');
      _isReady = true; // Allow app to start even if IPFS is down
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Content Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Add file to IPFS via local node
  Future<String> addFile(Uint8List data) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiBaseUrl/add'),
      );
      request.files.add(
        http.MultipartFile.fromBytes('file', data, filename: 'upload.bin'),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final cid = json['Hash'] as String;
        _pinnedCids.add(cid);
        return cid;
      } else {
        throw Exception(
          'IPFS add failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('IPFS Add Error: $e');
      rethrow;
    }
  }

  /// Get file using gateway rotation with CID verification (Spec §16.3)
  Future<Uint8List?> getFileWithRotation(String cid) async {
    for (final gateway in _gateways) {
      for (var attempt = 1; attempt <= NetworkConfig.maxRetries; attempt++) {
        try {
          final url = '$gateway/$cid';
          debugPrint('Fetching from $url (attempt $attempt)');

          final response = await http
              .get(Uri.parse(url), headers: {'Accept': '*/*'})
              .timeout(NetworkConfig.gatewayTimeout);

          if (response.statusCode == 200) {
            final data = response.bodyBytes;

            // Verify CID matches content
            if (_cidService.verifyCid(cid, data)) {
              debugPrint('CID verified from $gateway');
              return data;
            } else {
              debugPrint('CID mismatch from $gateway');
              break; // Try next gateway
            }
          } else if (response.statusCode == 429 || response.statusCode == 503) {
            // Rate limited or unavailable - exponential backoff
            final wait = Duration(seconds: 1 << attempt);
            debugPrint(
              'Gateway ${response.statusCode}, waiting ${wait.inSeconds}s',
            );
            await Future.delayed(wait);
          } else {
            break; // Try next gateway
          }
        } on TimeoutException {
          debugPrint('Gateway timeout on $gateway');
          break; // Try next gateway
        } catch (e) {
          debugPrint('Gateway error on $gateway: $e');
          break; // Try next gateway
        }
      }
    }

    // Fallback to local gateway if all public gateways failed
    return await _getFromLocalGateway(cid);
  }

  /// Get file from local gateway with caching
  Future<Uint8List?> _getFromLocalGateway(String cid) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(
        '$_gatewayUrl/$cid',
      );
      final bytes = await file.readAsBytes();
      return Uint8List.fromList(bytes);
    } catch (e) {
      debugPrint('Local gateway error: $e');
      return null;
    }
  }

  /// Stream file from local gateway
  Stream<Uint8List> getFile(String cid) async* {
    try {
      final file = await DefaultCacheManager().getSingleFile(
        '$_gatewayUrl/$cid',
      );
      yield* file.openRead().map((chunk) => Uint8List.fromList(chunk));
    } catch (e) {
      debugPrint('IPFS Get Error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Peer Tracking & Health
  // ─────────────────────────────────────────────────────────────────────────

  /// Check peer count for a CID
  Future<int> getPeerCount(String cid) async {
    try {
      // Use DHT findprovs to get providers
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/dht/findprovs?arg=$cid&num-providers=10'),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        // Parse NDJSON response
        final lines = response.body.split('\n').where((l) => l.isNotEmpty);
        var count = 0;
        for (final line in lines) {
          final json = jsonDecode(line);
          if (json['Type'] == 4) count++; // Type 4 = provider
        }

        _updatePeerInfo(cid, count);
        return count;
      }
    } catch (e) {
      debugPrint('Peer count error: $e');
    }
    return 0;
  }

  /// Get health status for a CID
  ContentHealthStatus getHealthStatus(String cid) {
    return _peerCache[cid]?.status ?? ContentHealthStatus.offline;
  }

  /// Get all endangered content
  List<String> getEndangeredCids() {
    return _peerCache.entries
        .where((e) => e.value.status == ContentHealthStatus.endangered)
        .map((e) => e.key)
        .toList();
  }

  /// Get all at-risk content
  List<String> getAtRiskCids() {
    return _peerCache.entries
        .where((e) => e.value.status == ContentHealthStatus.atRisk)
        .map((e) => e.key)
        .toList();
  }

  void _updatePeerInfo(String cid, int count) {
    if (_peerCache.containsKey(cid)) {
      _peerCache[cid]!.updatePeerCount(count);
    } else {
      _peerCache[cid] = PeerInfo(
        cid: cid,
        peerCount: count,
        lastChecked: DateTime.now(),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pinning Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Pin content to local node
  Future<bool> pinContent(String cid) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/pin/add?arg=$cid'),
      );

      if (response.statusCode == 200) {
        _pinnedCids.add(cid);
        return true;
      }
    } catch (e) {
      debugPrint('Pin error: $e');
    }
    return false;
  }

  /// Unpin content from local node
  Future<bool> unpinContent(String cid) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/pin/rm?arg=$cid'),
      );

      if (response.statusCode == 200) {
        _pinnedCids.remove(cid);
        return true;
      }
    } catch (e) {
      debugPrint('Unpin error: $e');
    }
    return false;
  }

  /// Check if content is pinned locally
  bool isPinned(String cid) => _pinnedCids.contains(cid);

  /// Get all pinned CIDs
  Set<String> get pinnedCids => Set.unmodifiable(_pinnedCids);

  /// Auto-pin endangered content (Swarm Healing)
  Future<void> healEndangeredContent() async {
    final endangered = getEndangeredCids();
    debugPrint('Healing ${endangered.length} endangered CIDs');

    for (final cid in endangered) {
      if (!isPinned(cid)) {
        final success = await pinContent(cid);
        debugPrint('Auto-pinned $cid: $success');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Silent Healing / Integrity Check
  // ─────────────────────────────────────────────────────────────────────────

  /// Verify integrity of pinned content
  Future<Map<String, bool>> verifyIntegrity() async {
    final results = <String, bool>{};

    for (final cid in _pinnedCids) {
      try {
        final data = await getFileWithRotation(cid);
        if (data != null) {
          results[cid] = _cidService.verifyCid(cid, data);
        } else {
          results[cid] = false;
        }
      } catch (e) {
        results[cid] = false;
      }
    }

    return results;
  }

  /// Run health check on all tracked CIDs
  Future<void> runHealthCheck() async {
    debugPrint('Running health check on ${_peerCache.length} CIDs');

    for (final cid in _peerCache.keys.toList()) {
      await getPeerCount(cid);
    }

    // Auto-heal endangered content
    await healEndangeredContent();
  }
  // ─────────────────────────────────────────────────────────────────────────
  // PubSub (P2P Messaging)
  // ─────────────────────────────────────────────────────────────────────────

  /// Publish a message to a PubSub topic
  Future<bool> publishToPubsub(String topic, String data) async {
    try {
      // Encode data to Base64url or similar if needed,
      // but IPFS API expects 'arg' for topic and 'arg' for payload?
      // Actually standard Kubo API: /api/v0/pubsub/pub?arg=<TOPIC>&arg=<PAYLOAD_URL_ENCODED>

      final payload = Uri.encodeComponent(data);
      // Note: We use query params because payload might be binary-ish or just large text
      final uri = Uri.parse('$_apiBaseUrl/pubsub/pub?arg=$topic&arg=$payload');

      final response = await http.post(uri);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('PubSub Publish Error: $e');
      return false;
    }
  }

  /// Subscribe to a topic (Returns a Stream)
  /// Note: This keeps a persistent connection open.
  Stream<String> subscribeToTopic(String topic) async* {
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_apiBaseUrl/pubsub/sub?arg=$topic'),
      );

      final response = await client.send(request);

      // Transform stream
      yield* response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
            // Parse IPFS PubSub JSON format
            // { "from": "...", "data": "base64...", "seqno": "...", "topicIDs": [...] }
            try {
              if (line.isEmpty) return '';
              final json = jsonDecode(line);
              final encodedData = json['data'] as String;
              // IPFS pubsub data is typically base64 encoded
              final bytes = base64Decode(encodedData);
              return utf8.decode(bytes);
            } catch (_) {
              return '';
            }
          })
          .where((s) => s.isNotEmpty);
    } catch (e) {
      debugPrint('PubSub Subscribe Error: $e');
      client.close();
    }
  }
}
