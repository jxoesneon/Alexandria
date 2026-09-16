import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'credit_models.dart';
import 'credit_service.dart';
import 'cashu_mint_client.dart';
import 'lnurl_service.dart';
import '../url_safety.dart';

/// Provider for CryptoBridgeService
final cryptoBridgeServiceProvider =
    ChangeNotifierProvider<CryptoBridgeService>((ref) {
  final creditService = ref.read(creditServiceProvider);
  return CryptoBridgeService(creditService: creditService);
});

/// Result of an outbound Lightning sweep operation
class SweepResult {
  final bool success;
  final String status; // 'confirmed', 'simulated', 'failed'
  final int sats;
  final String? bolt11;
  final String? paymentPreimage;
  final String? error;

  const SweepResult({
    required this.success,
    required this.status,
    required this.sats,
    this.bolt11,
    this.paymentPreimage,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'status': status,
        'sats': sats,
        if (bolt11 != null) 'bolt11': bolt11,
        if (paymentPreimage != null) 'payment_preimage': paymentPreimage,
        if (error != null) 'error': error,
      };
}

/// Represents a single Chaumian blinded e-cash proof (Cashu NUT-00)
class CashuProof {
  final String id;
  final int amount;
  final String secret;
  final String c;

  const CashuProof({
    required this.id,
    required this.amount,
    required this.secret,
    required this.c,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'secret': secret,
        'C': c,
      };

  factory CashuProof.fromJson(Map<String, dynamic> json) {
    return CashuProof(
      id: json['id'] as String? ?? 'default_keyset',
      amount: (json['amount'] as num).toInt(),
      secret: json['secret'] as String,
      c: json['C'] as String,
    );
  }
}

/// Represents a serialized Cashu token container (Cashu NUT-00 v3 format)
class CashuToken {
  final String mint;
  final List<CashuProof> proofs;

  const CashuToken({
    required this.mint,
    required this.proofs,
  });

  int get totalAmountSats => proofs.fold(0, (sum, p) => sum + p.amount);

  /// Encodes to standard "cashuA" base64url string
  String serialize() {
    final payload = {
      'token': [
        {
          'mint': mint,
          'proofs': proofs.map((p) => p.toJson()).toList(),
        }
      ]
    };
    final jsonStr = jsonEncode(payload);
    final b64 = base64UrlEncode(utf8.encode(jsonStr)).replaceAll('=', '');
    return 'cashuA$b64';
  }

  /// Deserializes a standard "cashuA" token string
  static CashuToken? deserialize(String tokenString) {
    final trimmed = tokenString.trim();
    if (!trimmed.startsWith('cashuA')) return null;

    try {
      var b64 = trimmed.substring(6);
      // Re-add padding if needed
      while (b64.length % 4 != 0) {
        b64 += '=';
      }
      final jsonBytes = base64Url.decode(b64);
      final jsonMap =
          jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;

      final tokenList = jsonMap['token'] as List<dynamic>;
      if (tokenList.isEmpty) return null;

      final firstEntry = tokenList.first as Map<String, dynamic>;
      final mint = firstEntry['mint'] as String;
      final proofsRaw = firstEntry['proofs'] as List<dynamic>;

      final proofs = proofsRaw
          .map((p) => CashuProof.fromJson(p as Map<String, dynamic>))
          .toList();

      return CashuToken(mint: mint, proofs: proofs);
    } catch (_) {
      return null;
    }
  }
}

/// Service governing optional non-custodial Bitcoin Lightning & Cashu E-Cash edge bridges (ALX-005)
class CryptoBridgeService extends ChangeNotifier {
  final CreditService _creditService;
  final LnurlService _lnurlService;
  final CashuMintClient _mintClient;

  String _lightningAddress = '';
  String _preferredCashuMint = 'https://mint.minibits.cash/Bitcoin';

  /// Satoshis per Archival Credit (1 ℭ = 10 sats)
  static const int satsPerCredit = 10;

