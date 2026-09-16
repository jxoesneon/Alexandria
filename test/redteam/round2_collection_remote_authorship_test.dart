// RED TEAM PoC — CollectionService.mergeRemoteState applies unsigned,
// unauthenticated remote state to LOCAL collections.
//
// lib/services/collection_service.dart:533-585 merges attacker JSON
// purely on HLC timestamp comparison: no Ed25519 signature is
// verified, `author` is taken straight off the wire, and the
// collection's accessControl roles are never consulted. Any peer on
// the sync topic can:
//   1. overwrite name/description of a collection it has NO role in,
//   2. mint a forged author for the write (repudiation/spoofing), and
//   3. pin a FAR-FUTURE wallTime so every subsequent legitimate edit
//      loses the LWW comparison — a durable metadata lockout.
// SyncService publishes queued ops to /alexandria/sync/v1/<id> with no
// signing either, so wire input reaches this merge unauthenticated.
//
// Asserts the SECURE expectation: unauthenticated remote state must
// not mutate a collection the remote party has no role in. Failure
// marks a live authorship/integrity bypass.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/collection_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

/// Deterministic fake identity — mirrors test harness conventions.
class _FakeIdentityService extends IdentityService {
  final AlexandriaIdentity _identity;
  _FakeIdentityService(this._identity) : super(SecureStorageService());

  @override
  Future<AlexandriaIdentity?> getIdentity() async => _identity;

  @override
  Future<Uint8List> sign(Uint8List data) async => Uint8List(64);
}

AlexandriaIdentity _identity(int fill) => AlexandriaIdentity(
      publicKey: Uint8List.fromList(List.filled(32, fill)),
      privateKey: Uint8List.fromList(List.filled(32, fill + 1)),
      createdAt: DateTime(2024),
    );

/// Attacker-forged LWW register payload (no signature anywhere).
Map<String, dynamic> _forgedRegister(
  String value,
  int wallTime,
  Uint8List attackerKey,
) =>
    {
      'value': value,
      'timestamp': {
        'wallTime': wallTime,
        'logical': 0,
        'nodeId': base64Encode(attackerKey),
      },
      'author': base64Encode(attackerKey),
    };

void main() {
  test('remote state with no role/signature must not overwrite metadata',
      () async {
    final ownerId = _identity(0x11);
    final attackerKey = _identity(0xEE).publicKey; // NOT in accessControl
    final svc = CollectionService(_FakeIdentityService(ownerId));

    final col = await svc.createCollection(
      name: 'Endangered Manuscripts',
      description: 'Curated by the librarian',
    );

    final futureWall = DateTime.now().millisecondsSinceEpoch + 86400000;
    await svc.mergeRemoteState(col.id, {
      'name': _forgedRegister('PWNED BY SYBIL', futureWall, attackerKey),
      'description': _forgedRegister(
          'attacker-controlled description', futureWall, attackerKey),
    });

    expect(col.name.value, 'Endangered Manuscripts',
        reason:
            'an unsigned remote LWW register overwrote the collection name; '
            'no signature check and no accessControl role check gate '
            'mergeRemoteState');
    expect(col.description.value, 'Curated by the librarian');
  });

  test('forged far-future timestamp must not lock out legitimate edits',
      () async {
    final ownerId = _identity(0x22);
    final attackerKey = _identity(0xEE).publicKey;
    final svc = CollectionService(_FakeIdentityService(ownerId));
    final col = await svc.createCollection(name: 'Original');

    // Attacker pins the name register at wall-clock +10 years.
    final farFuture =
        DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch;
    await svc.mergeRemoteState(col.id, {
      'name': _forgedRegister('ATTACKER LOCKOUT', farFuture, attackerKey),
    });
    expect(col.name.value, 'Original',
        reason: 'forged future HLC captured the name register');

    // Even IF the overwrite landed, a legitimate same-wall-time local
    // edit must be able to reclaim the register. Simulate an owner edit
    // at the real current time via a second remote merge (the only
    // write path this service exposes for remote state).
    final nowWall = DateTime.now().millisecondsSinceEpoch;
    await svc.mergeRemoteState(col.id, {
      'name': _forgedRegister('Recovered Title', nowWall, ownerId.publicKey),
    });
    expect(col.name.value, 'Recovered Title',
        reason: 'the forged far-future timestamp permanently wins the LWW '
            'comparison — every real edit until that wall time is '
            'silently discarded');
  });

  test('malformed remote state must fail safe, not crash the merge', () async {
    final ownerId = _identity(0x33);
    final svc = CollectionService(_FakeIdentityService(ownerId));
    final col = await svc.createCollection(name: 'Stable');

    // wallTime arrives as a STRING — HybridLogicalClock.fromJson does
    // `json['wallTime'] as int` with no type guard, so a hostile sync
    // message throws inside the merge path.
    Object? thrown;
    try {
      await svc.mergeRemoteState(col.id, {
        'name': {
          'value': 'x',
          'timestamp': {
            'wallTime': 'not-an-int',
            'logical': 0,
            'nodeId': base64Encode(Uint8List(32)),
          },
          'author': base64Encode(Uint8List(32)),
        },
      });
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isNull,
        reason:
            'a malformed remote HLC threw $thrown out of mergeRemoteState — '
            'untyped wire data crashes the sync handler');
    expect(col.name.value, 'Stable');
  });
}
