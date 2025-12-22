import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the CID service
final cidServiceProvider = Provider((ref) => CidService());

/// Multicodec codes
class _Multicodec {
  static const raw = 0x55; // Raw binary
  static const sha2_256 = 0x12; // SHA2-256 hash function
}

/// Multibase prefixes
class _Multibase {
  static const base32lower = 'b'; // Base32 lowercase (CIDv1 default)
  static const base58btc = 'z'; // Base58 Bitcoin
}

/// Represents a CIDv1 content identifier
class ContentIdentifier {
  final int version;
  final int codec;
  final int hashFunction;
  final Uint8List digest;

  ContentIdentifier({
    required this.version,
    required this.codec,
    required this.hashFunction,
    required this.digest,
  });

  /// Get the CID as a Base32 string (default format)
  String toBase32() {
    final bytes = _encode();
    return _Multibase.base32lower + _base32Encode(bytes);
  }

  /// Get the CID as a Base58 string
  String toBase58() {
    final bytes = _encode();
    return _Multibase.base58btc + _base58Encode(bytes);
  }

  /// Default string representation
  @override
  String toString() => toBase32();

  /// Encode CID to bytes
  Uint8List _encode() {
    // CIDv1: <version><codec><multihash>
    // multihash: <hash-function><digest-length><digest>
    final multihash = <int>[hashFunction, digest.length, ...digest];

    return Uint8List.fromList([version, codec, ...multihash]);
  }

  /// Parse a CID string
  static ContentIdentifier? parse(String cidString) {
    if (cidString.isEmpty) return null;

    try {
      final prefix = cidString[0];
      final encoded = cidString.substring(1);

      Uint8List bytes;
      if (prefix == _Multibase.base32lower) {
        bytes = _base32Decode(encoded);
      } else if (prefix == _Multibase.base58btc) {
        bytes = _base58Decode(encoded);
      } else {
        return null;
      }

      if (bytes.length < 4) return null;

      final version = bytes[0];
      final codec = bytes[1];
      final hashFunction = bytes[2];
      final digestLength = bytes[3];
      final digest = bytes.sublist(4, 4 + digestLength);

      return ContentIdentifier(
        version: version,
        codec: codec,
        hashFunction: hashFunction,
        digest: digest,
      );
    } catch (e) {
      return null;
    }
  }

  /// Verify that content matches this CID
  bool verify(Uint8List content) {
    final expectedDigest = sha256.convert(content).bytes;
    if (digest.length != expectedDigest.length) return false;

    for (var i = 0; i < digest.length; i++) {
      if (digest[i] != expectedDigest[i]) return false;
    }
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Encoding helpers
  // ─────────────────────────────────────────────────────────────────────────

  static String _base32Encode(Uint8List bytes) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    var result = '';
    var buffer = 0;
    var bitsLeft = 0;

    for (var byte in bytes) {
      buffer = (buffer << 8) | byte;
      bitsLeft += 8;

      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        result += alphabet[(buffer >> bitsLeft) & 0x1F];
      }
    }

    if (bitsLeft > 0) {
      result += alphabet[(buffer << (5 - bitsLeft)) & 0x1F];
    }

    return result;
  }

  static Uint8List _base32Decode(String encoded) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    final result = <int>[];
    var buffer = 0;
    var bitsLeft = 0;

    for (var char in encoded.toLowerCase().split('')) {
      final index = alphabet.indexOf(char);
      if (index == -1) continue;

      buffer = (buffer << 5) | index;
      bitsLeft += 5;

      while (bitsLeft >= 8) {
        bitsLeft -= 8;
        result.add((buffer >> bitsLeft) & 0xFF);
      }
    }

    return Uint8List.fromList(result);
  }

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

  static Uint8List _base58Decode(String encoded) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var value = BigInt.zero;

    for (var char in encoded.split('')) {
      final index = alphabet.indexOf(char);
      if (index == -1) continue;
      value = value * BigInt.from(58) + BigInt.from(index);
    }

    // Convert BigInt to bytes
    final bytes = <int>[];
    while (value > BigInt.zero) {
      bytes.insert(0, (value & BigInt.from(0xFF)).toInt());
      value = value >> 8;
    }

    // Add leading zeros
    for (var char in encoded.split('')) {
      if (char == '1') {
        bytes.insert(0, 0);
      } else {
        break;
      }
    }

    return Uint8List.fromList(bytes);
  }
}

/// Service for creating and verifying CIDs
class CidService {
  /// Generate CIDv1 for content
  ContentIdentifier generateCid(Uint8List content) {
    final digest = Uint8List.fromList(sha256.convert(content).bytes);

    return ContentIdentifier(
      version: 1,
      codec: _Multicodec.raw,
      hashFunction: _Multicodec.sha2_256,
      digest: digest,
    );
  }

  /// Generate CID from file bytes
  String cidFromBytes(Uint8List bytes) {
    return generateCid(bytes).toBase32();
  }

  /// Verify content matches a CID string
  bool verifyCid(String cidString, Uint8List content) {
    final cid = ContentIdentifier.parse(cidString);
    if (cid == null) return false;
    return cid.verify(content);
  }

  /// Parse a CID string
  ContentIdentifier? parseCid(String cidString) {
    return ContentIdentifier.parse(cidString);
  }

  /// Check if a string is a valid CID
  bool isValidCid(String cidString) {
    return ContentIdentifier.parse(cidString) != null;
  }

  /// Extract the hash from a CID (for comparison)
  Uint8List? extractHash(String cidString) {
    final cid = ContentIdentifier.parse(cidString);
    return cid?.digest;
  }
}
