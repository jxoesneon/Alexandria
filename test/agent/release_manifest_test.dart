// TUF-style threshold-signed release manifest machinery tests
// (ALX-012 §5.1): ReleaseManifest/ManifestTimestamp models, m-of-n
// Ed25519 threshold verification over the canonical preimage, role
// separation (release vs timestamp keys), freshness/staleness via the
// timestamp role, rollback resistance, raise-only floor semantics, the
// quorum-key registry, and the Beacon-envelope transport path.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/release/release_key_registry.dart';
import 'package:alexandria/services/release/release_manifest.dart';
import 'package:alexandria/services/release/release_manifest_authority.dart';

Future<SimpleKeyPair> _newKey() => Ed25519().newKeyPair();

Future<String> _pubHex(SimpleKeyPair kp) async =>
    bytesToHex((await kp.extractPublicKey()).bytes);

/// A 5-release-key + 1-timestamp-key quorum (3-of-5 release quorum).
class _SignerQuorum {
  final release = <String, SimpleKeyPair>{};
  final timestamp = <String, SimpleKeyPair>{};

  static Future<_SignerQuorum> create() async {
    final c = _SignerQuorum();
    for (var i = 1; i <= 5; i++) {
      c.release['rel-$i'] = await _newKey();
    }
    c.timestamp['ts-1'] = await _newKey();
    return c;
  }

  Future<ReleaseKeyRegistry> registry(
      {int releaseThreshold = 3, int timestampThreshold = 1}) async {
    final rel = <String, String>{};
    for (final e in release.entries) {
      rel[e.key] = await _pubHex(e.value);
    }
    final ts = <String, String>{};
    for (final e in timestamp.entries) {
      ts[e.key] = await _pubHex(e.value);
    }
    return StaticReleaseKeyRegistry(
      releaseKeys: rel,
      releaseThreshold: releaseThreshold,
      timestampKeys: ts,
      timestampThreshold: timestampThreshold,
    );
  }
}

const _t0 = 1800000000000; // fixed epoch ms baseline for tests

/// Signs a manifest under [relKeys] (subset → threshold control) and a
/// timestamp record under [tsKeys].
Future<SignedManifestBundle> _bundle({
  required Map<String, SimpleKeyPair> relKeys,
  required Map<String, SimpleKeyPair> tsKeys,
  int floor = 2,
  int seq = 1,
  int issuedAt = _t0,
  int manifestExp = _t0 + 3600000,
  int tsTime = _t0,
  int tsExp = _t0 + 600000,
}) async {
  final m = await ReleaseManifest.issue(
    minWireVersion: floor,
    sequence: seq,
    issuedAt: issuedAt,
    expiresAt: manifestExp,
    releaseSigners: relKeys,
  );
  final ts = await ManifestTimestamp.issue(
    m,
    timestampSigners: tsKeys,
    timestamp: tsTime,
    expiresAt: tsExp,
  );
  return SignedManifestBundle(manifest: m, timestamp: ts);
}

ReleaseManifestAuthority _authority(
  ReleaseKeyRegistry registry, {
  int baselineFloor = 1,
  int? persistedSequence,
  void Function(int)? onAccepted,
  DateTime Function()? clock,
}) =>
    ReleaseManifestAuthority(
      registry: registry,
      baselineFloor: baselineFloor,
      persistedSequence: persistedSequence ?? -1,
      onSequenceAccepted: onAccepted,
      clock: clock ?? () => DateTime.fromMillisecondsSinceEpoch(_t0),
    );

Map<String, SimpleKeyPair> _take(
        Map<String, SimpleKeyPair> m, Iterable<String> ids) =>
    {for (final id in ids) id: m[id]!};

