import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart' show AppDatabase, databaseProvider;
import '../logic/honor_system.dart';
import 'agent/beacon_models.dart';
import 'credits/credit_service.dart';
import 'credits/work_receipt.dart';
import 'identity_service.dart';

final proofOfRetrievabilityServiceProvider =
    Provider((ref) => ProofOfRetrievabilityService(ref));

class PoRChallenge {
  final String challengeId;
  final String cid;
  final int chunkIndex;
  final Uint8List nonce;
  final DateTime timestamp;

  /// Ed25519 public key (hex) of the verifier that issued this challenge.
  /// Nullable for legacy challenges issued before verifier-signed receipts;
  /// the issuer's identity key is substituted at issuance time.
  final String? challengerPubkey;

  PoRChallenge({
    required this.challengeId,
    required this.cid,
    required this.chunkIndex,
    required this.nonce,
    required this.timestamp,
    this.challengerPubkey,
  });

  Map<String, dynamic> toJson() => {
        'challengeId': challengeId,
        'cid': cid,
        'chunkIndex': chunkIndex,
        'nonce': nonce.toList(),
        'timestamp': timestamp.toIso8601String(),
        'challengerPubkey': challengerPubkey,
      };
}

class PoRProof {
  final String challengeId;
  final String tag;
  final DateTime timestamp;

