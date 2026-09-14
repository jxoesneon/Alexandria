import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'beacon_models.dart';

/// Ed25519 verification callback, injected so [EscrowAttestation] stays
/// crypto-agnostic. Same shape as `ReceiptSignatureVerifier` in
/// work_receipt.dart: the canonical message bytes, the raw 64-byte
/// signature, and the attestor's public key (encoding is the verifier's
/// concern — hex by codebase convention).
typedef EscrowAttestationVerifier = Future<bool> Function(
  Uint8List message,
  Uint8List signature,
  String publicKey,
);

/// Cryptographic evidence that a bounty's escrow was attested by a
/// FOREIGN attestor (ALX-011 / Review A3).
///
/// ONLY constructible via [EscrowAttestation.verify] — the private
/// constructor means no code path can mint an "attestation" without a
/// real Ed25519 signature check. This is enforcement by construction,
/// not a data bag: it replaces the former caller-asserted
/// `escrowAttested` bool on `MoltbookService.ingestBountyAnnouncement`,
/// which was the same class of forgeable input as the announcer's
/// `funded` flag itself.
///
/// Trust rules (mirroring the WorkReceipt attestation rules):
///  * The signature must verify over the canonical domain preimage
///    ([signingPreimage]) against [attestorPubkey].
///  * The attestation must BIND the exact bounty — id, cid, and
///    escrowed amount ([bindsBounty]).
///  * It must be UNEXPIRED ([isExpired]).
///  * The attestor must be FOREIGN to the poster — a self-vouch is no
///    attestation ([isSelfIssuedFor], same rule as
///    `WorkReceipt.isSelfIssued`).
///
/// NOTE: signature validity alone confers NO trust — anyone can mint a
/// keypair and sign. Whether a valid attestation admits anything is the
/// caller's trust-root decision (see `trustedAttestors` on
/// `MoltbookService.ingestBountyAnnouncement`, which also bars the
/// node's OWN key from attesting).
class EscrowAttestation {
  /// Hex-encoded Ed25519 pubkey of the foreign attestor that vouched
  /// for the escrow.
  final String attestorPubkey;

  /// Bounty id this attestation binds to.
  final String bountyId;

  /// Content CID the escrowed bounty covers.
  final String cid;

  /// Escrowed amount in integer milli-units (`credits * 1000`, rounded)
  /// — the same JCS discipline as `WorkReceipt.amountMilli`, so the
  /// signed preimage is bit-identical across platforms (a Dart `25.0`
  /// and a JavaScript `25` cannot diverge the preimage).
  final int amountMilli;

  /// Expiry, epoch milliseconds. Expired attestations never count.
  final int expiresAt;

  /// Base64 Ed25519 signature over the canonical domain preimage
  /// ([signingPreimage]).
  final String signature;

  const EscrowAttestation._({
    required this.attestorPubkey,
    required this.bountyId,
    required this.cid,
    required this.amountMilli,
    required this.expiresAt,
    required this.signature,
  });