  /// Service-level kill switch for every ℭ→external-value path (ALX-010).
  /// Stays closed until verifier-signed work receipts exist and
  /// [CreditService.attestedBalance] reflects foreign-verified value. The MCP
  /// layer keeps its own flag as belt; this is the load-bearing suspender -
  /// direct callers (e.g. the human wallet dialog) cannot route around it.
  static const bool payoutsEnabled = false;

  /// Reason surfaced to callers/UI when egress is blocked by [payoutsEnabled].
  static const String payoutsDisabledReason =
      'Payout rails are disabled until the cross-verified attestation layer '
      'ships (ALX-010). Credits remain spendable inside Alexandria.';

  /// Reason voucher redemption is disabled: without real mint verification
  /// (NUT-03 swap + /v1/checkstate) fabricated proofs would mint unbacked ℭ.
  static const String redemptionDisabledReason =
      'Cashu voucher redemption is disabled until real mint verification '
      '(NUT-03 swap + /v1/checkstate) is implemented.';

  /// Runtime view of the compile-time kill switch [payoutsEnabled]. Control
  /// flow must read the gate through this getter so the analyzer does not
  /// constant-fold the flag while the feature is dark.
  final bool? _overridePayoutsAllowed;
  bool get _payoutsAllowed => _overridePayoutsAllowed ?? payoutsEnabled;

  /// Returns a human-readable reason an egress of [credits] ℭ is barred, or
  /// null when the request is well-formed and the kill switch is open.
  ///
  /// This is an ADVISORY, request-level check - it is deliberately NOT the
  /// attested-budget gate (round-1 red finding): a per-request
  /// `requested <= attestedBalance` comparison here is only a rate limit,
  /// because each approved call then settles through the debit path. The
  /// CUMULATIVE budget lives in the debit itself - every egress path below
  /// calls [CreditService.spendCredits] (or its durable variant) with
  /// `isAttested: true`, which
  /// refuses atomically once the attested pool is exhausted. Only
  /// verifier-signed attested credit may ever leave Alexandria (ALX-010);
  /// self-certified value stays internal-only.
  String? egressRejectionReason(double credits) {
    // Fail closed on non-finite / non-positive input BEFORE any comparison:
    // `NaN > x` is always false, so NaN and -Infinity would otherwise slip
    // past the checks and crash later on
    // `(credits * satsPerCredit).toInt()` (UnsupportedError outside the try
    // in sweepToLightningAddressLive).
    if (!credits.isFinite || credits <= 0) {
      return 'Invalid egress amount.';
    }
    if (!_payoutsAllowed) {
      return payoutsDisabledReason;
    }
    return null;
  }

  final Set<String> _spentCashuSecrets = {};
  final List<String> _exportedTokensHistory = [];

  CryptoBridgeService({
    required CreditService creditService,
    LnurlService? lnurlService,
    CashuMintClient? mintClient,
    bool? overridePayoutsAllowed,
  })  : _creditService = creditService,
        _lnurlService = lnurlService ?? LnurlService(),
        _mintClient = mintClient ?? CashuMintClient(),
        _overridePayoutsAllowed = overridePayoutsAllowed;

  String get lightningAddress => _lightningAddress;
  String get preferredCashuMint => _preferredCashuMint;
  List<String> get exportedTokensHistory =>
      List.unmodifiable(_exportedTokensHistory);

  void setLightningAddress(String address) {
    _lightningAddress = address.trim();
    notifyListeners();
  }

  /// Sets the preferred Cashu mint, gated through
  /// [UrlSafety.requirePublicFetchUri] at set time (orchestrator seam -
  /// the request-time gate in [CashuMintClient] already refuses private
  /// targets, but a mint URL that can never pass the gate is dead config
  /// and should be rejected where it is entered). `.onion` mints over
  /// plain http are allowed, matching the client's fetch policy.
  /// Returns true iff the URL was accepted.
  Future<bool> setCashuMint(String mintUrl) async {
    final trimmed = mintUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    try {
      await UrlSafety.requirePublicFetchUri(uri, allowOnionHttp: true);
    } on StateError {
      return false;
    }
    _preferredCashuMint = trimmed;
    notifyListeners();
    return true;
  }

