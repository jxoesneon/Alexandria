import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';

void main() {
  group('CidService & ContentIdentifier Tests', () {
    late CidService cidService;

    setUp(() {
      cidService = CidService();
    });

    test('computes valid CIDv1 in Base32 format', () {
      final sample = Uint8List.fromList('Alexandria Library P2P Knowledge'.codeUnits);
      final cid = cidService.computeCid(sample);

      expect(cid.version, 1);
      expect(cid.codec, 0x55);
      expect(cid.hashFunction, 0x12);
      expect(cid.digest.length, 32);

      final b32 = cid.toBase32();
      expect(b32.startsWith('b'), isTrue);
      expect(cid.toString(), equals(b32));
      expect(cidService.isValidCid(b32), isTrue);
    });

    test('computes valid CIDv1 in Base58 format', () {
      final sample = Uint8List.fromList('Alexandria Cryptography'.codeUnits);
      final cid = cidService.computeCid(sample);

      final b58 = cid.toBase58();
      expect(b58.startsWith('z'), isTrue);
      expect(cidService.isValidCid(b58), isTrue);
    });

    test('validates legacy CIDv0 and invalid CIDs', () {
      expect(cidService.isValidCid('QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP1mXWo6uco'), isTrue);
      expect(cidService.isValidCid(''), isFalse);
      expect(cidService.isValidCid('invalid_short'), isFalse);
    });
  });
}
