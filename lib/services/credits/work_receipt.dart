import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Ed25519 verification callback, injected so [WorkReceipt] stays
/// crypto-agnostic. Receives the canonical message bytes, the raw 64-byte
/// signature, and the verifier's public key (encoding is the verifier's
/// concern — hex or base58), and resolves to whether the signature is valid.
typedef ReceiptSignatureVerifier = Future<bool> Function(
  Uint8List message,
  Uint8List signature,
  String publicKey,
);

/// A verifier-signed record of work performed by a prover (ALX-010 / P1).
///
/// The receipt — not a self-declaration — is what entitles a prover to mint
/// Archival Credits. [receiptId] is the sha256 of the canonical (sorted-key)
/// JSON body; [verifierSig] is a base64 Ed25519 signature over those same
/// canonical bytes. A forked client can mint a receipt claiming anything,
/// but only receipts carrying a *foreign* verifier's valid signature count
/// as attested value; self-signed receipts (prover == verifier) carry zero
/// egress weight.
class WorkReceipt {
  /// sha256 of [canonicalJson] — the receipt's unique, content-derived id.
  final String receiptId;

  /// Work category: 'storage' | 'compute' | 'verification'.
  final String workType;

  /// Public key of the node that performed the work (hex/base58 Ed25519).
  final String proverPubkey;

  /// Public key of the node that issued and signed the receipt.
  final String verifierPubkey;

  /// Content the work applies to (PoR: the challenged CID).
  final String? cid;

  /// Chunk indexes covered by this receipt.
  final List<int> chunkIndices;

  /// Hex-encoded challenge nonce the proof answered.
  final String challengeNonce;

  /// Hex-encoded response tag (e.g. HMAC-SHA256) submitted by the prover.
  final String responseTag;

  /// Amount of work proven, in the work type's natural unit
  /// (storage: bytes proven retrievable).
  final double workUnits;

  /// Credit value this receipt entitles the prover to claim.
  final double amount;

  /// Issuance epoch — UTC day 'YYYY-MM-DD'.
  final String epoch;

  /// Expiry, epoch milliseconds. Stale receipts cannot be claimed.
  final int expiresAt;

  /// Optional hash binding the receipt to external evidence
  /// (PoR: sha256 of the proven chunk bytes).
  final String? evidenceHash;

  /// Base64 Ed25519 signature over [canonicalJson] by the verifier.
  /// Empty when the verifier had no signing identity — the receipt still
  /// records the work but can only be claimed as unattested value.
  final String verifierSig;

  /// Optional prover counter-signature (base64) acknowledging the receipt.
  final String? proverSig;

  /// Spend-dedup flag: set once the receipt has been claimed.
  final bool spent;

  /// Persistence timestamp (db column `created_at`).
  final DateTime? createdAt;

  const WorkReceipt._({
    required this.receiptId,
    required this.workType,
    required this.proverPubkey,
    required this.verifierPubkey,
    required this.chunkIndices,
    required this.challengeNonce,
    required this.responseTag,
    required this.workUnits,
    required this.amount,
    required this.epoch,
    required this.expiresAt,
    this.cid,
    this.evidenceHash,
    this.verifierSig = '',
    this.proverSig,
    this.spent = false,
    this.createdAt,
  });

  /// Issues a new receipt, deriving [receiptId] from the canonical body.
  factory WorkReceipt.issue({
    required String workType,
    required String proverPubkey,
    required String verifierPubkey,
    String? cid,
    List<int> chunkIndices = const [],
    required String challengeNonce,
    required String responseTag,
    required double workUnits,
    required double amount,
    required String epoch,
    required int expiresAt,
    String? evidenceHash,
    String verifierSig = '',
    String? proverSig,
    bool spent = false,
    DateTime? createdAt,
  }) {
    final draft = WorkReceipt._(
      receiptId: '',
      workType: workType,
      proverPubkey: proverPubkey,
      verifierPubkey: verifierPubkey,
      cid: cid,
      chunkIndices: List.unmodifiable(chunkIndices),
      challengeNonce: challengeNonce,
      responseTag: responseTag,
      workUnits: workUnits,
      amount: amount,
      epoch: epoch,
      expiresAt: expiresAt,
      evidenceHash: evidenceHash,
      verifierSig: verifierSig,
      proverSig: proverSig,
      spent: spent,
      createdAt: createdAt,
    );
    return draft._with(receiptId: draft.computeReceiptId());
  }

