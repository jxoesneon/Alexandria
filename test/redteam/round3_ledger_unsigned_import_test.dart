// RED TEAM PoC - LedgerService.importFromJson verifies ONLY the
// previous-hash LINKAGE of imported entries; it never verifies the
// Ed25519 `signature` field each entry carries
// (lib/services/ledger_service.dart:277-299). A hand-crafted chain -
// hashes are recomputable by anyone (computeHash is deterministic
// sha256 over public fields) - imports cleanly and inflates
// totalReputation, which gates GovernanceService.canVote
// (minReputationToVote=10) and scales every vote's weight.
//
// Companion gap: ReputationWeights.dailyLimits exist but recordAction
// never consults them (isWithinDailyLimit is dead code at the write
// path - nothing calls it before appending). Reputation accrual is
// unbounded in both time and quantity.
//
// Asserts the SECURE expectation: imported ledger entries that cannot
// be signature-verified against a known identity must not accrue
// reputation, and the write path must enforce its own daily limits.
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ledger_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeIdentityService extends IdentityService {
  final AlexandriaIdentity _identity;
  _FakeIdentityService(this._identity) : super(SecureStorageService());
  @override
  Future<AlexandriaIdentity?> getIdentity() async => _identity;
  @override
  Future<Uint8List> sign(Uint8List data) async => Uint8List(64);
}

/// Forge a hash-linked entry exactly the way importFromJson expects.
Map<String, dynamic> _forgedEntry(
    int index, DateTime ts, String action, String cid, Uint8List prev) {
  return {
    'index': index,
    'timestamp': ts.toIso8601String(),
    'action': action,
    'contentCid': cid,
    'previousHash': base64Encode(prev),
    'signature': base64Encode(Uint8List(64)), // never verified
    'crossSignatures': <dynamic>[],
  };
}

void main() {
  test(
      'imported ledger entries are accepted without signature '
      'verification → forged reputation', () async {
    final svc = LedgerService(_FakeIdentityService(AlexandriaIdentity(
      publicKey: Uint8List(32),
      privateKey: Uint8List(32),
      createdAt: DateTime(2020),
    )));

    // Build a self-consistent 100-entry chain of validateHash actions
    // (2.0 rep each). The chain hashes link correctly - the signatures
    // are all zeros and no public key is ever consulted.
    final entries = <Map<String, dynamic>>[];
    var prev = LedgerService.genesisHash;
    for (var i = 0; i < 100; i++) {
      final ts = DateTime(2024, 1, 1).add(Duration(minutes: i));
      entries.add(_forgedEntry(i, ts, 'validateHash', 'bafyfake$i', prev));
      // Recompute the link the verifier will expect next.
      final data =
          '$i|${ts.toIso8601String()}|validateHash|bafyfake$i|${base64Encode(prev)}';
      prev = Uint8List.fromList(sha256.convert(utf8.encode(data)).bytes);
    }

    final imported = await svc.importFromJson(jsonEncode(entries));
    expect(imported, isFalse,
        reason: 'a fully forged ledger (zero-filled signatures, no known '
            'signer) imported successfully — only hash linkage is '
            'checked, so any crafted chain accrues real reputation '
            'that gates governance voting.');
    expect(svc.totalReputation, 0.0,
        reason: 'forged chain credited ${svc.totalReputation} reputation — '
            'enough to pass GovernanceConstants.minReputationToVote '
            '(10) and cast heavyweight votes');
  });

  test('recordAction must enforce its own daily limits', () async {
    final svc = LedgerService(_FakeIdentityService(AlexandriaIdentity(
      publicKey: Uint8List(32),
      privateKey: Uint8List(32),
      createdAt: DateTime(2020),
    )));

    // validateHash daily limit is 50; append 60 in one loop.
    for (var i = 0; i < 60; i++) {
      await svc.recordAction(
          action: LedgerActionType.validateHash, contentCid: 'cid$i');
    }
    final today =
        svc.getTodayActionCounts()[LedgerActionType.validateHash] ?? 0;
    expect(today, lessThanOrEqualTo(50),
        reason: 'recordAction wrote $today validateHash entries today — '
            'ReputationWeights.dailyLimits[validateHash]=50 is defined '
            'but never enforced on the write path (isWithinDailyLimit '
            'is never consulted). Reputation inflates without bound.');
  });
}
