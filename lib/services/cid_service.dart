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
    const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
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

  bool isValidCid(String cid) {
    if (cid.isEmpty) return false;
    if (cid.startsWith('b') && cid.length >= 40) return true;
    if (cid.startsWith('z') && cid.length >= 40) return true;
    if (cid.startsWith('Qm') && cid.length == 46) return true;
    return false;
  }
}
