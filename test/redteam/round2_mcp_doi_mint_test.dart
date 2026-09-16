// RED TEAM PoC - alexandria_ingest_doi mints 15 ℭ per DOI that is only
// REGEX-VALID - nothing is resolved, fetched, verified, or ingested.
//
// lib/services/agent/alexandria_mcp_server.dart:367-410 - `_ingestDoi`
// checks `^10\.\d{4,9}/\S+$` (any fabricated string passes:
// `10.0000/fake-1`), fabricates a "CID" from the string, writes the
// award as 'Verified and ingested scientific paper' via
// awardVerificationCredits, and returns credits_earned:15. The only
// bound is the persisted per-DOI dedup plus the 100 ℭ/day
// verificationReward cap - so an MCP-connected agent drains the full
// verification budget every day for work that never existed. The
// award text claims verification that was never performed - this is
// mint-on-garbage at the agent tool boundary, and the minted balance
// is spendable inside Alexandria even while payout rails are closed.
//
// Asserts the SECURE expectation: a "verification reward" must require
// verified input - a syntactically-valid fabricated DOI must mint
// nothing. Failure marks a live unearned-mint oracle.
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart'
    show AppDatabase, databaseProvider;
import 'package:alexandria/services/agent/alexandria_mcp_server.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fabricated DOIs must mint nothing — no verification occurred',
      () async {
    final db = AppDatabase();
    addTearDown(db.close);
    final poch = PoCHService();
    final credits =
        CreditService(pochService: poch, initialBalance: 0.0, db: db);
    await credits.ready;
    final container = ProviderContainer(overrides: [
      creditServiceProvider.overrideWith((_) => credits),
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    final server = AlexandriaMcpServer(
      creditService: credits,
      pochService: poch,
      cryptoBridgeService: CryptoBridgeService(creditService: credits),
      moltbookService: MoltbookService(creditService: credits),
      porService: container.read(proofOfRetrievabilityServiceProvider),
      ipfsService: container.read(ipfsServiceProvider),
      db: db,
    );

    // An agent mints on fabricated-but-regex-valid DOIs - no paper
    // exists, nothing was fetched or verified. Measure the REAL ledger
    // effect (the response hardcodes credits_earned:15.0 regardless of
    // what the capped mint actually granted - itself a misreport).
    var claimed = 0.0;
    for (var i = 0; i < 10; i++) {
      final res = await server.callTool('alexandria_ingest_doi', {
        'doi': '10.0000/fabricated-paper-$i',
      });
      expect(res['isError'], isFalse);
      final data = jsonDecode((res['content'] as List).first['text'] as String);
      claimed += (data['credits_earned'] as num).toDouble();
    }
    await credits.settled;

    expect(credits.balance, 0.0,
        reason: 'ten fabricated DOIs minted ${credits.balance} ℭ of real '
            'spendable balance (API claimed $claimed) — _ingestDoi '
            'awards a "verification" bounty for input that was never '
            'resolved or verified; the only bound is the 100 ℭ/day '
            'verificationReward cap, drained daily by any MCP caller. '
            'Note: claimed=$claimed exceeds even that cap — the tool '
            'misreports earnings when the clamp bites.');
  });
}
