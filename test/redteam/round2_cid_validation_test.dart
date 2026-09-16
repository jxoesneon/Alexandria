// RED TEAM probe - CidService.isValidCid is a shape check that
// rubber-stamps arbitrary strings, while IpfsService treats "pinned"
// as proof of availability.
//
// lib/services/cid_service.dart:178-184 accepts ANY string ≥40 chars
// starting with 'b' or 'z' (and any 46-char 'Qm…' string) - no
// multibase decode, no multihash structure, no digest length check.
// Callers using isValidCid as a trust gate admit nonexistent/garbage
// identifiers. The robust decodeDigest/verifyContent path exists, so
// the weak check is a footgun in the same class.
//
// lib/services/ipfs_service.dart:51-54 pinCid() records ANY string as
// pinned and returns true - callers cannot distinguish "content held"
// from "label registered"; getFile() yields EMPTY bytes for unknown
// CIDs instead of signalling absence (line 47), and findProviders
// reports a DHT provider for content nobody holds (line 65) -
// PreservationService.checkContentHealth then reports 'endangered'
// rather than 'lost' for content that does not exist.
//
// Asserts SECURE expectations; failures mark trust-boundary
// weaknesses, not mere cosmetic issues.
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/preservation_service.dart';

void main() {
  test('isValidCid must reject structurally invalid identifiers', () {
    final svc = CidService();
    // 40+ chars starting 'b' but NOT valid base32 (0,1,8,9 excluded)
    // and not a multihash - accepted anyway by the shape check.
    expect(svc.isValidCid('b${'0' * 39}'), isFalse,
        reason: 'invalid multibase chars accepted as a CID');
    expect(svc.isValidCid('z${'!' * 40}'), isFalse,
        reason: 'arbitrary punctuation accepted as a CIDv1');
    // A REAL cid to prove the positive path still works.
    expect(svc.isValidCid(svc.cidFromBytes(Uint8List.fromList([1, 2, 3]))),
        isTrue);
  });

  test('pinCid must not claim success for unresolvable identifiers', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ipfs = container.read(ipfsServiceProvider);

    final ok = await ipfs.pinCid('definitely-not-a-cid');
    expect(ok, isFalse,
        reason: 'pinCid("definitely-not-a-cid") returned true and added it to '
            'pinnedCids — pin claims are unconstrained by resolution or '
            'validity, so preservation health and storage accounting '
            'count phantom content');
  });

  test('health of nonexistent content must not read as endangered', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final preservation = container.read(preservationServiceProvider);

    final status = await preservation.checkContentHealth('not-a-real-cid');
    expect(status, HealthStatus.lost,
        reason: 'findProviders fabricates a DHT provider for unheld content, '
            'so health reports $status for content that does not exist — '
            'preservation decisions are made on phantom availability');
  });
}
