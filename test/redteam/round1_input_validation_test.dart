// RED TEAM probes - numeric input validation on the mint paths.
//
// awardStorageCredits computes `(mbSize * 0.1 * rarityWeight)
// .clamp(0.1, 50.0)` BEFORE the daily cap (credit_service.dart:446-447):
// the clamp's LOWER bound turns a zero or NEGATIVE sizeBytes into a
// guaranteed +0.1 ℭ mint. Any future caller that forwards
// attacker-influenced sizes mints free credits on empty input.
// awardComputeCredits, by contrast, passes its formula straight to
// _capDailyMint, whose lower clamp is 0 - the inconsistency itself is
// the tell.
//
// Asserts the SECURE expectation; failure marks a live mint-on-garbage.
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/sponsorship_service.dart';

void main() {
  test('zero/negative sizeBytes must mint NOTHING (clamp floor at 0)',
      () async {
    final s = CreditService(initialBalance: 0.0);
    final before = s.balance;
    // porPassed=true with no bytes actually proven.
    for (final size in <int>[0, -1, -1 << 20]) {
      final earned = s.awardStorageCredits(
          sizeBytes: size, peerCount: 2, porPassed: true, cid: 'c$size');
      expect(earned, 0.0,
          reason: 'sizeBytes=$size minted $earned ℭ — the 0.1 clamp '
              'floor turns garbage input into a mint');
    }
    expect(s.balance, before);
  });

  test('NaN dwell time must not satisfy the 5s sponsorship threshold',
      () async {
    final cs = CreditService(initialBalance: 0.0);
    final sp = SponsorshipService(creditService: cs, initialOptIn: true);
    final slot = sp.catalog.first;
    // `dwellTimeSeconds < 5.0` is false for NaN - the check passes.
    final receipt =
        sp.recordDwellImpression(slot: slot, dwellTimeSeconds: double.nan);
    expect(receipt, isNull,
        reason: 'NaN dwell passed the >=5s gate and minted a kickback');
    expect(cs.balance, 0.0);
  });
}
