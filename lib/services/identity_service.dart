import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'secure_storage_service.dart';

/// Provider for the IdentityService
final identityServiceProvider = Provider((ref) {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return IdentityService(secureStorage);
});

/// Storage keys for identity data
class _IdentityKeys {
  static const privateKey = 'alexandria_identity_private_key';
  static const publicKey = 'alexandria_identity_public_key';
  static const identityCreated = 'alexandria_identity_created';
}

/// Represents a cryptographic identity with Ed25519 keypair
class AlexandriaIdentity {
  final Uint8List publicKey;
  final Uint8List privateKey;
  final DateTime createdAt;

  AlexandriaIdentity({
    required this.publicKey,
    required this.privateKey,
    required this.createdAt,
  });

  /// Get the Base58-encoded public key (for display)
  String get publicKeyBase58 => _base58Encode(publicKey);

  /// Get the short identity (first 8 chars of Base58)
  String get shortId => publicKeyBase58.substring(0, 8);

  /// Convert to JSON for debugging (never export private key in production)
  Map<String, dynamic> toJson() => {
    'publicKey': publicKeyBase58,
    'shortId': shortId,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Base58 encoding implementation
  static String _base58Encode(Uint8List bytes) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var result = '';
    var value = BigInt.zero;

    for (var byte in bytes) {
      value = (value << 8) + BigInt.from(byte);
    }

    while (value > BigInt.zero) {
      final remainder = (value % BigInt.from(58)).toInt();
      result = alphabet[remainder] + result;
      value = value ~/ BigInt.from(58);
    }

    // Add leading '1's for leading zero bytes
    for (var byte in bytes) {
      if (byte == 0) {
        result = '1$result';
      } else {
        break;
      }
    }

    return result;
  }
}

/// Represents a signed identity proof
class IdentityProof {
  final String message;
  final Uint8List signature;
  final Uint8List publicKey;
  final DateTime timestamp;

  IdentityProof({
    required this.message,
    required this.signature,
    required this.publicKey,
    required this.timestamp,
  });

  /// Get Base64-encoded signature
  String get signatureBase64 => base64Encode(signature);

  Map<String, dynamic> toJson() => {
    'message': message,
    'signature': signatureBase64,
    'publicKey': AlexandriaIdentity._base58Encode(publicKey),
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Service for managing cryptographic identity
class IdentityService {
  final SecureStorageService _storage;
  final _algorithm = Ed25519();

  IdentityService(this._storage);

  AlexandriaIdentity? _cachedIdentity;

  /// Check if an identity exists
  Future<bool> hasIdentity() async {
    return await _storage.containsKey(_IdentityKeys.privateKey);
  }

  /// Get the current identity (cached for performance)
  Future<AlexandriaIdentity?> getIdentity() async {
    if (_cachedIdentity != null) return _cachedIdentity;

    final privateKeyHex = await _storage.read(_IdentityKeys.privateKey);
    final publicKeyHex = await _storage.read(_IdentityKeys.publicKey);
    final createdStr = await _storage.read(_IdentityKeys.identityCreated);

    if (privateKeyHex == null || publicKeyHex == null || createdStr == null) {
      return null;
    }

    _cachedIdentity = AlexandriaIdentity(
      privateKey: _hexDecode(privateKeyHex),
      publicKey: _hexDecode(publicKeyHex),
      createdAt: DateTime.parse(createdStr),
    );

    return _cachedIdentity;
  }

  /// Generate a new Ed25519 keypair and store securely
  Future<AlexandriaIdentity> generateIdentity() async {
    // Generate new keypair
    final keyPair = await _algorithm.newKeyPair();

    // Extract keys
    final privateKeyBytes = await keyPair
        .extractPrivateKeyBytes(); // 32 bytes seed
    final publicKeyObj = await keyPair.extractPublicKey();
    final publicKeyBytes = Uint8List.fromList(publicKeyObj.bytes); // 32 bytes

    final createdAt = DateTime.now();

    // Store securely
    await _storage.write(
      _IdentityKeys.privateKey,
      _hexEncode(Uint8List.fromList(privateKeyBytes)),
    );
    await _storage.write(_IdentityKeys.publicKey, _hexEncode(publicKeyBytes));
    await _storage.write(
      _IdentityKeys.identityCreated,
      createdAt.toIso8601String(),
    );

    _cachedIdentity = AlexandriaIdentity(
      privateKey: Uint8List.fromList(privateKeyBytes),
      publicKey: publicKeyBytes,
      createdAt: createdAt,
    );

    return _cachedIdentity!;
  }

  /// Create an identity proof (signed message with timestamp)
  Future<IdentityProof> createIdentityProof() async {
    final identity = await getIdentity();
    if (identity == null) {
      throw StateError('No identity exists. Generate one first.');
    }

    final timestamp = DateTime.now();
    final message = 'Alexandria Identity Proof: ${timestamp.toIso8601String()}';
    final messageBytes = utf8.encode(message);

    // Reconstruct keypair from stored bytes
    final keyPair = await _algorithm.newKeyPairFromSeed(identity.privateKey);

    // Sign the message
    final signature = await _algorithm.sign(messageBytes, keyPair: keyPair);

    return IdentityProof(
      message: message,
      signature: Uint8List.fromList(signature.bytes),
      publicKey: identity.publicKey,
      timestamp: timestamp,
    );
  }

  /// Verify an identity proof
  Future<bool> verifyIdentityProof(IdentityProof proof) async {
    try {
      final messageBytes = utf8.encode(proof.message);
      final publicKey = SimplePublicKey(
        proof.publicKey,
        type: KeyPairType.ed25519,
      );

      final signature = Signature(proof.signature, publicKey: publicKey);

      return await _algorithm.verify(messageBytes, signature: signature);
    } catch (e) {
      return false;
    }
  }

  /// Sign arbitrary data with the identity's private key
  Future<Uint8List> sign(Uint8List data) async {
    final identity = await getIdentity();
    if (identity == null) {
      throw StateError('No identity exists. Generate one first.');
    }

    final keyPair = await _algorithm.newKeyPairFromSeed(identity.privateKey);
    final signature = await _algorithm.sign(data, keyPair: keyPair);

    return Uint8List.fromList(signature.bytes);
  }

  /// Verify a signature against a public key
  Future<bool> verifySignature(
    Uint8List data,
    Uint8List signature,
    Uint8List publicKey,
  ) async {
    try {
      final pubKey = SimplePublicKey(publicKey, type: KeyPairType.ed25519);

      final sig = Signature(signature, publicKey: pubKey);
      return await _algorithm.verify(data, signature: sig);
    } catch (e) {
      return false;
    }
  }

  /// Delete the current identity (dangerous - cannot be recovered without backup)
  Future<void> deleteIdentity() async {
    await _storage.delete(_IdentityKeys.privateKey);
    await _storage.delete(_IdentityKeys.publicKey);
    await _storage.delete(_IdentityKeys.identityCreated);
    _cachedIdentity = null;
  }

  /// Compute SHA-256 hash of data
  Uint8List sha256(Uint8List data) {
    final digest = crypto.sha256.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper methods
  // ─────────────────────────────────────────────────────────────────────────

  String _hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _hexDecode(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
