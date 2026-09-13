import 'dart:convert';
import 'package:http/http.dart' as http;
import 'crypto_bridge_service.dart';

/// Quote returned when preparing to melt Cashu proofs into a Lightning payment
class CashuMeltQuote {
  final String quoteId;
  final int amountSats;
  final int feeReserveSats;
  final bool paid;
  final int expiry;

  const CashuMeltQuote({
    required this.quoteId,
    required this.amountSats,
    required this.feeReserveSats,
    this.paid = false,
    required this.expiry,
  });

  int get totalSatsRequired => amountSats + feeReserveSats;

  Map<String, dynamic> toJson() => {
        'quote': quoteId,
        'amount': amountSats,
        'fee_reserve': feeReserveSats,
        'paid': paid,
        'expiry': expiry,
      };

  factory CashuMeltQuote.fromJson(Map<String, dynamic> json) {
    return CashuMeltQuote(
      quoteId: json['quote'] as String,
      amountSats: (json['amount'] as num).toInt(),
      feeReserveSats: (json['fee_reserve'] as num?)?.toInt() ?? 0,
      paid: json['paid'] as bool? ?? false,
      expiry: (json['expiry'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Result of melting Cashu proofs to settle a BOLT11 Lightning invoice
class CashuMeltResult {
  final bool paid;
  final String? paymentPreimage;
  final String quoteId;

  const CashuMeltResult({
    required this.paid,
    this.paymentPreimage,
    required this.quoteId,
  });

  Map<String, dynamic> toJson() => {
        'paid': paid,
        if (paymentPreimage != null) 'payment_preimage': paymentPreimage,
        'quote': quoteId,
      };
}

/// Client interacting with remote Chaumian E-Cash mints over standard Cashu v1 REST protocol
class CashuMintClient {
  final http.Client _client;

  CashuMintClient({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the active keyset IDs from a Cashu mint (NUT-03)
  Future<List<String>> fetchActiveKeysetIds(String mintUrl) async {
    final cleanUrl = mintUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanUrl/v1/keys');

    final res = await _client.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent': 'Alexandria-Cashu-Client/1.0',
    }).timeout(const Duration(seconds: 10));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Failed to fetch mint keysets (HTTP ${res.statusCode})');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final keysets = data['keysets'] as List<dynamic>? ?? [];
    return keysets
        .map((k) => (k as Map<String, dynamic>)['id'] as String)
        .toList();
  }

  /// Obtains a melt quote from the mint for a given BOLT11 payment request (NUT-05)
  Future<CashuMeltQuote> getMeltQuote({
    required String mintUrl,
    required String bolt11,
  }) async {
    final cleanUrl = mintUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanUrl/v1/melt/quote/bolt11');

    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Alexandria-Cashu-Client/1.0',
      },
      body: jsonEncode({
        'request': bolt11,
        'unit': 'sat',
      }),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Failed to get melt quote from mint (HTTP ${res.statusCode}: ${res.body})');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return CashuMeltQuote.fromJson(data);
  }

  /// Melts Cashu proofs at the mint to pay the BOLT11 invoice (NUT-05)
  Future<CashuMeltResult> meltProofs({
    required String mintUrl,
    required String quoteId,
    required List<CashuProof> proofs,
  }) async {
    final cleanUrl = mintUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanUrl/v1/melt/bolt11');

    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Alexandria-Cashu-Client/1.0',
      },
      body: jsonEncode({
        'quote': quoteId,
        'inputs': proofs.map((p) => p.toJson()).toList(),
      }),
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Melt execution failed at mint (HTTP ${res.statusCode}: ${res.body})');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return CashuMeltResult(
      paid: data['paid'] as bool? ?? false,
      paymentPreimage: data['payment_preimage'] as String?,
      quoteId: quoteId,
    );
  }

  void close() {
    _client.close();
  }
}
