import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' hide CreditTransaction;
import 'package:alexandria/services/credits/credit_models.dart';
import 'package:alexandria/services/credits/credit_service.dart';

void main() {
  group('CreditService persistence — restart survival (ALX-005 §6.1)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('daily mint caps persist across service instances on one db',
        () async {
      final instanceA = CreditService(db: db, initialBalance: 0.0);
      await instanceA.ready;

      // 500 MB @ 1.0x rarity → 50.0 per award; four awards exhaust the
      // 200.0 daily storage cap.
      for (var i = 0; i < 4; i++) {
        final earned = instanceA.awardStorageCredits(
          sizeBytes: 500 * 1024 * 1024,
          peerCount: 8,
          porPassed: true,
          cid: 'bafy_cap_$i',
        );
        expect(earned, 50.0, reason: 'award $i should mint the full 50.0');
      }
      // Same-day award beyond the cap is already clamped to zero.
      expect(
        instanceA.awardStorageCredits(
          sizeBytes: 500 * 1024 * 1024,
          peerCount: 8,
          porPassed: true,
          cid: 'bafy_cap_over',
        ),
        0.0,
      );
      await instanceA.settled;

      // Simulated restart: a fresh service on the same database must see
      // the exhausted cap - the farming vector is closed.
      final instanceB = CreditService(db: db, initialBalance: 0.0);
      await instanceB.ready;
      expect(
        instanceB.awardStorageCredits(
          sizeBytes: 500 * 1024 * 1024,
          peerCount: 8,
          porPassed: true,
          cid: 'bafy_after_restart',
        ),
        0.0,
      );
    });

    test('every mint path records unattested transactions only', () async {
      final service = CreditService(db: db);
      await service.ready;

      service.awardStorageCredits(
        sizeBytes: 10 * 1024 * 1024,
        peerCount: 1,
        porPassed: true,
        cid: 'bafy_rare',
        rarityAttested: true, // bumps the multiplier, still self-certified
      );
      service.awardComputeCredits(cauchyMb: 5.0);
      service.awardVerificationCredits(
        action: 'DOI reconciliation',
        targetId: '10.1038/test',
      );
      service.awardSponsorshipKickback(
        campaignId: 'camp-1',
        grossCredits: 10.0,
        dwellTimeSeconds: 5.0,
      );
      service.awardBountyEscrow(amount: 7.0, bountyId: 'b1', cid: 'bafy_b');
      // Negative path (PoR slashing) is also unattested by definition.
      service.awardStorageCredits(
        sizeBytes: 1024,
        peerCount: 1,
        porPassed: false,
        cid: 'bafy_failed',
      );

      expect(service.transactions.length, greaterThanOrEqualTo(6));
      expect(service.transactions.every((t) => !t.isAttested), isTrue);
      expect(service.attestedBalance, 0.0);
      expect(service.unattestedBalance, service.balance);

      // The persisted rows carry the flag too.
      await service.settled;
      final rows = await db.getCreditTransactions();
      expect(rows, isNotEmpty);
      expect(rows.every((r) => r['isAttested'] == false), isTrue);
    });

    test('ledger history and balance survive a restart', () async {
      final instanceA = CreditService(db: db); // 100.0 genesis
      await instanceA.ready;
      expect(instanceA.transactions.length, 1); // genesis only

      instanceA.awardComputeCredits(cauchyMb: 5.0); // +10.0
      instanceA.spendCredits(amount: 30.0, reason: 'Replication fee');
      expect(instanceA.balance, 80.0);
      await instanceA.settled;

      final instanceB = CreditService(db: db);
      await instanceB.ready;

      // Prior history is warmed; genesis was granted exactly once -
      // a restart can neither reset nor double the welcome allocation.
      expect(instanceB.transactions.length, instanceA.transactions.length);
      expect(
        instanceB.transactions
            .where((t) => t.description.contains('Genesis'))
            .length,
        1,
      );
      expect(
        instanceB.transactions.any((t) => t.type == CreditType.computeReward),
        isTrue,
      );
      expect(
        instanceB.transactions.any((t) => t.amount < 0),
        isTrue,
        reason: 'the persisted debit must be visible after restart',
      );
      expect(instanceB.balance, 80.0);
      expect(instanceB.attestedBalance, 0.0);
      expect(instanceB.unattestedBalance, 80.0);
    });

    test('pre-hydration award cannot bypass the persisted daily mint cap',
        () async {
      // Seed 150/200 of the daily storage cap.
      final instanceA = CreditService(db: db, initialBalance: 0.0);
      await instanceA.ready;
      for (var i = 0; i < 3; i++) {
        expect(
          instanceA.awardStorageCredits(
            sizeBytes: 500 * 1024 * 1024,
            peerCount: 8,
            porPassed: true,
            cid: 'bafy_seed_$i',
          ),
          50.0,
        );
      }
      await instanceA.settled;

      // Simulated restart: an award fired BEFORE hydration must mint
      // nothing - the persisted 150/200 counter is not yet loaded, and
      // acting on the empty in-memory counter was the proven bypass.
      final instanceB = CreditService(db: db, initialBalance: 0.0);
      expect(
        instanceB.awardStorageCredits(
          sizeBytes: 500 * 1024 * 1024,
          peerCount: 8,
          porPassed: true,
          cid: 'bafy_prehydration',
        ),
        0.0,
        reason: 'pre-hydration mutations are refused (E-T2 #1)',
      );
      await instanceB.ready;

      // Only the honest remainder is mintable - the day ends at the cap.
      expect(
        instanceB.awardStorageCredits(
          sizeBytes: 500 * 1024 * 1024,
          peerCount: 8,
          porPassed: true,
          cid: 'bafy_posthydration',
        ),
        50.0,
      );
      expect(
        instanceB.awardStorageCredits(
          sizeBytes: 500 * 1024 * 1024,
          peerCount: 8,
          porPassed: true,
          cid: 'bafy_over_cap',
        ),
        0.0,
      );
      await instanceB.settled;
      final minted = await db.getDailyMinted(_testDayKey());
      expect(minted['storageReward'], 200.0);
    });

    test('pre-hydration spend cannot exceed the real ledger balance', () async {
      // Real ledger balance = 10.0 (no genesis granted).
      final instanceA = CreditService(db: db, initialBalance: 0.0);
      await instanceA.ready;
      instanceA.awardComputeCredits(cauchyMb: 5.0); // +10.0
      await instanceA.settled;

      // Simulated restart: before hydration the balance is 0.0 - never
      // the phantom initialBalance - and every mutator is gated.
      final instanceB = CreditService(db: db, initialBalance: 0.0);
      expect(
        instanceB.spendCredits(amount: 90.0, reason: 'pre-hydration drain'),
        isFalse,
        reason: 'a spend racing hydration must not land (E-T2 #2)',
      );
      expect(instanceB.balance, 0.0,
          reason: 'persistent mode never exposes a phantom balance');
      await instanceB.ready;

      // The real ledger balance is now authoritative.
      expect(instanceB.balance, 10.0);
      expect(
          instanceB.spendCredits(amount: 90.0, reason: 'overspend'), isFalse);
      expect(
          instanceB.spendCredits(amount: 5.0, reason: 'honest spend'), isTrue);
      expect(instanceB.balance, 5.0);
      await instanceB.settled;
    });

    test('concurrent instances on one database persist a single genesis row',
        () async {
      // Both services hydrate the same fresh database before either's
      // genesis write can land - the proven double-grant race (E-T2 #3).
      final instanceA = CreditService(db: db);
      final instanceB = CreditService(db: db);
      await Future.wait([instanceA.ready, instanceB.ready]);
      await Future.wait([instanceA.settled, instanceB.settled]);

      final rows = await db.getCreditTransactions();
      expect(
        rows
            .where((r) => (r['description'] as String).contains('Genesis'))
            .length,
        1,
        reason: 'the deterministic genesis id collapses racing grants '
            'onto one ledger row',
      );
      // A third instance ("restart") converges on the same single grant.
      final instanceC = CreditService(db: db);
      await instanceC.ready;
      expect(instanceC.balance, 100.0);
      expect(
        instanceC.transactions
            .where((t) => t.description.contains('Genesis'))
            .length,
        1,
      );
    });

    test('restart after a hydration failure still converges on genesis',
        () async {
      final flakyDb = _FlakyReadDatabase(failures: 1);
      addTearDown(flakyDb.close);

      final instanceA = CreditService(db: flakyDb);
      await instanceA.ready; // hydration throws → degraded path
      await instanceA.settled;

      // Genesis was still granted - the catch path checks for a genesis
      // row, not merely an empty list - and persisted (only reads fail).
      expect(instanceA.balance, 100.0);
      expect(
        instanceA.transactions
            .where((t) => t.description.contains('Genesis'))
            .length,
        1,
      );

      // "Restart" on the same database: reads now succeed, the persisted
      // genesis is seen, and no second grant is issued (E-T2 #7).
      final instanceB = CreditService(db: flakyDb);
      await instanceB.ready;
      await instanceB.settled;
      expect(instanceB.balance, 100.0);
      final rows = await flakyDb.getCreditTransactions();
      expect(
        rows
            .where((r) => (r['description'] as String).contains('Genesis'))
            .length,
        1,
      );
    });

    test('service without a database still works purely in-memory', () async {
      final service = CreditService(initialBalance: 50.0);
      await service.ready; // resolves immediately, no db attached

      expect(service.balance, 50.0);
      expect(service.transactions.length, 1);
      expect(service.transactions.first.isAttested, isFalse);

      final earned = service.awardComputeCredits(cauchyMb: 5.0);
      expect(earned, 10.0);
      expect(service.balance, 60.0);
      expect(service.attestedBalance, 0.0);
      expect(service.unattestedBalance, service.balance);
      await service.settled; // no-op without a db, but must not throw
    });
  });
}

/// UTC day key matching CreditService's mint-cap key format.
String _testDayKey() {
  final now = DateTime.now().toUtc();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

/// Database whose ledger read fails [failures] times before delegating to
/// the real implementation - simulates a transient hydration failure so
/// the degraded catch path can be exercised (E-T2 #7).
class _FlakyReadDatabase extends AppDatabase {
  _FlakyReadDatabase({required this.failures});

  int failures;

  @override
  Future<List<Map<String, dynamic>>> getCreditTransactions({int limit = 200}) {
    if (failures > 0) {
      failures--;
      throw StateError('simulated ledger read failure');
    }
    return super.getCreditTransactions(limit: limit);
  }
}