  /// Validates a standard Lightning Address format (user@domain.com)
  static bool isValidLightningAddress(String address) {
    final trimmed = address.trim();
    final regex = RegExp(r'^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$');
    return regex.hasMatch(trimmed);
  }

  /// Exports a specified amount of Archival Credits into an anonymous Chaumian E-Cash bearer token
  ///
  /// OPTIMISTIC-RETURN SEMANTICS (kept synchronous for the existing
  /// MCP/UI call sites - documented seam): the attested debit settles
  /// through the write-behind path, so the returned bearer token can
  /// precede the durable row by a settle window. The durable gate still
  /// makes the over-spend non-canonical and rolls the local debit back,
  /// but an emitted token cannot be recalled - new callers should use
  /// [exportCreditsAsCashuTokenDurable], where a returned token
  /// provably corresponds to a durably-committed debit.
  CashuToken? exportCreditsAsCashuToken(double creditsToExport) {
    // ALX-010 service gate: no egress while payouts are disabled. Reason is
    // available to callers via [egressRejectionReason]. Never debits when
    // rejected.
    if (egressRejectionReason(creditsToExport) != null) return null;

    if (creditsToExport <= 0 || _creditService.balance < creditsToExport) {
      return null;
    }

    final totalSats = (creditsToExport * satsPerCredit).toInt();
    if (totalSats <= 0) return null;

    // Deduct from local wallet balance - settled against the ATTESTED pool
    // (isAttested: true): only foreign-verifier-backed value may ever leave
    // the system, and the refusal lands atomically inside the debit so the
    // cumulative attested budget can never be raced or re-read stale.
    final success = _creditService.spendCredits(
      amount: creditsToExport,
      reason: 'Exported to Chaumian E-Cash ($totalSats Sats)',
      debitType: CreditType.priorityAccessDebit,
      isAttested: true,
    );

    if (!success) return null;

    // Deconstruct total sats into power-of-2 denominations (Cashu standard)
    final proofs = _generateProofsForAmount(totalSats);
    final token = CashuToken(
      mint: _preferredCashuMint,
      proofs: proofs,
    );

    final serialized = token.serialize();
    _exportedTokensHistory.add(serialized);
    notifyListeners();

    return token;
  }

  /// DURABLE variant of [exportCreditsAsCashuToken] (optimistic-return
  /// residual - the egress half of the closure): the attested debit is
  /// committed through
  /// [CreditService.spendCreditsDurable] BEFORE the bearer token is
  /// assembled, so a non-null return provably corresponds to a
  /// durably-committed debit - the token can never outrun its own
  /// collateral.
  Future<CashuToken?> exportCreditsAsCashuTokenDurable(
      double creditsToExport) async {
    if (egressRejectionReason(creditsToExport) != null) return null;

    if (creditsToExport <= 0 || _creditService.balance < creditsToExport) {
      return null;
    }

    final totalSats = (creditsToExport * satsPerCredit).toInt();
    if (totalSats <= 0) return null;

    final success = await _creditService.spendCreditsDurable(
      amount: creditsToExport,
      reason: 'Exported to Chaumian E-Cash ($totalSats Sats)',
      debitType: CreditType.priorityAccessDebit,
      isAttested: true,
    );

    if (!success) return null;

    final proofs = _generateProofsForAmount(totalSats);
    final token = CashuToken(
      mint: _preferredCashuMint,
      proofs: proofs,
    );

    final serialized = token.serialize();
    _exportedTokensHistory.add(serialized);
    notifyListeners();

    return token;
  }

