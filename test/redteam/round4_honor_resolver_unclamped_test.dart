// RED TEAM PoC — Round-4: HonorSystem gained a reputationResolver seam
// (round-3 hardening) — caller claims are clamped to
// maxClaimedReputation when no resolver is wired. But the RESOLVED
// (attested) value is used RAW:
//
//   lib/logic/honor_system.dart:49
//     final resolved = reputationResolver?.call(validatorId) ??
//         reputation.clamp(0, maxClaimedReputation);
//
// HonorBandwidthService — the sibling fix from the same round —
// explicitly clamps even ATTESTED values ("a compromised or buggy
// attestation source must not mint unbounded priority either",
// maxAttestedHonor/maxAttestedPoR). HonorSystem applies no such bound:
//
//   * resolver returns a negative score → log(reputation + 10) with a
//     negative argument → NaN → NaN.round() THROWS — a buggy attestation
//     source crashes every trust computation;
//   * resolver returns a huge score → unbounded weight dominates every
//     tally (the exact failure maxClaimedReputation exists to prevent).
//
// Asserts the SECURE expectation: attested reputation must be clamped
// into a sane range exactly like claimed reputation and like the
// bandwidth service's attested values — a broken resolver must degrade
// to bounded weight, never NaN/unbounded.
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/logic/honor_system.dart';

void main() {
  test('a negative attested reputation must not crash the tally',
      () async {
    final hs = HonorSystem(reputationResolver: (_) => -100);
    hs.recordVote(validatorId: 'v1', targetCid: 'cidA', score: 1);

    int? score;
    Object? threw;
    try {
      score = hs.computeTrustScore('cidA');
    } catch (e) {
      threw = e;
    }
    expect(threw, isNull,
        reason:
            'computeTrustScore threw $threw — resolver returned -100, '
            'log(-90) is NaN, and NaN.round() throws. The attested value '
            'is used unclamped; a buggy resolver poisons every tally.');
    expect(score, isNotNull);
  });

  test('an unbounded attested reputation must not dominate the tally',
      () async {
    final hs = HonorSystem(
        reputationResolver: (_) => 1 << 60); // compromised resolver
    hs.recordVote(validatorId: 'sybil', targetCid: 'cidB', score: 1);
    final score = hs.computeTrustScore('cidB');

    // With a sane bound the weight of one vote is at most ~log10 of the
    // cap; maxClaimedReputation=10000 → weight ≤ ~4.0 per vote.
    expect(score.abs(), lessThanOrEqualTo(5),
        reason:
            'a single vote carried weight ~log10(2^60)≈18 — the attested '
            'reputation path has no bound (HonorBandwidthService clamps '
            'attested values at maxAttestedHonor; HonorSystem does not), '
            'so a compromised/buggy attestation source mints unlimited '
            'trust weight.');
  });
}
