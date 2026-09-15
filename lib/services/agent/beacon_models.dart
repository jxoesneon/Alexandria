import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// Converts bytes to a lowercase hex string
String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Parses a hex string to bytes.
///
/// STRICT parser (ALX-012): after ASCII-space stripping, only
/// `[0-9a-fA-F]` pairs are accepted — `int.parse`'s tolerance for
/// `+` signs, tabs, NBSP and other respellings would let two distinct
/// spellings of one key decode to identical bytes, which a canonical
/// key guard (e.g. `WorkReceipt.samePubkey`) cannot see. The decoder's
/// acceptance set must never exceed the guard's. Throws
/// [FormatException] on malformed input; every caller is a verify path
/// that fails closed on throw.
List<int> hexToBytes(String hex) {
  final cleanHex = hex.replaceAll(' ', '');
  if (cleanHex.isEmpty ||
      cleanHex.length % 2 != 0 ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleanHex)) {
    throw FormatException('malformed hex string', hex);
  }
  final bytes = <int>[];
  for (var i = 0; i < cleanHex.length; i += 2) {
    bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}

/// Recursively sorts maps lexicographically by key for canonical JSON serialization
dynamic _canonicalize(dynamic value) {
  if (value is Map) {
    final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
    final result = <String, dynamic>{};
    for (final key in sortedKeys) {
      result[key] = _canonicalize(value[key]);
    }
    return result;
  } else if (value is List) {
    return value.map(_canonicalize).toList();
  }
  return value;
}

/// Serializes any object or map to canonical, sorted JSON string
String toCanonicalJson(Map<String, dynamic> map) {
  final canonical = _canonicalize(map);
  return jsonEncode(canonical);
}

/// Cryptographically signed Beacon v2 Envelope (Ed25519)
class BeaconEnvelope {
  final int v;
  final String kind;
  final String agentId;
  final int ts;
  final String nonce;
  final String pubkey;
  final String sig;
  final Map<String, dynamic> payload;

  const BeaconEnvelope({
    this.v = 2,
    required this.kind,
    required this.agentId,
    required this.ts,
    required this.nonce,
    required this.pubkey,
    required this.sig,
    required this.payload,
  });

  /// Self-declared client build provenance, if the author included it.
  ///
  /// This value lives inside [payload] under the `client_info` key, so it is
  /// part of the signed body: the signature proves only that the envelope's
  /// author *claims* these values. It carries ZERO trust weight and must never
  /// gate admission, rewards, or verification (ALX-010). Returns null when the
  /// author did not declare any client info.
  Map<String, dynamic>? get clientInfo {
    final raw = payload['client_info'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// Derives canonical agent_id from public key bytes: bcn_`first 12 hex chars`
  static String deriveAgentId(List<int> pubkeyBytes) {
    final hex = bytesToHex(pubkeyBytes);
    return 'bcn_${hex.substring(0, 12)}';
  }

  /// Builds the canonical dictionary representation excluding signature
  Map<String, dynamic> toUnsignedMap() {
    return {
      'v': v,
      'kind': kind,
      'agent_id': agentId,
      'ts': ts,
      'nonce': nonce,
      'pubkey': pubkey,
      'payload': payload,
    };
  }

  /// Builds the complete signed dictionary
  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'kind': kind,
      'agent_id': agentId,
      'ts': ts,
      'nonce': nonce,
      'pubkey': pubkey,
      'payload': payload,
      'sig': sig,
    };
  }

  /// Generates the canonical payload bytes to sign or verify
  List<int> getPreimageBytes() {
    final canonicalStr = toCanonicalJson(toUnsignedMap());
    return utf8.encode(canonicalStr);
  }

  /// Verifies the Ed25519 signature over the canonical JSON preimage
  Future<bool> verify() async {
    try {
      if (v != 2) return false;
      final pubkeyBytes = hexToBytes(pubkey);
      if (pubkeyBytes.length != 32) return false;

      final expectedAgentId = deriveAgentId(pubkeyBytes);
      if (agentId != expectedAgentId) return false;

      final sigBytes = hexToBytes(sig);
      if (sigBytes.length != 64) return false;

      final algorithm = Ed25519();
      final simplePublicKey =
          SimplePublicKey(pubkeyBytes, type: KeyPairType.ed25519);
      final signature = Signature(sigBytes, publicKey: simplePublicKey);

      final preimage = getPreimageBytes();
      return await algorithm.verify(preimage, signature: signature);
    } catch (_) {
      return false;
    }
  }

  /// Formats the envelope with standard Beacon text framing for social/text transports
  String toFramedText() {
    final jsonStr = jsonEncode(toJson());
    return '[BEACON v2]\n$jsonStr';
  }

  /// Parses a framed Beacon envelope from text or raw JSON string
  static BeaconEnvelope? parse(String rawText) {
    try {
      var jsonStr = rawText.trim();
      if (jsonStr.startsWith('[BEACON v2]')) {
        jsonStr = jsonStr.substring(11).trim();
      }
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return BeaconEnvelope(
        v: (map['v'] as num?)?.toInt() ?? 2,
        kind: map['kind'] as String? ?? 'message',
        agentId: map['agent_id'] as String? ?? '',
        ts: (map['ts'] as num?)?.toInt() ?? 0,
        nonce: map['nonce'] as String? ?? '',
        pubkey: map['pubkey'] as String? ?? '',
        sig: map['sig'] as String? ?? '',
        payload: (map['payload'] as Map<String, dynamic>?) ?? {},
      );
    } catch (_) {
      return null;
    }
  }