  PoRProof({
    required this.challengeId,
    required this.tag,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'challengeId': challengeId,
        'tag': tag,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Outcome of [ProofOfRetrievabilityService.verifyAndIssueReceipt]: on a
/// valid proof, the verifier-side [WorkReceipt] that was issued, persisted
/// and claimed. `valid == false` means the proof was rejected (unknown or
/// expired challenge, tag mismatch) and no receipt exists.
class PoRVerificationResult {
  final bool valid;
  final WorkReceipt? receipt;

  const PoRVerificationResult._(this.valid, this.receipt);

  const PoRVerificationResult.rejected() : this._(false, null);
  const PoRVerificationResult.verified(WorkReceipt receipt)
      : this._(true, receipt);
}

/// Proof-of-Retrievability challenge/response engine (ALX-010).
///
/// Verification is now *verifier-side issuance*: a valid proof produces a
/// verifier-signed [WorkReceipt]. The receipt's value is claimed locally
/// ONLY when the local node is the prover of record (legacy self-checks
/// always prove local bytes); a receipt naming a foreign prover is
/// persisted UNSPENT as that prover's claim instrument - minting it
/// locally would pay the verifier for someone else's work.
///
/// Local mints are always unattested (1.0x rarity): attestation requires a
/// signature by a verifier foreign to the claiming node, and this service
/// can only ever sign as the local identity key.
class ProofOfRetrievabilityService {
  final Ref _ref;
  final Map<String, PoRChallenge> _pendingChallenges = {};

  /// Injectable clock - production uses [DateTime.now]; tests supply a
  /// controllable source so challenge-expiry purging is deterministic.
  final DateTime Function() _now;

  static const Duration challengeTtl = Duration(minutes: 5);

  /// Hard cap on retained pending challenges (REV4 review / Safety 5):
  /// an unbounded map is a memory-DoS via challenge spam. The map is
  /// insertion-ordered, so eviction removes the oldest entry.
  static const int _maxPendingChallenges = 256;

  /// Receipts are claimable for 24h after issuance.
  static const Duration receiptTtl = Duration(hours: 24);

  ProofOfRetrievabilityService(this._ref, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// Legacy challenge factory - signature preserved for callers that
  /// predate verifier identity (UI integrity self-checks, security
  /// overview). Delegates to [issueChallenge] with no challenger key.
  PoRChallenge createChallenge({
    required String cid,
    required int totalChunks,
  }) {
    return issueChallenge(cid: cid, totalChunks: totalChunks);
  }

  /// Issues a fresh challenge on behalf of a verifier identified by
  /// [challengerPubkey] (Ed25519 pubkey hex, e.g. the local agent key).
  PoRChallenge issueChallenge({
    required String cid,
    required int totalChunks,
    String? challengerPubkey,
  }) {
    if (totalChunks <= 0) throw ArgumentError('totalChunks must be positive');
    final rnd = Random.secure();
    final chunkIndex = rnd.nextInt(totalChunks);
    final nonce =
        Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
    final challengeId = sha256.convert(nonce).toString().substring(0, 16);

    final challenge = PoRChallenge(
      challengeId: challengeId,
      cid: cid,
      chunkIndex: chunkIndex,
      nonce: nonce,
      timestamp: _now(),
      challengerPubkey: challengerPubkey,
    );

    // Bound the map before inserting (REV4 review / Safety 5): purge
    // expired entries first - they are dead weight and cheaper to drop
    // than a live challenge - then, if still at capacity, evict the
    // OLDEST entry (the map is insertion-ordered, so the first key is
    // the oldest).
    final now = _now();
    _pendingChallenges
        .removeWhere((_, c) => now.difference(c.timestamp) > challengeTtl);
    while (_pendingChallenges.length >= _maxPendingChallenges) {
      _pendingChallenges.remove(_pendingChallenges.keys.first);
    }
    _pendingChallenges[challengeId] = challenge;
    return challenge;
  }

  /// Number of retained pending challenges - exposed for tests
  /// exercising the [_maxPendingChallenges] bound.
  @visibleForTesting
  int get pendingChallengeCount => _pendingChallenges.length;

  /// Looks up an unexpired pending challenge by ID. Used by the MCP server to
  /// reject proofs against challenges this node never issued.
  PoRChallenge? pendingChallenge(String challengeId) {
    final challenge = _pendingChallenges[challengeId];
    if (challenge == null) return null;
    if (_now().difference(challenge.timestamp) > challengeTtl) {
      _pendingChallenges.remove(challengeId);
      return null;
    }
    return challenge;
  }

  PoRProof generateProof({
    required PoRChallenge challenge,
    required Uint8List chunkData,
  }) {
    final hmac = Hmac(sha256, challenge.nonce);
    final digest = hmac.convert(chunkData);
    return PoRProof(
      challengeId: challenge.challengeId,
      tag: digest.toString(),
      timestamp: DateTime.now(),
    );
  }

  /// Synchronous verification entry point (legacy callers: integrity
  /// self-check, security overview). The tag check, honor record and the
  /// local 1.0x storage award all run inline - callers observe the new
  /// balance when this returns `true`. Receipt signing and persistence
  /// finish asynchronously; the issued receipt is retrievable from the
  /// database or via [verifyAndIssueReceipt].
  bool verifyProof({
    required PoRProof proof,
    required Uint8List expectedChunkData,
    required String proverPeerId,
  }) {
    final challenge = _validateProof(proof, expectedChunkData);
    if (challenge == null) return false;

    // No honor ballot here: this path always proves locally-held bytes, so
    // any recorded vote would be a self-attestation — inflating the
    // community-trust tally with a validator that cannot vouch for itself.

    // Legacy callers supply no prover pubkey and always prove locally-held
    // bytes, so the local node is the prover of record: mint the self-check
    // award synchronously. The mint is ALWAYS unattested (1.0x) - a
    // locally-signed receipt naming a foreign peer id can never carry
    // attestation weight for a local claim. The receipt artifact (which
    // records the claim as spent) is built and persisted asynchronously.
    _mintLocalStorageReward(challenge, expectedChunkData.length);
    unawaited(_issueReceipt(
      challenge: challenge,
      proof: proof,
      expectedChunkData: expectedChunkData,
      proverPeerId: proverPeerId,
      proverPubkey: null,
      localMintSettled: true,
    ));
    return true;
  }

  /// Verifier-side issuance path (ALX-010/P1). On a valid proof, builds a
  /// [WorkReceipt] naming the challenge's verifier and the prover's pubkey,
  /// signs it with the verifier's identity when that identity matches the
  /// recorded verifier key, and persists it via `insertWorkReceipt`.
  ///
  /// The receipt's value is claimed through the credit ledger ONLY when
  /// the local node is the prover of record ([proverPubkey] absent - the
  /// proof ran over local bytes - or equal to the node identity key). A
  /// receipt naming a foreign prover is persisted UNSPENT: it is the
  /// prover's claim instrument and mints nothing here.
  ///
  /// Returns [PoRVerificationResult] carrying the issued receipt - the
  /// artifact a forked client cannot forge for a foreign verifier.
  Future<PoRVerificationResult> verifyAndIssueReceipt({
    required PoRProof proof,
    required Uint8List expectedChunkData,
    required String proverPeerId,
    String? proverPubkey,
  }) async {
    final challenge = _validateProof(proof, expectedChunkData);
    if (challenge == null) return const PoRVerificationResult.rejected();

    // Honor the prover ONLY when it is verifiably foreign: a proof over
    // local bytes (no prover key, or the node's own key) is a
    // self-attestation and must not mint community trust.
    final effectiveProver = proverPubkey ?? proverPeerId;
    if (proverPubkey != null && !await _isLocalKey(effectiveProver)) {
      _recordHonor(effectiveProver, challenge);
    }

    final receipt = await _issueReceipt(
      challenge: challenge,
      proof: proof,
      expectedChunkData: expectedChunkData,
      proverPeerId: proverPeerId,
      proverPubkey: proverPubkey,
    );
    return PoRVerificationResult.verified(receipt);
  }

  /// Shared synchronous check: pending, unexpired challenge whose stored
  /// nonce yields the submitted tag. Consumes the challenge either way.
  PoRChallenge? _validateProof(PoRProof proof, Uint8List expectedChunkData) {
    final challenge = _pendingChallenges[proof.challengeId];
    if (challenge == null) return null;

    if (_now().difference(challenge.timestamp) > challengeTtl) {
      _pendingChallenges.remove(proof.challengeId);
      return null;
    }

    final hmac = Hmac(sha256, challenge.nonce);
    final expectedTag = hmac.convert(expectedChunkData).toString();
    _pendingChallenges.remove(proof.challengeId);

    return expectedTag == proof.tag ? challenge : null;
  }

  /// True when [key] canonically names the local node identity (or when no
  /// identity is available and the caller supplied no distinguishing key).
  /// Case/padding variants still count as local - [WorkReceipt.samePubkey].
  Future<bool> _isLocalKey(String key) async {
    try {
      final identity = await _ref.read(identityServiceProvider).getIdentity();
      if (identity == null) return false;
      return WorkReceipt.samePubkey(key, bytesToHex(identity.publicKey));
    } catch (_) {
      return false;
    }
  }

  void _recordHonor(String proverPeerId, PoRChallenge challenge) {
    try {
      final honorSystem = _ref.read(honorSystemProvider);
      honorSystem.recordVote(
        validatorId: proverPeerId,
        targetCid: challenge.cid,
        score: 1,
        reputation: 20,
      );
    } catch (_) {
      // Honor recording must never fail verification.
    }
  }

  /// Synchronous local storage-reward mint for proofs over locally-held
  /// bytes. Always unattested (1.0x rarity) - a locally-verified,
  /// locally-signed proof can never carry foreign attestation weight.
  ///
  /// The mint is deferred behind [CreditService.ready] only while
  /// hydration is still in flight: a verification landing inside that
  /// window would otherwise be silently refused (returns 0.0) and the
  /// earned reward lost. Once hydrated the award stays synchronous -
  /// the mint has landed when verifyProof returns.
  void _mintLocalStorageReward(PoRChallenge challenge, int sizeBytes) {
    try {
      final credits = _ref.read(creditServiceProvider);
      void mint() => credits.awardStorageCredits(
            sizeBytes: sizeBytes,
            peerCount: 2,
            porPassed: true,
            cid: challenge.cid,
          );
      if (credits.isHydrated) {
        mint();
      } else {
        unawaited(credits.ready.then((_) {
          // Best-effort: if the service was disposed while hydration
          // resolved (scope restart, teardown) the mint drops exactly as
          // the pre-deferral refusal would have dropped it - the award
          // path notifies listeners on a possibly-disposed PoCHService.
          try {
            mint();
          } catch (_) {}
        }));
      }
    } catch (_) {
      // Safe fallback in isolated mock test environments
    }
  }

  /// Builds, optionally signs, persists and - only when the local node is
  /// the prover of record - claims the work receipt for a verified proof.
  /// Never throws - a persistence or signing failure must not invalidate
  /// an honestly verified proof.
  ///
  /// [localMintSettled] marks the synchronous [verifyProof] path, which
  /// already ran the local 1.0x mint inline; the receipt is then only
  /// persisted and flagged spent.
  Future<WorkReceipt> _issueReceipt({
    required PoRChallenge challenge,
    required PoRProof proof,
    required Uint8List expectedChunkData,
    required String proverPeerId,
    required String? proverPubkey,
    bool localMintSettled = false,
  }) async {
    // Resolve the local (verifier-side) identity, if any.
    AlexandriaIdentity? identity;
    String? localPubkeyHex;
    try {
      identity = await _ref.read(identityServiceProvider).getIdentity();
      if (identity != null) localPubkeyHex = bytesToHex(identity.publicKey);
    } catch (_) {
      // No secure storage in tests/headless runs - receipts stay unsigned.
    }

    // When no prover key is supplied the proof ran over local bytes - name
    // the REAL local key as prover rather than whatever caller-supplied
    // label arrived in proverPeerId, so the signed receipt never asserts a
    // fabricated prover identity.
    final effectiveProver = proverPubkey ?? localPubkeyHex ?? proverPeerId;
    final verifierPubkey = challenge.challengerPubkey ?? localPubkeyHex ?? '';

    // The receipt asserts exactly the work that was proven - the verified
    // chunk bytes alone, never an extrapolation over sibling chunks.
    final sizeBytes = expectedChunkData.length;
    const peerCount = 2;

    // The local node may claim this receipt's value only when it IS the
    // prover of record: legacy callers supply no prover key (the proof is
    // always computed over local bytes), or the supplied key IS the node
    // identity key - compared CANONICALLY via WorkReceipt.samePubkey, so
    // a case-variant or space-padded prover_pubkey spelling the local key
    // (reachable via the MCP tool) still mints the local reward rather
    // than stranding it as an unclaimable foreign-prover instrument. A
    // receipt naming a foreign prover is persisted UNSPENT as that
    // prover's claim instrument - minting it locally would pay the
    // verifier for someone else's work and burn the artifact.
    final localIsProver = proverPubkey == null ||
        (localPubkeyHex != null &&
            WorkReceipt.samePubkey(effectiveProver, localPubkeyHex));

    // Sign the canonical body - but only ever AS the recorded verifier
    // key; signing under a different key would mint an unverifiable
    // artifact. The compare is canonical for the same reason: a
    // case-variant challengerPubkey spelling the local identity is still
    // signable - string equality would silently strand the receipt
    // unsigned.
    final issuedAt = DateTime.now();
    var receipt = _draftReceipt(
      challenge: challenge,
      proof: proof,
      sizeBytes: sizeBytes,
      peerCount: peerCount,
      proverPubkey: effectiveProver,
      verifierPubkey: verifierPubkey,
      expectedChunkData: expectedChunkData,
      issuedAt: issuedAt,
    );
    final canSign = identity != null &&
        localPubkeyHex != null &&
        WorkReceipt.samePubkey(localPubkeyHex, verifierPubkey);
    if (canSign) {
      try {
        // The signature sits outside the canonical body, so attaching it
        // leaves the signed bytes (and the receipt id) untouched.
        final sigBytes = await _ref
            .read(identityServiceProvider)
            .sign(receipt.signingPayload);
        receipt = receipt.withVerifierSig(base64Encode(sigBytes));
      } catch (_) {
        // Signing failed - the receipt stays unsigned and unattested.
      }
    }

    // Attestation weight requires a signature by a verifier FOREIGN to the
    // claiming node (`isVerifierSigned && verifier != local && !selfIssued`).
    // This path can only ever sign as the local key, so a locally-signed
    // receipt can NEVER carry attestation weight for a local mint - the
    // local claim below always lands at the flat 1.0x rarity weight, and
    // the rarity flag itself is sealed: `awardStorageCredits` no longer
    // accepts a caller-supplied attestation (see CreditService).
    // Persist the artifact; tolerate absence of a database in pure tests.
    AppDatabase? db;
    try {
      final database = _ref.read(databaseProvider);
      await database.insertWorkReceipt(receipt.toDbMap());
      db = database;
    } catch (_) {
      db = null;
    }

    // Local claim: only when the local node proved the work itself, through
    // the normal capped mint at unattested weight. CreditService's
    // claimVerifiedReceipt is the seam for foreign-verifier receipts; a
    // receipt we signed ourselves is never eligible for that weight here.
    var claimed = localMintSettled;
    if (!claimed && localIsProver) {
      try {
        final credits = _ref.read(creditServiceProvider);
        // A receipt issued inside the hydration window would mint 0.0 -
        // await readiness so the earned reward actually lands.
        await credits.ready;
        credits.awardStorageCredits(
          sizeBytes: sizeBytes,
          peerCount: peerCount,
          porPassed: true,
          cid: challenge.cid,
        );
      } catch (_) {
        // Safe fallback in isolated mock test environments
      }
      claimed = true;
    }

    // A locally-claimed receipt is spent - it must never be replayed
    // through the claim seam. A foreign-prover receipt stays UNSPENT: the
    // value belongs to whoever holds the prover key.
    if (claimed) {
      var spentPersisted = db == null;
      if (db != null) {
        try {
          // Atomic requirement, now implemented: the receipt already
          // exists, so route through the conditional UPDATE WHERE
          // receipt_id=? AND spent=0 checked by rows-affected - a single
          // atomic op. Losing the CAS (false) means another claim landed
          // first; the artifact then stays reported as spent either way.
          spentPersisted = await db.claimReceiptAtomically(receipt.receiptId) ||
              // A concurrent claim may have already consumed it -
              // the row IS spent in that case, so report spent.
              (await db.getWorkReceipt(receipt.receiptId))?['spent'] == true;
        } catch (_) {}
      }
      // Report the state actually persisted (or the consumption itself
      // when nothing was persisted) - not the pre-claim draft.
      if (spentPersisted) receipt = receipt.markSpent();
    }

    return receipt;
  }

  WorkReceipt _draftReceipt({
    required PoRChallenge challenge,
    required PoRProof proof,
    required int sizeBytes,
    required int peerCount,
    required String proverPubkey,
    required String verifierPubkey,
    required Uint8List expectedChunkData,
    required DateTime issuedAt,
  }) {
    // The storage-reward value this receipt mints through the capped path
    // - recorded on the receipt so a forked client's inflated
    // self-declaration is worthless. Locally-issued receipts are always
    // drafted at unattested (1.0x) rarity weight: attested rarity can only
    // be baked into a receipt by a FOREIGN verifier, never self-declared,
    // and the attestation flag is sealed to tests - production callers
    // cannot pass it (see CreditService.rarityWeightFor).
    final rarityWeight = CreditService.rarityWeightFor(peerCount);
    final mbSize = sizeBytes / (1024 * 1024);
    final amount = (mbSize * 0.1 * rarityWeight).clamp(0.1, 50.0);

    return WorkReceipt.issue(
      workType: 'storage',
      proverPubkey: proverPubkey,
      verifierPubkey: verifierPubkey,
      cid: challenge.cid,
      chunkIndices: [challenge.chunkIndex],
      challengeNonce: bytesToHex(challenge.nonce),
      responseTag: proof.tag,
      workUnits: sizeBytes.toDouble(),
      amount: amount,
      epoch: WorkReceipt.epochFor(issuedAt),
      expiresAt: issuedAt.add(receiptTtl).millisecondsSinceEpoch,
      evidenceHash: sha256.convert(expectedChunkData).toString(),
    );
  }
}
