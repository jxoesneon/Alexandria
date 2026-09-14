import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod provider exposing this node's self-declared [BuildInfo].
final buildInfoServiceProvider = Provider<BuildInfo>((ref) {
  return BuildInfo.current();
});

/// Self-declared build provenance metadata for this client.
///
/// IMPORTANT (ALX-010 review decision): everything exposed by this class is
/// *claimed* by the local client and carries ZERO trust weight. A forked or
/// malicious client can claim any commit hash, digest, or channel — nothing
/// here is remotely verifiable. The ONLY enforceable trust invariant in
/// Alexandria is peer-verified Ed25519 signatures over Beacon envelopes.
///
/// Therefore this metadata must NEVER gate admission, rewards, verification,
/// or any security decision. Its legitimate uses are debugging,
/// protocol-compat display, and quarantine heuristics for known-bad builds.
///
/// Values are injected at compile time via `--dart-define`, e.g.:
///   flutter build --dart-define=BUILD_COMMIT_SHA=`sha` \
///                 --dart-define=BUILD_ARTIFACT_DIGEST=`digest` \
///                 --dart-define=BUILD_TIMESTAMP=`iso8601`
class BuildInfo {
  /// Sentinel used when no commit SHA was injected at build time.
  static const String devCommitSha = 'dev-local';

  static const String _definedCommitSha = String.fromEnvironment(
    'BUILD_COMMIT_SHA',
    defaultValue: devCommitSha,
  );
  static const String _definedArtifactDigest = String.fromEnvironment(
    'BUILD_ARTIFACT_DIGEST',
  );
  static const String _definedBuildTimestamp = String.fromEnvironment(
    'BUILD_TIMESTAMP',
  );

  /// Full claimed commit SHA (or [devCommitSha] when not injected).
  final String commitSha;

  /// Short display form of [commitSha] (first 7 chars for git SHAs).
  final String commitShort;

  /// Build channel: 'release', 'debug', or 'dev' (profile/other).
  final String buildChannel;

  /// Claimed artifact digest, if injected at build time.
  final String? artifactDigest;

  /// Claimed build timestamp (ISO-8601), if injected at build time.
  final String? builtAt;

  /// True only when a commit SHA was injected AND the artifact was compiled
  /// in release mode. Still entirely self-declared — see class doc.
  final bool isOfficialBuild;

  BuildInfo({
    required this.commitSha,
    required this.buildChannel,
    this.artifactDigest,
    this.builtAt,
  })  : commitShort = _shorten(commitSha),
        isOfficialBuild = commitSha.isNotEmpty &&
            commitSha != devCommitSha &&
            buildChannel == 'release';

  /// Reads the compile-time defines and runtime compilation mode.
  factory BuildInfo.current() {
    return BuildInfo(
      commitSha: _definedCommitSha,
      buildChannel: _detectChannel(),
      artifactDigest:
          _definedArtifactDigest.isEmpty ? null : _definedArtifactDigest,
      builtAt: _definedBuildTimestamp.isEmpty ? null : _definedBuildTimestamp,
    );
  }

  static String _detectChannel() {
    if (kReleaseMode) return 'release';
    if (kDebugMode) return 'debug';
    return 'dev';
  }

  static String _shorten(String sha) {
    final looksLikeGitSha = RegExp(r'^[0-9a-fA-F]{8,}$').hasMatch(sha);
    if (looksLikeGitSha && sha.length > 7) return sha.substring(0, 7);
    return sha;
  }

  /// Self-declared provenance map, suitable for embedding inside a signed
  /// Beacon envelope's payload as `client_info`.
  ///
  /// Every provenance key carries the `claimed_` prefix so nothing downstream
  /// can mistake it for verified provenance. Optional keys are omitted when
  /// their values were not injected at build time.
  Map<String, dynamic> get claimedBuildInfo => <String, dynamic>{
        'claimed_commit_sha': commitSha,
        'claimed_build_channel': buildChannel,
        if (artifactDigest != null) 'claimed_artifact_digest': artifactDigest,
        if (builtAt != null) 'claimed_build_timestamp': builtAt,
        'protocol_version': '1',
      };
}
