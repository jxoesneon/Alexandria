// Campaign-2 tests: per-vote signed biometric binding.
//
// Covers the strong human-attestation path:
//   * BiometricService.attestVoteIntent mints only behind a REAL
//     device-credential prompt (no fail-open escapes),
//   * ConsensusService.castVote requires the token to verify against
//     the actual ballot fields — forged, stale, wrong-field and
//     replayed tokens refuse the cast,
//   * a verified token is pinned onto the ballot
//     (Vote.humanAttestation) and folded into the signed payload,
//   * the temporal HumanAttestationClock window survives as the
//     compat fallback when no token is supplied.
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/consensus_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ledger_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeSecureStorage implements SecureStorageService {
  final Map<String, String> _data = {};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async => _data[key] = value;
  @override
  Future<void> delete(String key) async => _data.remove(key);
  @override
  Future<void> deleteAll() async => _data.clear();
  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}

class _FakeIdentityService implements IdentityService {
  _FakeIdentityService(this.keyPair, this.publicKeyBytes);
  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: publicKeyBytes,
        privateKey: Uint8List.fromList(await keyPair.extractPrivateKeyBytes()),
        createdAt: DateTime(2025, 1, 1),
      );

  @override
  Future<Uint8List> sign(Uint8List data) async {
    final sig = await Ed25519().sign(data, keyPair: keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Recomputes the token MAC in-test so forged/tampered variants can be
/// built — mirrors BiometricService's preimage exactly.
String _mac(Uint8List key, Uint8List voterKey, String changeId, bool approve,
    int issuedAt, String nonce) {
  final preimage =
      'alexandria:vote-attestation:v1|${base64Encode(voterKey)}|'
      '$changeId|$approve|$issuedAt|$nonce';
  return crypto.Hmac(crypto.sha256, key)
      .convert(utf8.encode(preimage))
      .toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');
  final attKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  late _FakeSecureStorage storage;
  late BiometricService biometric;
  late _FakeIdentityService identity;
  late LedgerService ledger;

  void mockLocalAuth({required bool available, required bool? authResult}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, (call) async {
      switch (call.method) {
        case 'isDeviceSupported':
        case 'canCheckBiometrics':
          return available;
        case 'getAvailableBiometrics':
          // local_auth's canCheckBiometrics resolves through
          // deviceSupportsBiometrics → getAvailableBiometrics, so the
          // enrolled list must empty out when `available` is false.
          return available ? ['fingerprint'] : <String>[];
        case 'authenticate':
          return authResult;
      }
      return null;
    });
  }

  setUp(() async {
    storage = _FakeSecureStorage();
    // Secure mode on — but attestVoteIntent must prompt regardless.
    storage._data['secure_mode_enabled'] = 'true';
    final container = ProviderContainer(overrides: [
      secureStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    biometric = container.read(biometricServiceProvider);
    mockLocalAuth(available: true, authResult: true);

    final algo = Ed25519();
    final kp = await algo.newKeyPair();
    final pub = await kp.extractPublicKey();
    identity = _FakeIdentityService(kp, Uint8List.fromList(pub.bytes));
    ledger = LedgerService(identity);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, null);
  });

  ConsensusService consensus({VoteAttestationVerifier? verifier}) =>
      ConsensusService(identity, ledger, voteAttestationVerifier: verifier);

  Future<ChangeRequest> propose(ConsensusService svc, {String cid = 'bafy_t'}) =>
      svc.proposeChange(
        targetCid: cid,
        field: 'title',
        currentValue: 'Old',
        proposedValue: 'New',
      );

  group('BiometricService.attestVoteIntent', () {
    test('mints a token only behind a real prompt success', () async {
      final token = await biometric.attestVoteIntent(
        voterKey: identity.publicKeyBytes,
        changeId: 'change-1',
        approve: true,
      );
      expect(token, isNotNull);
      expect(token!.startsWith('va1.'), isTrue);
      // A genuine prompt also feeds the recency clock.
      expect(biometric.lastAuthenticatedAt, isNotNull);
    });

    test('returns null when the prompt is dismissed/fails', () async {
      mockLocalAuth(available: true, authResult: false);
      final token = await biometric.attestVoteIntent(
        voterKey: identity.publicKeyBytes,
        changeId: 'change-1',
        approve: true,
      );
      expect(token, isNull);
      // No attestation — and the human clock must not move either.
      expect(biometric.lastAuthenticatedAt, isNull);
    });

    test('returns null when biometrics are unavailable (fail closed — '
        'no usability escape on the attestation path)', () async {
      mockLocalAuth(available: false, authResult: true);
      final token = await biometric.attestVoteIntent(
        voterKey: identity.publicKeyBytes,
        changeId: 'change-1',
        approve: true,
      );
      expect(token, isNull);
    });
  });

  group('BiometricService.consumeVoteAttestation', () {
    Future<String?> mint({
      Uint8List? voterKey,
      String changeId = 'change-1',
      bool approve = true,
    }) =>
        biometric.attestVoteIntent(
          voterKey: voterKey ?? identity.publicKeyBytes,
          changeId: changeId,
          approve: approve,
        );

    test('accepts a fresh token bound to the exact fields', () async {
      final token = (await mint())!;
      expect(
        await biometric.consumeVoteAttestation(
          token,
          voterKey: identity.publicKeyBytes,
          changeId: 'change-1',
          approve: true,
        ),
        isTrue,
      );
    });

    test('refuses a token replayed across a different changeId', () async {
      final token = (await mint(changeId: 'change-A'))!;
      expect(
        await biometric.consumeVoteAttestation(
          token,
          voterKey: identity.publicKeyBytes,
          changeId: 'change-B',
          approve: true,
        ),
        isFalse,
      );
    });

    test('refuses a token bound to the opposite choice', () async {
      final token = (await mint(approve: true))!;
      expect(
        await biometric.consumeVoteAttestation(
          token,
          voterKey: identity.publicKeyBytes,
          changeId: 'change-1',
          approve: false,
        ),
        isFalse,
      );
    });

    test('refuses a token bound to a different voter key', () async {
      final token = (await mint())!;
      expect(
        await biometric.consumeVoteAttestation(
          token,
          voterKey: Uint8List.fromList(List.filled(32, 0xEE)),
          changeId: 'change-1',
          approve: true,
        ),
        isFalse,
      );
    });

    test('single-use: a consumed token can never attest again', () async {
      final token = (await mint())!;
      expect(
        await biometric.consumeVoteAttestation(
          token,
          voterKey: identity.publicKeyBytes,
          changeId: 'change-1',
          approve: true,
        ),
        isTrue,
      );
      expect(
        await biometric.consumeVoteAttestation(
          token,
          voterKey: identity.publicKeyBytes,
          changeId: 'change-1',
          approve: true,
        ),
        isFalse,
      );
    });

    test('refuses forged, malformed, stale and future-dated tokens',
        () async {
      // A deterministic-keyed service lets us craft valid-format tokens.
      final crafted = BiometricService(
          null, const Duration(minutes: 2), attKey);
      final now = DateTime.now().millisecondsSinceEpoch;
      final voter = identity.publicKeyBytes;

      // Forged MAC.
      expect(
        await crafted.consumeVoteAttestation(
          'va1.$now.deadbeef.${'0' * 64}',
          voterKey: voter,
          changeId: 'c',
          approve: true,
        ),
        isFalse,
      );

      // Malformed (no prefix / wrong shape).
      expect(
        await crafted.consumeVoteAttestation('garbage',
            voterKey: voter, changeId: 'c', approve: true),
        isFalse,
      );
      expect(
        await crafted.consumeVoteAttestation('va1.$now.nonce',
            voterKey: voter, changeId: 'c', approve: true),
        isFalse,
      );

      // Stale: valid MAC, expired issuance.
      final stale = now - const Duration(minutes: 5).inMilliseconds;
      final staleToken =
          'va1.$stale.nn.${_mac(attKey, voter, 'c', true, stale, 'nn')}';
      expect(
        await crafted.consumeVoteAttestation(staleToken,
            voterKey: voter, changeId: 'c', approve: true),
        isFalse,
      );

      // Future-dated: valid MAC, pre-minted claim.
      final future = now + const Duration(minutes: 1).inMilliseconds;
      final futureToken =
          'va1.$future.nn.${_mac(attKey, voter, 'c', true, future, 'nn')}';
      expect(
        await crafted.consumeVoteAttestation(futureToken,
            voterKey: voter, changeId: 'c', approve: true),
        isFalse,
      );

      // Sanity: a correctly minted recent token on the same key verifies.
      final good =
          'va1.$now.nn.${_mac(attKey, voter, 'c', true, now, 'nn')}';
      expect(
        await crafted.consumeVoteAttestation(good,
            voterKey: voter, changeId: 'c', approve: true),
        isTrue,
      );
    });
  });

  group('ConsensusService.castVote per-vote binding', () {
    test('a verified token mints an isHuman ballot pinned to the token',
        () async {
      final svc = consensus(verifier: biometric.consumeVoteAttestation);
      final req = await propose(svc);
      final token = (await biometric.attestVoteIntent(
        voterKey: identity.publicKeyBytes,
        changeId: req.id,
        approve: true,
      ))!;

      final vote = await svc.castVote(
        requestId: req.id,
        approve: true,
        reputation: 100,
        daysActive: 365,
        isHuman: true,
        humanAttestationToken: token,
      );

      expect(vote, isNotNull);
      expect(vote!.isHuman, isTrue);
      expect(vote.weightAttested, isTrue);
      expect(vote.humanAttestation, equals(token));
      // Human factor applied: weight uses the 1.0 human multiplier.
      expect(
        vote.weight,
        closeTo(
          VoteWeightCalculator.calculateWeight(
            reputationScore: ledger.totalReputation,
            daysActive: DateTime.now()
                .difference(DateTime(2025, 1, 1))
                .inDays,
            isHuman: true,
          ),
          0.0001,
        ),
      );
    });

    test('a token minted for a different change refuses the cast',
        () async {
      final svc = consensus(verifier: biometric.consumeVoteAttestation);
      final req = await propose(svc, cid: 'bafy_a');
      final other = await propose(svc, cid: 'bafy_b');
      final token = (await biometric.attestVoteIntent(
        voterKey: identity.publicKeyBytes,
        changeId: other.id,
        approve: true,
      ))!;

      final vote = await svc.castVote(
        requestId: req.id,
        approve: true,
        reputation: 100,
        daysActive: 365,
        isHuman: true,
        humanAttestationToken: token,
      );
      expect(vote, isNull);
      expect(req.votes, isEmpty);
    });

    test('a token minted for the opposite choice refuses the cast',
        () async {
      final svc = consensus(verifier: biometric.consumeVoteAttestation);
      final req = await propose(svc);
      final token = (await biometric.attestVoteIntent(
        voterKey: identity.publicKeyBytes,
        changeId: req.id,
        approve: false, // token commits to REJECT
      ))!;

      final vote = await svc.castVote(
        requestId: req.id,
        approve: true, // ballot claims APPROVE
        reputation: 100,
        daysActive: 365,
        isHuman: true,
        humanAttestationToken: token,
      );
      expect(vote, isNull);
      expect(req.votes, isEmpty);
    });

    test('a forged token refuses the cast (no silent AI-priced ballot)',
        () async {
      final svc = consensus(verifier: biometric.consumeVoteAttestation);
      final req = await propose(svc);
      final now = DateTime.now().millisecondsSinceEpoch;
      final vote = await svc.castVote(
        requestId: req.id,
        approve: true,
        reputation: 100,
        daysActive: 365,
        isHuman: true,
        humanAttestationToken: 'va1.$now.nn.${'f' * 64}',
      );
      expect(vote, isNull);
      expect(req.votes, isEmpty);
    });

    test('a presented token with no verifier wired refuses the cast',
        () async {
      final svc = consensus(); // no verifier
      final req = await propose(svc);
      final vote = await svc.castVote(
        requestId: req.id,
        approve: true,
        reputation: 100,
        daysActive: 365,
        isHuman: true,
        humanAttestationToken: 'va1.0.nn.${'0' * 64}',
      );
      expect(vote, isNull);
    });

    test('clock fallback still works when no token is supplied '
        '(compat path — temporal binding only)', () async {
      final svc = ConsensusService(
        identity,
        ledger,
        humanAttestationClock: () => biometric.lastAuthenticatedAt,
        voteAttestationVerifier: biometric.consumeVoteAttestation,
      );
      final req = await propose(svc);
      // A genuine prompt feeds the clock.
      await biometric.attestVoteIntent(
        voterKey: identity.publicKeyBytes,
        changeId: req.id,
        approve: true,
      );

      final vote = await svc.castVote(
        requestId: req.id,
        approve: true,
        reputation: 100,
        daysActive: 365,
        isHuman: true,
        // no token → temporal window evidence
      );
      expect(vote, isNotNull);
      expect(vote!.isHuman, isTrue);
      // Temporal-path ballots carry no per-vote pin.
      expect(vote.humanAttestation, isNull);
    });

    test('no token + no biometric evidence → isHuman fails closed',
        () async {
      final svc = consensus(verifier: biometric.consumeVoteAttestation);
      final req = await propose(svc);
      final vote = await svc.castVote(
        requestId: req.id,
        approve: true,
        reputation: 100,
        daysActive: 365,
        isHuman: true, // bare claim
      );
      expect(vote, isNotNull);
      expect(vote!.isHuman, isFalse);
      expect(req.humanApprovalCount, 0);
    });
  });
}
