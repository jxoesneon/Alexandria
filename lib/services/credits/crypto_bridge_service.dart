import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'credit_models.dart';
import 'credit_service.dart';
import 'cashu_mint_client.dart';
import 'lnurl_service.dart';

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
      final jsonMap = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;

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

  final Set<String> _spentCashuSecrets = {};
  final List<String> _exportedTokensHistory = [];

  CryptoBridgeService({
    required CreditService creditService,
    LnurlService? lnurlService,
    CashuMintClient? mintClient,
  })  : _creditService = creditService,
        _lnurlService = lnurlService ?? LnurlService(),
        _mintClient = mintClient ?? CashuMintClient();

  String get lightningAddress => _lightningAddress;
  String get preferredCashuMint => _preferredCashuMint;
  List<String> get exportedTokensHistory => List.unmodifiable(_exportedTokensHistory);

  void setLightningAddress(String address) {
    _lightningAddress = address.trim();
    notifyListeners();
  }

  void setCashuMint(String mintUrl) {
    _preferredCashuMint = mintUrl.trim();
    notifyListeners();
  }

  /// Validates a standard Lightning Address format (user@domain.com)
  static bool isValidLightningAddress(String address) {
    final trimmed = address.trim();
    final regex = RegExp(r'^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$');
    return regex.hasMatch(trimmed);
  }

  /// Exports a specified amount of Archival Credits into an anonymous Chaumian E-Cash bearer token
  CashuToken? exportCreditsAsCashuToken(double creditsToExport) {
    if (creditsToExport <= 0 || _creditService.balance < creditsToExport) {
      return null;
    }

    final totalSats = (creditsToExport * satsPerCredit).toInt();
    if (totalSats <= 0) return null;

    // Deduct from local wallet balance
    final success = _creditService.spendCredits(
      amount: creditsToExport,
      reason: 'Exported to Chaumian E-Cash ($totalSats Sats)',
      debitType: CreditType.priorityAccessDebit,
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

  /// Redeems an incoming Chaumian E-Cash token voucher and deposits credits into the local wallet
  double redeemCashuToken(String tokenString) {
    final token = CashuToken.deserialize(tokenString);
    if (token == null || token.proofs.isEmpty) {
      return 0.0;
    }

    // Check for double-spend against spent secrets
    int unspentSats = 0;
    for (final proof in token.proofs) {
      if (!_spentCashuSecrets.contains(proof.secret)) {
        unspentSats += proof.amount;
        _spentCashuSecrets.add(proof.secret);
      }
    }

    if (unspentSats <= 0) {
      return 0.0; // All proofs already spent
    }

    // Convert unspent sats to Archival Credits
    final creditsAwarded = unspentSats / satsPerCredit;

    _creditService.awardVerificationCredits(
      action: 'Redeemed Cashu E-Cash Voucher ($unspentSats Sats from ${token.mint})',
      targetId: 'cashu_${token.proofs.first.id}',
      amount: creditsAwarded,
    );

    notifyListeners();
    return creditsAwarded;
  }

  /// Simulates a non-custodial Lightning payment sweep to the user's configured Lightning Address
  bool sweepToLightningAddress({
    required double creditsToSweep,
    String? customAddress,
  }) {
    final target = customAddress ?? _lightningAddress;
    if (!isValidLightningAddress(target)) return false;
    if (creditsToSweep <= 0 || _creditService.balance < creditsToSweep) return false;

    final sats = (creditsToSweep * satsPerCredit).toInt();

    final success = _creditService.spendCredits(
      amount: creditsToSweep,
      reason: 'Lightning Payout to $target ($sats Sats)',
      referenceId: target,
      debitType: CreditType.priorityAccessDebit,
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
        // 5. Deduct credits on successful payment confirmation
        _creditService.spendCredits(
          amount: creditsToSweep,
          reason: 'Live Lightning Payout to $target ($sats Sats)',
          referenceId: meltResult.paymentPreimage ?? invoice.pr,
          debitType: CreditType.priorityAccessDebit,
        );

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
