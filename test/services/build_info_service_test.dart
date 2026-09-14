import 'package:flutter_test/flutter_test.dart';
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

    test('claimedBuildInfo uses claimed_-prefixed keys and protocol_version',
        () {
      final map = BuildInfo.current().claimedBuildInfo;

      for (final key in map.keys) {
        if (key == 'protocol_version') continue;
        expect(
          key.startsWith('claimed_'),
          isTrue,
          reason: 'provenance key "$key" must carry the claimed_ prefix',
        );
      }

      expect(map['claimed_commit_sha'], 'dev-local');
      expect(map['claimed_build_channel'], isNot('release'));
      expect(map['protocol_version'], '1');
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
      expect(map['protocol_version'], '1');
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
