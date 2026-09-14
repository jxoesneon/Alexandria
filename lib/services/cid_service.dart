import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final cidServiceProvider = Provider((ref) => CidService());

class _Multicodec {
  static const raw = 0x55;
  static const sha2_256 = 0x12;
}

class _Multibase {
  static const base32lower = 'b';
  static const base58btc = 'z';
}

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

  String toBase32() {
    final bytes = _encode();
    return _Multibase.base32lower + _base32Encode(bytes);
  }

  String toBase58() {
    final bytes = _encode();
    return _Multibase.base58btc + _base58Encode(bytes);
  }

  @override
  String toString() => toBase32();

  Uint8List _encode() {
    final result = BytesBuilder();
    result.addByte(version);
    result.addByte(codec);
    result.addByte(hashFunction);
    result.addByte(digest.length);
    result.add(digest);
    return result.toBytes();
  }

  static String _base32Encode(Uint8List bytes) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    final buffer = StringBuffer();
    var val = 0;
    var valBits = 0;
    for (var i = 0; i < bytes.length; i++) {
      val = (val << 8) | bytes[i];
      valBits += 8;
      while (valBits >= 5) {
        valBits -= 5;
        buffer.write(alphabet[(val >> valBits) & 0x1F]);
      }
    }
    if (valBits > 0) {
      buffer.write(alphabet[(val << (5 - valBits)) & 0x1F]);
    }
    return buffer.toString();
  }

  static String _base58Encode(Uint8List bytes) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var zeroes = 0;
    while (zeroes < bytes.length && bytes[zeroes] == 0) {
      zeroes++;
    }
    var bigInt = BigInt.zero;
    for (var i = zeroes; i < bytes.length; i++) {
      bigInt = (bigInt << 8) + BigInt.from(bytes[i]);
    }
    final buffer = StringBuffer();
    while (bigInt > BigInt.zero) {
      final rem = (bigInt % BigInt.from(58)).toInt();
      bigInt = bigInt ~/ BigInt.from(58);
      buffer.write(alphabet[rem]);
    }
    final chars = buffer.toString().split('').reversed.join('');
    return ('1' * zeroes) + chars;
  }
}

class CidService {
  ContentIdentifier computeCid(Uint8List data) {
    final digest = sha256.convert(data).bytes;
    return ContentIdentifier(
      version: 1,
      codec: _Multicodec.raw,
      hashFunction: _Multicodec.sha2_256,
      digest: Uint8List.fromList(digest),
    );
  }

  /// Decodes an Alexandria-issued CIDv1 (raw codec, sha2-256) back to its
  /// 32-byte digest. Returns null for foreign or malformed CIDs.
  Uint8List? decodeDigest(String cid) {
    final Uint8List? bytes;
    if (cid.startsWith(_Multibase.base32lower)) {
      bytes = _base32Decode(cid.substring(1));
    } else if (cid.startsWith(_Multibase.base58btc)) {
      bytes = _base58Decode(cid.substring(1));
    } else {
      return null;
    }
    if (bytes == null || bytes.length != 36) return null;
    if (bytes[0] != 1 ||
        bytes[1] != _Multicodec.raw ||
        bytes[2] != _Multicodec.sha2_256 ||
        bytes[3] != 32) {
      return null;
    }
    return bytes.sublist(4);
  }

  /// Recomputes SHA-256 over [data] and compares against the digest embedded
  /// in [cid]. The integrity anchor for all retrieved content: a peer serving
  /// altered bytes produces a different hash and fails verification.
  bool verifyContent(String cid, Uint8List data) {
    final expected = decodeDigest(cid);
    if (expected == null) return false;
    final actual = sha256.convert(data).bytes;
    for (var i = 0; i < 32; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  }

  static Uint8List? _base32Decode(String input) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    var val = 0;
    var valBits = 0;
    final out = BytesBuilder();
    for (final ch in input.codeUnits) {
      final idx = alphabet.indexOf(String.fromCharCode(ch));
      if (idx < 0) return null;
      val = (val << 5) | idx;
      valBits += 5;
      if (valBits >= 8) {
        valBits -= 8;
        out.addByte((val >> valBits) & 0xFF);
      }
    }
    return out.toBytes();
  }

  static Uint8List? _base58Decode(String input) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var bigInt = BigInt.zero;
    for (final ch in input.codeUnits) {
      final idx = alphabet.indexOf(String.fromCharCode(ch));
      if (idx < 0) return null;
      bigInt = bigInt * BigInt.from(58) + BigInt.from(idx);
    }
    final bytes = <int>[];
    while (bigInt > BigInt.zero) {
      bytes.insert(0, (bigInt % BigInt.from(256)).toInt());
      bigInt = bigInt ~/ BigInt.from(256);
    }
    var zeroes = 0;
    while (zeroes < input.length && input[zeroes] == '1') {
      zeroes++;
    }
    return Uint8List.fromList(List.filled(zeroes, 0) + bytes);
  }

  bool isValidCid(String cid) {
    if (cid.isEmpty) return false;
    if (cid.startsWith('b') && cid.length >= 40) return true;
    if (cid.startsWith('z') && cid.length >= 40) return true;
    if (cid.startsWith('Qm') && cid.length == 46) return true;
    return false;
  }

  String cidFromBytes(Uint8List data) => computeCid(data).toBase32();
}