  /// Factory to construct, canonically serialize, and cryptographically sign a Beacon v2 envelope
  static Future<BeaconEnvelope> create({
    required String kind,
    required SimpleKeyPair keyPair,
    required Map<String, dynamic> payload,
    Map<String, dynamic>? clientInfo,
    int? timestampSeconds,
    String? nonce,
  }) async {
    final pubKey = await keyPair.extractPublicKey();
    final pubkeyHex = bytesToHex(pubKey.bytes);
    final agentId = deriveAgentId(pubKey.bytes);
    final ts =
        timestampSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final n = nonce ??
        sha256
            .convert(utf8.encode(
                '$ts-$agentId-${DateTime.now().microsecondsSinceEpoch}'))
            .toString()
            .substring(0, 20);

    // Client provenance is embedded inside the payload so it is signed *as
    // content*: the signature attests that the author claims these values,
    // which is the honest semantic for self-declared metadata. Because it
    // rides inside `payload`, the canonical preimage scheme is unchanged and
    // envelopes signed before this field existed still verify identically.
    final signedPayload = clientInfo == null
        ? payload
        : <String, dynamic>{...payload, 'client_info': clientInfo};

    final unsignedMap = {
      'v': 2,
      'kind': kind,
      'agent_id': agentId,
      'ts': ts,
      'nonce': n,
      'pubkey': pubkeyHex,
      'payload': signedPayload,
    };

    final canonicalJson = toCanonicalJson(unsignedMap);
    final preimageBytes = utf8.encode(canonicalJson);

    final algorithm = Ed25519();
    final signature = await algorithm.sign(preimageBytes, keyPair: keyPair);
    final sigHex = bytesToHex(signature.bytes);

    return BeaconEnvelope(
      v: 2,
      kind: kind,
      agentId: agentId,
      ts: ts,
      nonce: n,
      pubkey: pubkeyHex,
      sig: sigHex,
      payload: signedPayload,
    );
  }
}

/// Represents a post on the Moltbook AI agent social network (https://www.moltbook.com)
class MoltbookPost {
  final int id;
  final String submolt;
  final String title;
  final String content;
  final String authorAgentId;
  int upvotes;
  final DateTime timestamp;
  final BeaconEnvelope? beaconEnvelope;

  MoltbookPost({
    required this.id,
    required this.submolt,
    required this.title,
    required this.content,
    required this.authorAgentId,
    this.upvotes = 0,
    required this.timestamp,
    this.beaconEnvelope,
  });

  bool get isBeaconVerified => beaconEnvelope != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'submolt': submolt,
        'title': title,
        'content': content,
        'author_agent_id': authorAgentId,
        'upvotes': upvotes,
        'timestamp': timestamp.toIso8601String(),
        if (beaconEnvelope != null) 'beacon': beaconEnvelope!.toJson(),
      };

  factory MoltbookPost.fromJson(Map<String, dynamic> json) {
    BeaconEnvelope? env;
    if (json['beacon'] != null) {
      env = BeaconEnvelope.parse(jsonEncode(json['beacon']));
    }
    return MoltbookPost(
      id: (json['id'] as num).toInt(),
      submolt: json['submolt'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      authorAgentId: json['author_agent_id'] as String? ?? 'agent_anon',
      upvotes: (json['upvotes'] as num?)?.toInt() ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      beaconEnvelope: env,
    );
  }
}

/// Represents an active preservation bounty broadcast across the agent swarm
class PreservationBounty {
  final String id;
  final String cid;
  final String? doi;
  final String title;
  final int targetShards;
  final double offeredCredits;
  final String urgency; // 'normal', 'high', 'critical'
  final String originAgentId;
  final DateTime createdAt;
  bool isClaimed;

  /// Whether [offeredCredits] were actually escrowed at post time.
  /// Bounties posted via `postPreservationBounty` are funded; seeded/demo
  /// network announcements are unfunded and can never be claimed for payout.
  final bool funded;

  PreservationBounty({
    required this.id,
    required this.cid,
    this.doi,
    required this.title,
    this.targetShards = 5,
    required this.offeredCredits,
    this.urgency = 'normal',
    required this.originAgentId,
    required this.createdAt,
    this.isClaimed = false,
    this.funded = false,
  });

  /// Returns a copy of this bounty, optionally overriding [isClaimed].
  ///
  /// `MoltbookService.activeBounties` hands out copies built this way so
  /// no caller can reach the stored record's mutable claim flag —
  /// flipping `isClaimed` on a returned object used to reopen a claimed
  /// bounty for a second escrow payout (Review REV3 Safety veto fix).
  PreservationBounty copyWith({bool? isClaimed}) {
    return PreservationBounty(
      id: id,
      cid: cid,
      doi: doi,
      title: title,
      targetShards: targetShards,
      offeredCredits: offeredCredits,
      urgency: urgency,
      originAgentId: originAgentId,
      createdAt: createdAt,
      isClaimed: isClaimed ?? this.isClaimed,
      funded: funded,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cid': cid,
        if (doi != null) 'doi': doi,
        'title': title,
        'target_shards': targetShards,
        'offered_credits': offeredCredits,
        'urgency': urgency,
        'origin_agent_id': originAgentId,
        'created_at': createdAt.toIso8601String(),
        'is_claimed': isClaimed,
        'funded': funded,
      };

  factory PreservationBounty.fromJson(Map<String, dynamic> json) {
    return PreservationBounty(
      id: json['id'] as String,
      cid: json['cid'] as String,
      doi: json['doi'] as String?,
      title: json['title'] as String,
      targetShards: (json['target_shards'] as num?)?.toInt() ?? 5,
      offeredCredits: (json['offered_credits'] as num).toDouble(),
      urgency: json['urgency'] as String? ?? 'normal',
      originAgentId: json['origin_agent_id'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isClaimed: json['is_claimed'] as bool? ?? false,
      funded: json['funded'] as bool? ?? false,
    );
  }
}
