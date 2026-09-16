import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/build_info_service.dart';

void main() {
  group('BuildInfo claimed provenance (ALX-010)', () {
    test('dev defaults are present when no dart-defines are injected', () {
      final info = BuildInfo.current();

      expect(info.commitSha, BuildInfo.devCommitSha);
      expect(info.commitSha, 'dev-local');
      // flutter test compiles in debug mode, so channel must not be release
      expect(info.buildChannel, isNot('release'));
      expect(info.artifactDigest, isNull);
      expect(info.builtAt, isNull);
    });

    test('isOfficialBuild is false without injected defines', () {
      final info = BuildInfo.current();
      expect(info.isOfficialBuild, isFalse);
    });

    test('isOfficialBuild requires injected SHA AND release channel', () {
      expect(
        BuildInfo(commitSha: 'a1b2c3d4e5f6', buildChannel: 'release')
            .isOfficialBuild,
        isTrue,
      );
      expect(
        BuildInfo(commitSha: 'a1b2c3d4e5f6', buildChannel: 'debug')
            .isOfficialBuild,
        isFalse,
      );
      expect(
        BuildInfo(commitSha: 'dev-local', buildChannel: 'release')
            .isOfficialBuild,
        isFalse,
      );
      expect(
        BuildInfo(commitSha: '', buildChannel: 'release').isOfficialBuild,
        isFalse,
      );
    });

    test('claimedBuildInfo uses claimed_-prefixed keys uniformly', () {
      final map = BuildInfo.current().claimedBuildInfo;

      for (final key in map.keys) {
        expect(
          key.startsWith('claimed_'),
          isTrue,
          reason: 'provenance key "$key" must carry the claimed_ prefix',
        );
      }

      expect(map['claimed_commit_sha'], 'dev-local');
      expect(map['claimed_build_channel'], isNot('release'));
      expect(map['claimed_client_version'], 'dev');
      expect(map['claimed_protocol_version'], '1');
      // Optional keys are omitted when their defines were not injected
      expect(map.containsKey('claimed_artifact_digest'), isFalse);
      expect(map.containsKey('claimed_build_timestamp'), isFalse);
    });

    test('claimedBuildInfo includes optional keys when values are present', () {
      final info = BuildInfo(
        commitSha: 'a1b2c3d4e5f6',
        buildChannel: 'release',
        artifactDigest: 'sha256:deadbeef',
        builtAt: '2025-01-01T00:00:00Z',
      );
      final map = info.claimedBuildInfo;

      expect(map['claimed_commit_sha'], 'a1b2c3d4e5f6');
      expect(map['claimed_build_channel'], 'release');
      expect(map['claimed_artifact_digest'], 'sha256:deadbeef');
      expect(map['claimed_build_timestamp'], '2025-01-01T00:00:00Z');
      expect(map['claimed_protocol_version'], '1');
    });

    test(
        'claimedBroadcastInfo is the narrowed wire-safe subset '
        '(REV3-D review)', () {
      final info = BuildInfo(
        commitSha: 'a1b2c3d4e5f6',
        buildChannel: 'release',
        artifactDigest: 'sha256:deadbeef',
        builtAt: '2025-01-01T00:00:00Z',
      );
      final map = info.claimedBroadcastInfo;

      expect(map, hasLength(3));
      expect(map['claimed_client_version'], info.clientVersion);
      expect(map['claimed_build_channel'], 'release');
      expect(map['claimed_protocol_version'], '1');
      // High-entropy provenance stays local - broadcast must not
      // advertise exact builds for targeted-exploitation scanning.
      expect(map.containsKey('claimed_commit_sha'), isFalse);
      expect(map.containsKey('claimed_artifact_digest'), isFalse);
      expect(map.containsKey('claimed_build_timestamp'), isFalse);
    });

    test(
        'claimed_client_version defaults to dev sentinel and is '
        'claimed_-prefixed (ALX-012 B3-lite)', () {
      final info = BuildInfo.current();

      // Clearly-non-official default when ALX_CLIENT_VERSION is not injected
      expect(info.clientVersion, BuildInfo.devClientVersion);
      expect(info.clientVersion, 'dev');

      final map = info.claimedBuildInfo;
      expect(map.containsKey('claimed_client_version'), isTrue);
      expect(map['claimed_client_version'], 'dev');
      // Advisory only: the field exists alongside, never instead of, the
      // claimed_ provenance - and carries no trust weight by invariant.
      expect(map.keys.where((k) => k.startsWith('claimed_')).length,
          greaterThanOrEqualTo(3));
    });

    test('claimed_client_version honors an injected semver value', () {
      final info = BuildInfo(
        commitSha: 'a1b2c3d4e5f6',
        buildChannel: 'release',
        clientVersion: '1.4.2',
      );
      expect(info.clientVersion, '1.4.2');
      expect(info.claimedBuildInfo['claimed_client_version'], '1.4.2');
    });

    test(
        'claimed client info rides the signed Beacon body — tampering '
        'with claimed_client_version breaks the signature', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();

      final envelope = await BeaconEnvelope.create(
        kind: 'bounty_broadcast',
        keyPair: keyPair,
        payload: {'cid': 'bafy_test_123'},
        clientInfo: BuildInfo.current().claimedBuildInfo,
      );

      // claimed_client_version is present inside the signed payload
      expect(envelope.clientInfo?['claimed_client_version'], 'dev');
      expect(await envelope.verify(), isTrue);

      // A relay or forked client that rewrites the claimed version after
      // signing must invalidate the envelope: claimed metadata is signed
      // *as content*, so tampering is detectable - yet it still carries
      // zero trust weight (ALX-010 / ALX-011 §8).
      final tampered = BeaconEnvelope(
        v: envelope.v,
        kind: envelope.kind,
        agentId: envelope.agentId,
        ts: envelope.ts,
        nonce: envelope.nonce,
        pubkey: envelope.pubkey,
        sig: envelope.sig,
        payload: <String, dynamic>{
          ...envelope.payload,
          'client_info': <String, dynamic>{
            ...envelope.clientInfo!,
            'claimed_client_version': '9.9.9',
          },
        },
      );
      expect(tampered.clientInfo?['claimed_client_version'], '9.9.9');
      expect(await tampered.verify(), isFalse);
    });

    test('commitShort abbreviates git SHAs but keeps sentinel values intact',
        () {
      expect(
        BuildInfo(
          commitSha: 'a1b2c3d4e5f6a7b8',
          buildChannel: 'debug',
        ).commitShort,
        'a1b2c3d',
      );
      expect(
        BuildInfo(commitSha: 'dev-local', buildChannel: 'debug').commitShort,
        'dev-local',
      );
    });
  });
}
