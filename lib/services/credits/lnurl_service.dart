import 'dart:convert';
import 'package:http/http.dart' as http;

/// Represents the result of a successful LUD-16 LNURL-pay invoice request
class LnurlPayInvoice {
  final String pr; // BOLT11 payment request (invoice)
  final int amountSats;
  final String recipientAddress;
  final String? paymentHash;

  const LnurlPayInvoice({
    required this.pr,
    required this.amountSats,
    required this.recipientAddress,
    this.paymentHash,
  });

  Map<String, dynamic> toJson() => {
        'pr': pr,
        'amount_sats': amountSats,
        'recipient_address': recipientAddress,
        if (paymentHash != null) 'payment_hash': paymentHash,
      };
}

/// Service implementing LUD-16 & LUD-06 LNURL-pay resolution to obtain real BOLT11 invoices
class LnurlService {
  final http.Client _client;

  LnurlService({http.Client? client}) : _client = client ?? http.Client();

  /// Resolves a Lightning Address (user@domain.com) into a real BOLT11 payment request
  Future<LnurlPayInvoice> resolveAddressToInvoice({
    required String lightningAddress,
    required int amountSats,
  }) async {
    final parts = lightningAddress.trim().split('@');
    if (parts.length != 2) {
      throw ArgumentError('Invalid Lightning Address format: $lightningAddress');
    }

    final user = parts[0];
    final domain = parts[1];

    // Step 1: Query .well-known/lnurlp endpoint
    final endpointUrl = Uri.https(domain, '/.well-known/lnurlp/$user');
    final res = await _client.get(endpointUrl, headers: {
      'Accept': 'application/json',
      'User-Agent': 'Alexandria-Client/1.0',
    }).timeout(const Duration(seconds: 10));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Failed to resolve LNURL endpoint for $lightningAddress (HTTP ${res.statusCode})');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

    final tag = data['tag'] as String?;
    if (tag != null && tag != 'payRequest') {
      throw StateError('Invalid LNURL tag: expected payRequest, got $tag');
    }

    final callback = data['callback'] as String?;
    if (callback == null || callback.isEmpty) {
      throw StateError('LNURL response missing callback URL');
    }

    final minSendable = (data['minSendable'] as num?)?.toInt() ?? 1000;
    final maxSendable = (data['maxSendable'] as num?)?.toInt() ?? 1000000000;
    final amountMilliSats = amountSats * 1000;

    if (amountMilliSats < minSendable || amountMilliSats > maxSendable) {
      throw RangeError(
        'Requested amount ($amountSats Sats = $amountMilliSats msats) is out of bounds [${minSendable ~/ 1000}, ${maxSendable ~/ 1000}] Sats.',
      );
    }

    // Step 2: Request BOLT11 payment request from callback URL
    final callbackUri = Uri.parse(callback).replace(queryParameters: {
      ...Uri.parse(callback).queryParameters,
      'amount': amountMilliSats.toString(),
    });

    final callbackRes = await _client.get(callbackUri, headers: {
      'Accept': 'application/json',
      'User-Agent': 'Alexandria-Client/1.0',
    }).timeout(const Duration(seconds: 10));

    if (callbackRes.statusCode < 200 || callbackRes.statusCode >= 300) {
      throw StateError('LNURL callback failed with HTTP ${callbackRes.statusCode}');
    }

    final invoiceData = jsonDecode(utf8.decode(callbackRes.bodyBytes)) as Map<String, dynamic>;
    final pr = invoiceData['pr'] as String?;
    if (pr == null || !pr.toLowerCase().startsWith('lnbc') && !pr.toLowerCase().startsWith('lntb')) {
      throw StateError('Invalid or missing BOLT11 invoice returned by LNURL callback: $pr');
    }

    return LnurlPayInvoice(
      pr: pr,
      amountSats: amountSats,
      recipientAddress: lightningAddress,
    );
  }

  void close() {
    _client.close();
  }
}