  /// UTC-day epoch key ('YYYY-MM-DD') used for daily mint accounting.
  static String epochFor(DateTime dt) {
    final u = dt.toUtc();
    return '${u.year}-${u.month.toString().padLeft(2, '0')}-'
        '${u.day.toString().padLeft(2, '0')}';
  }

  /// Canonical wire-format version. Bumped when the signed body changes
  /// shape so foreign verifiers can pin the scheme they recompute.
  static const int wireVersion = 1;

  /// [amount] expressed as integer milli-units (`amount * 1000`, rounded).
  /// The canonical body serializes ONLY this integer form: a foreign
  /// verifier recomputing [receiptId] via RFC 8785 JCS must never diverge
  /// on Dart's `1.0` vs JavaScript's `1` number formatting. The double
  /// [amount] accessor remains for display.
  int get amountMilli => (amount * 1000).round();

  /// [workUnits] expressed as integer milli-units — see [amountMilli].
  int get workUnitsMilli => (workUnits * 1000).round();

  /// The signed body: every consensus field EXCEPT the receipt id, both
  /// signatures, and bookkeeping (spent/createdAt). The signature therefore
  /// attests to the work terms themselves, and adding/removing a signature
  /// never changes [receiptId].
  ///
  /// Wire format v1: `v` pins the scheme version, and the monetary fields
  /// travel as integers (`amountMilli`/`workUnitsMilli`) so canonical JSON
  /// is bit-identical across platforms — see [amountMilli].
  Map<String, dynamic> unsignedBody() => {
        'amountMilli': amountMilli,
        'challengeNonce': challengeNonce,
        'chunkIndices': chunkIndices,
        'epoch': epoch,
        'expiresAt': expiresAt,
        'proverPubkey': proverPubkey,
        'responseTag': responseTag,
        'v': wireVersion,
        'verifierPubkey': verifierPubkey,
        'workType': workType,
        'workUnitsMilli': workUnitsMilli,
        if (cid != null) 'cid': cid,
        if (evidenceHash != null) 'evidenceHash': evidenceHash,
      };

  /// Deterministic, sorted-key JSON of [unsignedBody] — the exact byte
  /// preimage for both [receiptId] and [verifierSig].
  String canonicalJson() => jsonEncode(_canonicalize(unsignedBody()));

  /// sha256 (hex) of [canonicalJson]. Stable across platforms and key order.
  String computeReceiptId() =>
      sha256.convert(utf8.encode(canonicalJson())).toString();

  /// The canonical bytes a verifier signs / a checker verifies.
  Uint8List get signingPayload =>
      Uint8List.fromList(utf8.encode(canonicalJson()));

  /// True when prover and verifier are the same key — a self-issued receipt
  /// that proves integrity of storage but carries no attestation weight
  /// (the self-PoR loop is closed: it can never be claimed as attested).
  bool get isSelfIssued =>
      proverPubkey.isNotEmpty && proverPubkey == verifierPubkey;

  /// Whether this receipt carries a verifier signature at all.
  bool get isVerifierSigned => verifierSig.isNotEmpty;

  /// Whether the receipt can be claimed as *attested* value: signed by a
  /// verifier that is not the prover. (Signature validity itself is checked
  /// separately via [verifyVerifierSignature].)
  ///
  /// This is an intrinsic property of the artifact only. A CLAIMING node
  /// must additionally require `verifierPubkey != <own pubkey>`: a receipt
  /// the local node signed itself can never carry attestation weight for a
  /// local mint — attestation means a *foreign* verifier vouched.
  bool get isAttestedClaim => isVerifierSigned && !isSelfIssued;

  /// True when [expiresAt] has passed relative to [now] (default: now).
  bool isExpired([DateTime? now]) =>
      (now ?? DateTime.now()).millisecondsSinceEpoch > expiresAt;

  /// Returns a copy carrying [sig] as [verifierSig]. The receipt id is
  /// unchanged — the signature is outside the canonical body.
  WorkReceipt withVerifierSig(String sig) => _with(verifierSig: sig);

  /// Returns a copy flagged as consumed by a claim. `spent` is
  /// bookkeeping outside the canonical body, so the receipt id is
  /// unchanged. Used so the artifact returned to callers reflects the
  /// state actually persisted by `markReceiptSpent`.
  WorkReceipt markSpent() => _with(spent: true);