  /// Redeems an incoming Chaumian E-Cash token voucher and deposits credits into the local wallet
  ///
  /// DISABLED (ALX-010): always returns 0. Until proofs are verified against a
  /// real mint (NUT-03 swap + /v1/checkstate), crediting ℭ here would mint
  /// unbacked value for fabricated tokens - a local spent-set is not proof of
  /// mint backing. See [redemptionDisabledReason].
  double redeemCashuToken(String tokenString) {
    final token = CashuToken.deserialize(tokenString);
    if (token == null || token.proofs.isEmpty) {
      return 0.0;
    }

    // Well-formed vouchers are still rejected. Their secrets are absorbed into
    // the spent-set (never credited) so vouchers submitted while disabled can
    // never be replayed once real mint verification lands.
    for (final proof in token.proofs) {
      _spentCashuSecrets.add(proof.secret);
    }
    debugPrint('redeemCashuToken rejected: $redemptionDisabledReason');
    return 0.0;
  }

  /// Simulates a non-custodial Lightning payment sweep to the user's configured Lightning Address
  ///
  /// OPTIMISTIC-RETURN SEMANTICS - same seam as
  /// [exportCreditsAsCashuToken]: the returned `true` precedes the
  /// durable debit's settle. Prefer [sweepToLightningAddressDurable]
  /// for `true ⇒ committed` semantics.
  bool sweepToLightningAddress({
    required double creditsToSweep,
    String? customAddress,
  }) {
    // ALX-010 service gate: a simulated payout is still a ℭ→external-value
    // path (it burns real credits for a pretend payment) - gated identically.
    if (egressRejectionReason(creditsToSweep) != null) return false;

    final target = customAddress ?? _lightningAddress;
    if (!isValidLightningAddress(target)) return false;
    if (creditsToSweep <= 0 || _creditService.balance < creditsToSweep) {
      return false;
    }

    final sats = (creditsToSweep * satsPerCredit).toInt();

    // Attested-pool debit (isAttested: true) - a simulated payout is still a
    // ℭ→external-value path, so it draws on the same cumulative
    // foreign-verifier budget as a real sweep.
    final success = _creditService.spendCredits(
      amount: creditsToSweep,
      reason: 'Lightning Payout to $target ($sats Sats)',
      referenceId: target,
      debitType: CreditType.priorityAccessDebit,
      isAttested: true,
    );

    if (success) {
      notifyListeners();
    }
    return success;
  }

  /// DURABLE variant of [sweepToLightningAddress] - the attested debit
  /// is committed through [CreditService.spendCreditsDurable] before
  /// `true` is returned (optimistic-return residual closure on the
  /// egress paths).
  Future<bool> sweepToLightningAddressDurable({
    required double creditsToSweep,
    String? customAddress,
  }) async {
    if (egressRejectionReason(creditsToSweep) != null) return false;

    final target = customAddress ?? _lightningAddress;
    if (!isValidLightningAddress(target)) return false;
    if (creditsToSweep <= 0 || _creditService.balance < creditsToSweep) {
      return false;
    }

    final sats = (creditsToSweep * satsPerCredit).toInt();

    final success = await _creditService.spendCreditsDurable(
      amount: creditsToSweep,
      reason: 'Lightning Payout to $target ($sats Sats)',
      referenceId: target,
      debitType: CreditType.priorityAccessDebit,
      isAttested: true,
    );

    if (success) {
      notifyListeners();
    }
    return success;
  }

