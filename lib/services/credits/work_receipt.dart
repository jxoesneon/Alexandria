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
/// JSON body; [verifierSig] is a base64 Ed25519 signature over the
/// domain-separated [signingPayload] derived from that body. A forked
/// client can mint a receipt claiming anything, but only receipts carrying
/// a *foreign* verifier's valid signature count as attested value;
/// self-signed receipts (prover == verifier) carry zero egress weight.
class WorkReceipt {
  /// sha256 of [canonicalJson] — the receipt's unique, content-derived id.
  final String receiptId;

  /// Wire-format version this artifact was issued under (ALX-012). It is a
  /// REAL per-receipt field, part of the canonical body — a foreign
  /// receipt's declared `v` travels with the artifact and selects the
  /// signature domain ([signingPayload]): v<=1 verifies over the bare
  /// canonical JSON (legacy, pre-domain receipts), v>=2 over the
  /// `'alexandria:receipt:v$v:'`-prefixed preimage. Newly issued receipts
  /// default to [wireVersion]; older rows hydrate with `v == 1`.
  final int v;

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
    this.v = wireVersion,
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
  /// [v] pins the wire-format version the artifact claims; it defaults to
  /// the current [wireVersion] and is only overridable so legacy-scheme
  /// receipts (v1, bare-domain signatures) remain constructible.
  factory WorkReceipt.issue({
    int v = wireVersion,
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
      v: v,
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

  /// Canonical wire-format version issued by THIS build. Bumped when the
  /// signed body changes shape so foreign verifiers can pin the scheme
  /// they recompute. v2 (ALX-012) introduced the domain-separated
  /// [signingPayload] — a domain change IS a wire change.
  static const int wireVersion = 2;

  /// [amount] expressed as integer milli-units (`amount * 1000`, rounded).
  /// The canonical body serializes ONLY this integer form: a foreign
  /// verifier recomputing [receiptId] via RFC 8785 JCS must never diverge
  /// on Dart's `1.0` vs JavaScript's `1` number formatting. The double
  /// [amount] accessor remains for display.
  ///
  /// Throws [ArgumentError] when [amount] is non-finite (NaN/±∞) or
  /// overflows the milli range — claim paths MUST guard
  /// `receipt.amount.isFinite` BEFORE reaching the canonicalizer (a
  /// hostile row hydrated via [WorkReceipt.fromDbMap] would otherwise
  /// crash mid-guard-chain).
  int get amountMilli => _milliOf(amount, 'amount');

  /// [workUnits] expressed as integer milli-units — see [amountMilli].
  /// Same fail-fast contract: guard `receipt.workUnits.isFinite` first.
  int get workUnitsMilli => _milliOf(workUnits, 'workUnits');

  /// Largest |milli| value safely representable on every platform —
  /// 2^53 - 1, the web's exact-integer budget, comfortably inside the
  /// VM's 64-bit int range.
  static const double _maxSafeMilli = 9007199254740991.0;

  static int _milliOf(double value, String field) {
    final milli = value * 1000;
    if (!value.isFinite || !milli.isFinite || milli.abs() > _maxSafeMilli) {
      throw ArgumentError.value(
          value,
          field,
          'receipt values must be finite and within milli range; claim '
          'paths must guard isFinite before canonicalizing');
    }
    return milli.round();
  }

  /// The signed body: every consensus field EXCEPT the receipt id, both
  /// signatures, and bookkeeping (spent/createdAt). The signature therefore
  /// attests to the work terms themselves, and adding/removing a signature
  /// never changes [receiptId].
  ///
  /// Wire format: [v] pins the scheme version PER RECEIPT, and the
  /// monetary fields travel as integers (`amountMilli`/`workUnitsMilli`)
  /// so canonical JSON is bit-identical across platforms — see
  /// [amountMilli].
  Map<String, dynamic> unsignedBody() => {
        'amountMilli': amountMilli,
        'challengeNonce': challengeNonce,
        'chunkIndices': chunkIndices,
        'epoch': epoch,
        'expiresAt': expiresAt,
        'proverPubkey': proverPubkey,
        'responseTag': responseTag,
        'v': v,
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

  /// The canonical bytes a verifier signs / a checker verifies
  /// (ALX-012 epoch-domain separation). The preimage is selected by THIS
  /// receipt's own [v]:
  ///  * `v >= 2`: `'alexandria:receipt:v$v:'` prefix + canonical JSON —
  ///    signatures are bound to the scheme epoch, so an artifact signed
  ///    under one domain can never be replayed under another;
  ///  * `v <= 1` (legacy): the bare canonical JSON — pre-domain receipts
  ///    keep verifying under their original preimage during the grace
  ///    window, so existing signed artifacts stay claimable.
  Uint8List get signingPayload {
    final canonical = canonicalJson();
    final preimage = v >= 2 ? 'alexandria:receipt:v$v:$canonical' : canonical;
    return Uint8List.fromList(utf8.encode(preimage));
  }

  /// True when prover and verifier are the same key — a self-issued receipt
  /// that proves integrity of storage but carries no attestation weight
  /// (the self-PoR loop is closed: it can never be claimed as attested).
  ///
  /// NOTE: this is the SYNTACTIC check — literal string equality. The
  /// same key material can be spelled as uppercase or space-padded hex
  /// (the strict hex decoder still accepts both spellings), so identity
  /// guards in claim paths must use the canonical [samePubkey]
  /// comparison instead of relying on this getter (or on `==` between
  /// key strings).
  bool get isSelfIssued =>
      proverPubkey.isNotEmpty && proverPubkey == verifierPubkey;

  /// Canonical public-key identity comparison (ALX-012 fix-up).
  ///
  /// Raw string equality is NOT an identity check: the same Ed25519 key
  /// can be written uppercase or padded with ASCII spaces — spellings
  /// the strict wire decoder still accepts as identical key bytes — so
  /// `a == b` misses equivalent keys and lets a self-signed receipt pose
  /// as foreign-verified (self-dealing bypass). Two tiers:
  ///  1. EXACT string equality after trimming — deliberately NOT
  ///     case-folded: folding would equate distinct non-hex identities
  ///     ('AbC' == 'abc' is not a key binding, it is a false positive),
  ///     and real hex case-variants are already covered by tier 2;
  ///  2. byte equality of decoded hex when BOTH strings decode under the
  ///     strict class (ASCII spaces stripped, even-length
  ///     `[0-9a-fA-F]+` only — exactly what the signature oracle's
  ///     `hexToBytes` accepts) — catches case and interior-padding
  ///     variants of real hex keys.
  ///
  /// A non-hex respelling ('+5', tab/NBSP/newline paddings that the old
  /// `int.parse`-based decoder silently accepted) satisfies NEITHER
  /// tier, so it fails closed here AND at the strict oracle: the
  /// decoder's acceptance set must never exceed the guard's, and the
  /// guard's must never exceed the decoder's.
  ///
  /// Returns false when either side is empty/blank — an absent key can
  /// never satisfy an identity binding (a vacuous `'' == ''` match must
  /// not pass a prover/verifier guard).
  static bool samePubkey(String a, String b) {
    final na = a.trim();
    final nb = b.trim();
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    final ba = _tryHexToBytes(na);
    final bb = _tryHexToBytes(nb);
    if (ba == null || bb == null || ba.length != bb.length) return false;
    for (var i = 0; i < ba.length; i++) {
      if (ba[i] != bb[i]) return false;
    }
    return true;
  }

  static final RegExp _hexChars = RegExp(r'^[0-9a-fA-F]+$');

  /// Strict hex decode — ASCII spaces stripped, then even-length
  /// `[0-9a-fA-F]+` only, mirroring the oracle decoder
  /// (`beacon_models.hexToBytes`) so the guard's acceptance set is
  /// IDENTICAL to the verifier's. Returns null when the input is not
  /// well-formed hex. Implemented locally so [WorkReceipt] stays free
  /// of a dependency on the agent layer.
  static Uint8List? _tryHexToBytes(String s) {
    final clean = s.replaceAll(' ', '');
    if (clean.isEmpty || clean.length.isOdd || !_hexChars.hasMatch(clean)) {
      return null;
    }
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

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

  /// Verifies [verifierSig] over the domain-separated [signingPayload]
  /// (chosen by this receipt's own [v]) using the injected Ed25519
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
      v: v,
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
        'v': v,
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
      // Rows predating the v column (or callers omitting it) hydrate as
      // the legacy scheme — v1 verifies over the bare canonical body.
      v: (map['v'] as num?)?.toInt() ?? 1,
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
  /// stay doubles for display; `v` (the receipt's own wire version),
  /// `amount_milli` and `work_units_milli` carry the integer fields a
  /// foreign verifier needs to recompute [receiptId] bit-exactly.
  Map<String, dynamic> toJson() => {
        'receipt_id': receiptId,
        'v': v,
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