  /// Canonical signed statement — the exact byte preimage the attestor
  /// signs and verifiers recompute:
  /// `utf8('alexandria:escrow:v2:' + canonicalJson({amountMilli,
  ///   bountyId, cid, expiresAt}))`
  ///
  /// v2 replaces the v1 colon-joined preimage, which was NON-INJECTIVE:
  /// `('x:y','z')` and `('x','y:z')` concatenated to identical bytes, so
  /// a signature minted for one (id, cid) pair re-verified for the
  /// other. Canonical JSON with sorted keys ([toCanonicalJson]) makes
  /// field boundaries structural — no choice of string field values can
  /// ever collide two distinct field tuples onto one preimage. The
  /// `alexandria:escrow:v2:` domain prefix additionally prevents
  /// preimage collisions with Beacon envelopes, work receipts, or any
  /// other signed artifact in the system. There are zero v1 producers,
  /// so the bump is a clean break.
  static Uint8List signingPreimage({
    required String bountyId,
    required String cid,
    required int amountMilli,
    required int expiresAt,
  }) =>
      Uint8List.fromList(
        utf8.encode(
          'alexandria:escrow:v2:${toCanonicalJson(<String, dynamic>{
            'amountMilli': amountMilli,
            'bountyId': bountyId,
            'cid': cid,
            'expiresAt': expiresAt,
          })}',
        ),
      );

  /// Constructs an attestation ONLY if the Ed25519 signature over the
  /// domain preimage verifies against [attestorPubkey] via [verifyFn].
  ///
  /// Returns null on ANY failure: malformed/empty fields, non-positive
  /// amount, malformed or wrong-length signature, invalid signature, a
  /// throwing [verifyFn], or an already-expired attestation (relative
  /// to [now], default: real now). Callers can never obtain a
  /// "verified" attestation that did not actually verify — and
  /// `expiresAt` stays bound inside the signed preimage, so a poster
  /// cannot extend it post-hoc.
  static Future<EscrowAttestation?> verify({
    required String attestorPubkey,
    required String bountyId,
    required String cid,
    required int amountMilli,
    required int expiresAt,
    required String signature,
    required EscrowAttestationVerifier verifyFn,
    DateTime? now,
  }) async {
    try {
      if (attestorPubkey.isEmpty || bountyId.isEmpty || cid.isEmpty) {
        return null;
      }
      // A zero/negative escrow can never back a claimable bounty
      // (postPreservationBounty already rejects non-positive offers).
      // The 2^53 ceiling keeps amountMilli inside the exact-integer
      // range every consumer can represent (JS MAX_SAFE_INTEGER domain),
      // so a preimage can never attest an amount that silently
      // round-trips to a different value on another platform.
      if (amountMilli <= 0 || amountMilli > 9007199254740992) {
        return null;
      }
      final sigBytes = base64Decode(signature);
      if (sigBytes.length != 64) return null;
      final ok = await verifyFn(
        signingPreimage(
          bountyId: bountyId,
          cid: cid,
          amountMilli: amountMilli,
          expiresAt: expiresAt,
        ),
        sigBytes,
        attestorPubkey,
      );
      if (!ok) return null;
      final attestation = EscrowAttestation._(
        attestorPubkey: attestorPubkey,
        bountyId: bountyId,
        cid: cid,
        amountMilli: amountMilli,
        expiresAt: expiresAt,
        signature: signature,
      );
      // Dead on arrival: an already-expired attestation attests nothing.
      if (attestation.isExpired(now)) return null;
      return attestation;
    } catch (_) {
      return null;
    }
  }

  /// Ready-made [EscrowAttestationVerifier] for hex-encoded Ed25519
  /// pubkeys (the codebase-wide convention), built on
  /// package:cryptography. Transports/tests may inject any verifier
  /// with the same shape instead.
  static Future<bool> verifyEd25519(
    Uint8List message,
    Uint8List signature,
    String publicKeyHex,
  ) async {
    try {
      final pkBytes = hexToBytes(publicKeyHex);
      if (pkBytes.length != 32) return false;
      final publicKey =
          SimplePublicKey(pkBytes, type: KeyPairType.ed25519);
      return await Ed25519().verify(
        message,
        signature: Signature(signature, publicKey: publicKey),
      );
    } catch (_) {
      return false;
    }
  }

  /// Largest |milli| product [bindsBounty] will attempt to round — the
  /// same 2^53 ceiling [verify] enforces on [amountMilli], so a product
  /// outside this bound could never equal a verified amount anyway.
  static const double _maxMilliProduct = 9007199254740992.0;

  /// True when this attestation cryptographically binds to [bounty]'s
  /// identifying fields: same id, same cid, same escrowed amount. An
  /// attestation minted for a different bounty (or a different amount)
  /// does not bind — so attestations can never be replayed across
  /// announcements.
  ///
  /// The guard is on the PRODUCT, not just
  /// [PreservationBounty.offeredCredits]: a finite offeredCredits of
  /// roughly 1.8e305 or more overflows to Infinity when milli-scaled,
  /// and `Infinity.round()` throws. Through `ingestBountyAnnouncement`
  /// that throw is a persistent crash primitive — the dedup-upgrade
  /// path would re-throw on every later attested re-announcement of the
  /// poisoned id. Ingest must fail closed, never crash (H2).
  bool bindsBounty(PreservationBounty bounty) {
    final milli = bounty.offeredCredits * 1000;
    if (!milli.isFinite || milli.abs() > _maxMilliProduct) return false;
    return bountyId == bounty.id &&
        cid == bounty.cid &&
        amountMilli == milli.round();
  }

  /// True when the attestor IS the bounty's poster — a self-vouch that
  /// carries zero attestation weight, exactly like a self-issued
  /// WorkReceipt (`prover == verifier`). Attestation means a FOREIGN
  /// party vouched; a poster signing its own escrow claim is the same
  /// forgeable self-declaration as the `funded` flag it replaces.
  ///
  /// [PreservationBounty] carries only the poster's derived
  /// `originAgentId` (`bcn_<first 12 pubkey hex>`), so this compares the
  /// attestor's derived agent id against it. A prefix collision can only
  /// ever produce a FALSE self-issued verdict — fail-safe, since it
  /// rejects rather than admits.
  ///
  /// An undecodable/wrong-length [attestorPubkey] cannot be shown to be
  /// foreign, so it conservatively counts as self-issued (no weight).
  ///
  /// The agent-id comparison is canonical (trim + case-fold): agent ids
  /// are `bcn_<hex>` and hex is case-insensitive, so a poster claiming
  /// `origin_agent_id` as an UPPERCASE or padded spelling of the
  /// attestor's derived id is still the SAME claimed poster — raw `==`
  /// would let exactly that spelling launder a self-vouch (H1 class).
  /// Over-matching only ever produces MORE self-issued verdicts, which
  /// is the fail-safe direction: it rejects rather than admits.
  bool isSelfIssuedFor(PreservationBounty bounty) {
    try {
      final pkBytes = hexToBytes(attestorPubkey);
      if (pkBytes.length != 32) return true;
      return BeaconEnvelope.deriveAgentId(pkBytes).toLowerCase() ==
          bounty.originAgentId.trim().toLowerCase();
    } catch (_) {
      return true;
    }
  }

  /// True when [expiresAt] has passed relative to [now] (default: now).
  bool isExpired([DateTime? now]) =>
      (now ?? DateTime.now()).millisecondsSinceEpoch > expiresAt;
}