void main() {
  group('threshold verification', () {
    test('a valid 3-of-5 signed manifest is accepted and raises the '
        'floor', () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry());
      expect(auth.effectiveFloor, 1); // baseline before any manifest

      final bundle = await _bundle(
          relKeys: _take(c.release, ['rel-1', 'rel-2', 'rel-3']),
          tsKeys: c.timestamp,
          floor: 2,
          seq: 1);
      expect(await auth.ingest(bundle), ManifestIngestResult.accepted);
      expect(auth.effectiveFloor, 2);
      expect(auth.acceptedSequence, 1);
      expect(auth.current, isNotNull);
      expect(auth.current!.minWireVersion, 2);
    });

    test('2-of-5 signatures refuse (below threshold)', () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry());
      final bundle = await _bundle(
          relKeys: _take(c.release, ['rel-1', 'rel-2']), tsKeys: c.timestamp);
      expect(await auth.ingest(bundle),
          ManifestIngestResult.insufficientReleaseSignatures);
      expect(auth.effectiveFloor, 1); // untouched
      expect(auth.acceptedSequence, -1);
    });

    test('a forged release signature never counts', () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry());
      final m = await ReleaseManifest.issue(
          minWireVersion: 2,
          sequence: 1,
          issuedAt: _t0,
          expiresAt: _t0 + 3600000,
          releaseSigners: _take(c.release, ['rel-1', 'rel-2', 'rel-3']));
      // Corrupt one signature byte.
      final sigs = m.signatures.toList();
      final bad = ManifestSignature(
          role: ManifestSignature.roleRelease,
          keyId: sigs[2].keyId,
          sig: base64Encode(
              Uint8List.fromList(base64Decode(sigs[2].sig))..[0] ^= 0xff));
      sigs[2] = bad;
      final forged = ReleaseManifest(
          minWireVersion: m.minWireVersion,
          sequence: m.sequence,
          issuedAt: m.issuedAt,
          expiresAt: m.expiresAt,
          signatures: sigs);
      final ts = await ManifestTimestamp.issue(forged,
          timestampSigners: c.timestamp,
          timestamp: _t0,
          expiresAt: _t0 + 600000);
      expect(
          await auth.ingest(
              SignedManifestBundle(manifest: forged, timestamp: ts)),
          ManifestIngestResult.insufficientReleaseSignatures);
    });

    test('duplicate keyIds count once — a signature flood is one vote',
        () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry());
      // 2 distinct keys + a duplicated keyId entry = still 2 votes.
      final bundle = await _bundle(
          relKeys: _take(c.release, ['rel-1', 'rel-2']),
          tsKeys: c.timestamp);
      final dup = ManifestSignature(
          role: ManifestSignature.roleRelease,
          keyId: 'rel-1',
          sig: bundle.manifest.signatures.first.sig);
      final flooded = ReleaseManifest(
          minWireVersion: bundle.manifest.minWireVersion,
          sequence: bundle.manifest.sequence,
          issuedAt: bundle.manifest.issuedAt,
          expiresAt: bundle.manifest.expiresAt,
          signatures: [...bundle.manifest.signatures, dup]);
      final ts = await ManifestTimestamp.issue(flooded,
          timestampSigners: c.timestamp,
          timestamp: _t0,
          expiresAt: _t0 + 600000);
      expect(
          await auth.ingest(
              SignedManifestBundle(manifest: flooded, timestamp: ts)),
          ManifestIngestResult.insufficientReleaseSignatures);
    });

    test('wrong-role signatures never count — release slot signed by '
        'timestamp key, timestamp slot signed by release key', () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry());

      // Release slot: 2 real release keys + the TIMESTAMP key's
      // signature presented under the release role with keyId 'ts-1'.
      final m = await ReleaseManifest.issue(
          minWireVersion: 2,
          sequence: 1,
          issuedAt: _t0,
          expiresAt: _t0 + 3600000,
          releaseSigners: _take(c.release, ['rel-1', 'rel-2']));
      final tsKeySig = await Ed25519().sign(
          ReleaseManifest.signingPreimage(
              minWireVersion: 2,
              sequence: 1,
              issuedAt: _t0,
              expiresAt: _t0 + 3600000),
          keyPair: c.timestamp['ts-1']!);
      final wrongRole = ReleaseManifest(
          minWireVersion: m.minWireVersion,
          sequence: m.sequence,
          issuedAt: m.issuedAt,
          expiresAt: m.expiresAt,
          signatures: [
            ...m.signatures,
            ManifestSignature(
                role: ManifestSignature.roleRelease,
                keyId: 'ts-1', // a timestamp keyId, not a release keyId
                sig: base64Encode(tsKeySig.bytes)),
          ]);
      final ts = await ManifestTimestamp.issue(wrongRole,
          timestampSigners: c.timestamp,
          timestamp: _t0,
          expiresAt: _t0 + 600000);
      expect(
          await auth.ingest(
              SignedManifestBundle(manifest: wrongRole, timestamp: ts)),
          ManifestIngestResult.insufficientReleaseSignatures);

      // Timestamp slot: a RELEASE key signs the freshness record —
      // release keys carry zero timestamp weight.
      final m2 = await ReleaseManifest.issue(
          minWireVersion: 2,
          sequence: 1,
          issuedAt: _t0,
          expiresAt: _t0 + 3600000,
          releaseSigners: _take(c.release, ['rel-1', 'rel-2', 'rel-3']));
      final badTsPreimage = ManifestTimestamp.signingPreimage(
          sequence: m2.sequence,
          manifestHash: m2.contentHash,
          timestamp: _t0,
          expiresAt: _t0 + 600000);
      final relTsSig = await Ed25519().sign(badTsPreimage,
          keyPair: c.release['rel-1']!);
      final badTs = ManifestTimestamp(
          sequence: m2.sequence,
          manifestHash: m2.contentHash,
          timestamp: _t0,
          expiresAt: _t0 + 600000,
          signatures: [
            ManifestSignature(
                role: ManifestSignature.roleTimestamp,
                keyId: 'rel-1', // a release keyId, not a timestamp keyId
                sig: base64Encode(relTsSig.bytes)),
          ]);
      expect(
          await auth.ingest(
              SignedManifestBundle(manifest: m2, timestamp: badTs)),
          ManifestIngestResult.insufficientTimestampSignatures);
    });
  });

  group('floor semantics (raise-only, never lower)', () {
    test('a floor below the baseline refuses', () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry(), baselineFloor: 2);
      final bundle = await _bundle(
          relKeys: _take(c.release, ['rel-1', 'rel-2', 'rel-3']),
          tsKeys: c.timestamp,
          floor: 1, // below baseline 2
          seq: 1);
      expect(await auth.ingest(bundle), ManifestIngestResult.floorLower);
      expect(auth.effectiveFloor, 2);
    });

    test('a floor below a previously accepted manifest refuses — the '
        'ratchet never reverses', () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry());
      final up = await _bundle(
          relKeys: _take(c.release, ['rel-1', 'rel-2', 'rel-3']),
          tsKeys: c.timestamp,
          floor: 3,
          seq: 1);
      expect(await auth.ingest(up), ManifestIngestResult.accepted);
      expect(auth.effectiveFloor, 3);

      // A validly-signed seq-2 manifest asserting floor 2 < 3 refuses.
      final down = await _bundle(
          relKeys: _take(c.release, ['rel-1', 'rel-2', 'rel-4']),
          tsKeys: c.timestamp,
          floor: 2,
          seq: 2);
      expect(await auth.ingest(down), ManifestIngestResult.floorLower);
      expect(auth.effectiveFloor, 3); // unchanged
      expect(auth.acceptedSequence, 1);
    });

    test('a floor equal to baseline is accepted (ratchets sequence '
        'without lowering)', () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry(), baselineFloor: 2);
      final bundle = await _bundle(
          relKeys: _take(c.release, ['rel-1', 'rel-2', 'rel-3']),
          tsKeys: c.timestamp,
          floor: 2,
          seq: 1);
      expect(await auth.ingest(bundle), ManifestIngestResult.accepted);
      expect(auth.effectiveFloor, 2);
    });
  });

  group('staleness / rollback / binding', () {
    test('expired manifest refuses', () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry());
      final bundle = await _bundle(
          relKeys: _take(c.release, ['rel-1', 'rel-2', 'rel-3']),
          tsKeys: c.timestamp,
          manifestExp: _t0 - 1, // already expired at the injected clock
          tsExp: _t0 + 600000);
      expect(await auth.ingest(bundle),
          ManifestIngestResult.expiredManifest);
    });

    test('stale timestamp record refuses (freeze/replay protection)',
        () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry());
      final bundle = await _bundle(
          relKeys: _take(c.release, ['rel-1', 'rel-2', 'rel-3']),
          tsKeys: c.timestamp,
          tsExp: _t0 - 1); // timestamp record expired
      expect(await auth.ingest(bundle),
          ManifestIngestResult.staleTimestamp);
    });

    test('a timestamp bound to a different manifest hash or sequence '
        'is malformed', () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry());
      final m = await ReleaseManifest.issue(
          minWireVersion: 2,
          sequence: 1,
          issuedAt: _t0,
          expiresAt: _t0 + 3600000,
          releaseSigners: _take(c.release, ['rel-1', 'rel-2', 'rel-3']));
      // Timestamp covers a DIFFERENT sequence.
      final tsWrong = ManifestTimestamp(
          sequence: 99,
          manifestHash: m.contentHash,
          timestamp: _t0,
          expiresAt: _t0 + 600000,
          signatures: const []);
      expect(
          await auth.ingest(
              SignedManifestBundle(manifest: m, timestamp: tsWrong)),
          ManifestIngestResult.malformed);
      // Timestamp covers a different manifest hash.
      final tsHash = ManifestTimestamp(
          sequence: m.sequence,
          manifestHash: 'deadbeef',
          timestamp: _t0,
          expiresAt: _t0 + 600000,
          signatures: const []);
      expect(
          await auth.ingest(
              SignedManifestBundle(manifest: m, timestamp: tsHash)),
          ManifestIngestResult.malformed);
    });

    test('rollback: a non-increasing sequence refuses after acceptance',
        () async {
      final c = await _SignerQuorum.create();
      final auth = _authority(await c.registry());
      final keys = _take(c.release, ['rel-1', 'rel-2', 'rel-3']);
      expect(
          await auth
              .ingest(await _bundle(relKeys: keys, tsKeys: c.timestamp, seq: 5)),
          ManifestIngestResult.accepted);
      // Same sequence replays refuse.
      expect(
          await auth
              .ingest(await _bundle(relKeys: keys, tsKeys: c.timestamp, seq: 5)),
          ManifestIngestResult.rollback);
      // A regressed sequence refuses.
      expect(
          await auth
              .ingest(await _bundle(relKeys: keys, tsKeys: c.timestamp, seq: 4)),
          ManifestIngestResult.rollback);
      // A strictly-greater sequence still passes.
      expect(
          await auth
              .ingest(await _bundle(relKeys: keys, tsKeys: c.timestamp, seq: 6)),
          ManifestIngestResult.accepted);
      expect(auth.acceptedSequence, 6);
    });

    test('the rollback cursor honours the persisted-sequence seam',
        () async {
      final c = await _SignerQuorum.create();
      var persisted = 0;
      final auth = _authority(await c.registry(),
          persistedSequence: 4, onAccepted: (s) => persisted = s);
      final keys = _take(c.release, ['rel-1', 'rel-2', 'rel-3']);
      // Restored cursor blocks seq <= 4.
      expect(
          await auth
              .ingest(await _bundle(relKeys: keys, tsKeys: c.timestamp, seq: 3)),
          ManifestIngestResult.rollback);
      expect(
          await auth
              .ingest(await _bundle(relKeys: keys, tsKeys: c.timestamp, seq: 7)),
          ManifestIngestResult.accepted);
      expect(persisted, 7); // pushed back through the persistence seam
    });
  });

  group('registry + envelope transport', () {
    test('the empty registry fails closed — nothing is ever trusted',
        () async {
      final c = await _SignerQuorum.create();
      const reg = EmptyReleaseKeyRegistry();
      final auth = _authority(reg);
      final bundle = await _bundle(
          relKeys: _take(c.release, ['rel-1', 'rel-2', 'rel-3']),
          tsKeys: c.timestamp);
      expect(await auth.ingest(bundle),
          ManifestIngestResult.insufficientReleaseSignatures);
      expect(auth.effectiveFloor, 1);
    });

    test('a manifest envelope signed by a release key is ingested; a '
        'non-quorum signer is dropped', () async {
      final c = await _SignerQuorum.create();
      final reg = await c.registry();
      final auth = _authority(reg);
      final keys = _take(c.release, ['rel-1', 'rel-2', 'rel-3']);
      final bundle =
          await _bundle(relKeys: keys, tsKeys: c.timestamp, floor: 2, seq: 1);

      // quorum-signed envelope (timestamp key is also a release key).
      final env = await bundle.toEnvelope(c.timestamp['ts-1']!);
      expect(await auth.ingestEnvelope(env), ManifestIngestResult.accepted);
      expect(auth.effectiveFloor, 2);

      // A non-quorum agent carrying the same bundle is refused at the
      // envelope gate.
      final impostor = await _newKey();
      final badEnv = await bundle.toEnvelope(impostor);
      expect(await auth.ingestEnvelope(badEnv),
          ManifestIngestResult.malformed);

      // Wrong-kind envelope drops.
      final wrongKind = await BeaconEnvelope.create(
          kind: 'moltbook_post',
          keyPair: c.timestamp['ts-1']!,
          payload: bundle.toPayloadBlock());
      expect(await auth.ingestEnvelope(wrongKind),
          ManifestIngestResult.malformed);
    });

    test('manifest JSON round-trips through the payload block', () async {
      final c = await _SignerQuorum.create();
      final keys = _take(c.release, ['rel-1', 'rel-2', 'rel-3']);
      final bundle =
          await _bundle(relKeys: keys, tsKeys: c.timestamp, floor: 4, seq: 9);
      final parsed =
          SignedManifestBundle.fromPayload(bundle.toPayloadBlock());
      expect(parsed, isNotNull);
      expect(parsed!.manifest.minWireVersion, 4);
      expect(parsed.manifest.sequence, 9);
      expect(parsed.manifest.contentHash, bundle.manifest.contentHash);
      expect(parsed.timestamp.manifestHash, bundle.manifest.contentHash);
    });
  });
}