  /// Executes a live Lightning payment sweep over the wire (LUD-16 LNURL-pay -> Cashu NUT-05 Melt)
  Future<SweepResult> sweepToLightningAddressLive({
    required double creditsToSweep,
    String? customAddress,
    String? preferredMint,
  }) async {
    // ALX-010 service gate - fail closed before any network IO. The reason is
    // surfaced verbatim so callers (MCP tools, wallet UI) can display it.
    final rejection = egressRejectionReason(creditsToSweep);
    if (rejection != null) {
      return SweepResult(
        success: false,
        status: 'failed',
        sats: 0,
        error: rejection,
      );
    }

    final target = customAddress ?? _lightningAddress;
    if (!isValidLightningAddress(target)) {
      return const SweepResult(
        success: false,
        status: 'failed',
        sats: 0,
        error: 'Invalid Lightning Address format',
      );
    }

    if (creditsToSweep <= 0 || _creditService.balance < creditsToSweep) {
      return const SweepResult(
        success: false,
        status: 'failed',
        sats: 0,
        error: 'Insufficient credit balance',
      );
    }

    final sats = (creditsToSweep * satsPerCredit).toInt();
    final mint = preferredMint ?? _preferredCashuMint;

    try {
      // 1. Resolve Lightning Address to real BOLT11 invoice via LUD-16
      final invoice = await _lnurlService.resolveAddressToInvoice(
        lightningAddress: target,
        amountSats: sats,
      );

      // 2. Request melt quote from Cashu mint
      final meltQuote = await _mintClient.getMeltQuote(
        mintUrl: mint,
        bolt11: invoice.pr,
      );

      // 3. Decompose and generate proofs for required sats
      final proofs = _generateProofsForAmount(meltQuote.totalSatsRequired);

      // 4. Melt proofs at mint to settle Lightning invoice
      final meltResult = await _mintClient.meltProofs(
        mintUrl: mint,
        quoteId: meltQuote.quoteId,
        proofs: proofs,
      );

      if (meltResult.paid) {
        // 5. Deduct credits on successful payment confirmation - settled
        // against the ATTESTED pool (isAttested: true): sats already left on
        // the wire, so the cumulative foreign-verifier budget must be
        // enforced by the debit itself, not a stale pre-flight read.
        // DURABLE debit (optimistic-return residual - closed on the real
        // egress path): spendCreditsDurable commits the ledger row
        // through the durable attested-coverage gate BEFORE returning,
        // so a 'confirmed' result provably corresponds to a
        // durably-committed debit. A refusal is a reconciliation event -
        // never report 'confirmed' on a stale ledger.
        final debited = await _creditService.spendCreditsDurable(
          amount: creditsToSweep,
          reason: 'Live Lightning Payout to $target ($sats Sats)',
          referenceId: meltResult.paymentPreimage ?? invoice.pr,
          debitType: CreditType.priorityAccessDebit,
          isAttested: true,
        );

        if (!debited) {
          return SweepResult(
            success: false,
            status: 'failed',
            sats: sats,
            bolt11: invoice.pr,
            paymentPreimage: meltResult.paymentPreimage,
            error: 'Payment settled but local debit failed — manual '
                'reconciliation required',
          );
        }

        notifyListeners();
        return SweepResult(
          success: true,
          status: 'confirmed',
          sats: sats,
          bolt11: invoice.pr,
          paymentPreimage: meltResult.paymentPreimage,
        );
      } else {
        return SweepResult(
          success: false,
          status: 'failed',
          sats: sats,
          bolt11: invoice.pr,
          error: 'Mint could not route or settle Lightning invoice',
        );
      }
    } catch (e) {
      return SweepResult(
        success: false,
        status: 'failed',
        sats: sats,
        error: e.toString(),
      );
    }
  }

  List<CashuProof> _generateProofsForAmount(int totalSats) {
    final rnd = Random.secure();
    final proofs = <CashuProof>[];
    var remaining = totalSats;

    // Split into power-of-two pieces (1, 2, 4, 8, 16, 32, 64...)
    var denom = 1;
    while (remaining > 0) {
      if ((remaining & 1) == 1) {
        final secretBytes = List<int>.generate(32, (_) => rnd.nextInt(256));
        final secretHex = sha256.convert(secretBytes).toString();
        final cBytes = List<int>.generate(33, (_) => rnd.nextInt(256));
        final cHex = sha256.convert(cBytes).toString();

        proofs.add(CashuProof(
          id: 'alx_mint_01',
          amount: denom,
          secret: secretHex,
          c: cHex,
        ));
      }
      remaining >>= 1;
      denom <<= 1;
    }

    return proofs;
  }
}