  /// Verifies [verifierSig] over [canonicalJson] using the injected Ed25519
  /// [verifyFn]. Returns false for unsigned receipts or malformed input.
  Future<bool> verifyVerifierSignature(
      ReceiptSignatureVerifier verifyFn) async {
    if (verifierSig.isEmpty || verifierPubkey.isEmpty) return false;
    try {
      final sigBytes = base64Decode(verifierSig);
      if (sigBytes.length != 64) return false;
      return await verifyFn(
        signingPayload,
        sigBytes,
        verifierPubkey,
      );
    } catch (_) {
      return false;
    }
  }

  WorkReceipt _with({
    String? receiptId,
    String? verifierSig,
    String? proverSig,
    bool? spent,
  }) {
    return WorkReceipt._(
      receiptId: receiptId ?? this.receiptId,
      workType: workType,
      proverPubkey: proverPubkey,
      verifierPubkey: verifierPubkey,
      cid: cid,
      chunkIndices: chunkIndices,
      challengeNonce: challengeNonce,
      responseTag: responseTag,
      workUnits: workUnits,
      amount: amount,
      epoch: epoch,
      expiresAt: expiresAt,
      evidenceHash: evidenceHash,
      verifierSig: verifierSig ?? this.verifierSig,
      proverSig: proverSig ?? this.proverSig,
      spent: spent ?? this.spent,
      createdAt: createdAt,
    );
  }

  /// Map shaped for `AppDatabase.insertWorkReceipt` — `chunkIndices` is the
  /// JSON-array TEXT column form.
  Map<String, dynamic> toDbMap() => {
        'receiptId': receiptId,
        'workType': workType,
        'proverPubkey': proverPubkey,
        'verifierPubkey': verifierPubkey,
        'cid': cid,
        'chunkIndices': jsonEncode(chunkIndices),
        'challengeNonce': challengeNonce,
        'responseTag': responseTag,
        'workUnits': workUnits,
        'amount': amount,
        'epoch': epoch,
        'expiresAt': expiresAt,
        'evidenceHash': evidenceHash,
        'verifierSig': verifierSig,
        'proverSig': proverSig,
        'spent': spent,
        'createdAt': createdAt ?? DateTime.now(),
      };

  /// Rebuilds a receipt from a `getWorkReceipt` row map.
  factory WorkReceipt.fromDbMap(Map<String, dynamic> map) {
    return WorkReceipt._(
      receiptId: map['receiptId'] as String,
      workType: map['workType'] as String,
      proverPubkey: map['proverPubkey'] as String,
      verifierPubkey: map['verifierPubkey'] as String,
      cid: map['cid'] as String?,
      chunkIndices: List.unmodifiable(
          (jsonDecode(map['chunkIndices'] as String) as List)
              .map((e) => (e as num).toInt())),
      challengeNonce: map['challengeNonce'] as String,
      responseTag: map['responseTag'] as String,
      workUnits: (map['workUnits'] as num).toDouble(),
      amount: (map['amount'] as num).toDouble(),
      epoch: map['epoch'] as String,
      expiresAt: (map['expiresAt'] as num).toInt(),
      evidenceHash: map['evidenceHash'] as String?,
      verifierSig: map['verifierSig'] as String? ?? '',
      proverSig: map['proverSig'] as String?,
      spent: map['spent'] as bool? ?? false,
      createdAt: map['createdAt'] as DateTime?,
    );
  }

  /// JSON view returned to MCP agents — the inspectable artifact. Amounts
  /// stay doubles for display; `v`, `amount_milli` and `work_units_milli`
  /// carry the wire-format-v1 integer fields a foreign verifier needs to
  /// recompute [receiptId] bit-exactly.
  Map<String, dynamic> toJson() => {
        'receipt_id': receiptId,
        'v': wireVersion,
        'work_type': workType,
        'prover_pubkey': proverPubkey,
        'verifier_pubkey': verifierPubkey,
        'cid': cid,
        'chunk_indices': chunkIndices,
        'challenge_nonce': challengeNonce,
        'response_tag': responseTag,
        'work_units': workUnits,
        'amount': amount,
        'work_units_milli': workUnitsMilli,
        'amount_milli': amountMilli,
        'epoch': epoch,
        'expires_at': expiresAt,
        'evidence_hash': evidenceHash,
        'verifier_sig': verifierSig,
        'prover_sig': proverSig,
        'spent': spent,
        'self_issued': isSelfIssued,
        'attested_claim': isAttestedClaim,
      };

  /// Recursively sorts map keys so JSON encoding is canonical.
  static dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final out = <String, dynamic>{};
      for (final k in keys) {
        out[k] = _canonicalize(value[k]);
      }
      return out;
    }
    if (value is List) {
      return value.map(_canonicalize).toList();
    }
    return value;
  }
}
