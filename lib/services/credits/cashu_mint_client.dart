import 'dart:convert';
import 'package:http/http.dart' as http;
import '../url_safety.dart';
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
    final uri = _mintUri(mintUrl, '/v1/keys');

    final res = await _gatedSend(
      'GET',
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'Alexandria-Cashu-Client/1.0',
      },
      timeout: const Duration(seconds: 10),
    );

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
    final uri = _mintUri(mintUrl, '/v1/melt/quote/bolt11');

    final res = await _gatedSend(
      'POST',
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Alexandria-Cashu-Client/1.0',
      },
      body: jsonEncode({
        'request': bolt11,
        'unit': 'sat',
      }),
      timeout: const Duration(seconds: 15),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError(
          'Failed to get melt quote from mint (HTTP ${res.statusCode}: ${res.body})');
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
    final uri = _mintUri(mintUrl, '/v1/melt/bolt11');

    final res = await _gatedSend(
      'POST',
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Alexandria-Cashu-Client/1.0',
      },
      body: jsonEncode({
        'quote': quoteId,
        'inputs': proofs.map((p) => p.toJson()).toList(),
      }),
      timeout: const Duration(seconds: 30),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError(
          'Melt execution failed at mint (HTTP ${res.statusCode}: ${res.body})');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return CashuMeltResult(
      paid: data['paid'] as bool? ?? false,
      paymentPreimage: data['payment_preimage'] as String?,
      quoteId: quoteId,
    );
  }

  static Uri _mintUri(String mintUrl, String path) {
    final cleanUrl = mintUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$cleanUrl$path');
  }

  /// (round-5 red finding) Every mint leg is gated exactly like the
  /// LNURL legs (`LnurlService._gatedGet`): the mint URL is
  /// caller-supplied remote configuration, and the melt paths POST
  /// bearer Cashu proofs to it - an unchecked URL is SSRF plus
  /// cleartext token exfiltration.
  ///
  /// The request URL passes [UrlSafety.requirePublicFetchUri] BEFORE a
  /// single byte is requested (https only, http for .onion; every
  /// inet_aton/IPv6-literal spelling parsed; DNS answers checked). The
  /// transport NEVER follows redirects internally - `followRedirects`
  /// is pinned off - and each redirect hop a GET follows is re-gated.
  /// A redirect on a proof-bearing POST is refused outright: re-issuing
  /// the request against an unvetted target would hand the tokens to a
  /// host the caller never named.
  Future<http.Response> _gatedSend(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    required Duration timeout,
  }) async {
    var current = uri;
    for (var hop = 0; hop <= UrlSafety.maxRedirectHops; hop++) {
      await UrlSafety.requirePublicFetchUri(current, allowOnionHttp: true);
      final request = http.Request(method, current)
        ..followRedirects = false
        ..maxRedirects = 0;
      if (headers != null) request.headers.addAll(headers);
      if (body != null) request.body = body;
      final response = await _client
          .send(request)
          .timeout(timeout)
          .then(http.Response.fromStream);
      final location = response.headers['location'];
      if (_isRedirect(response.statusCode) && location != null) {
        if (method != 'GET') {
          throw StateError(
              'Refusing to follow an HTTP ${response.statusCode} redirect '
              'on a proof-bearing mint request');
        }
        final next = Uri.tryParse(location);
        if (next == null) {
          throw const FormatException(
              'Mint response carried an unparseable redirect target');
        }
        current = current.resolveUri(next);
        continue; // next loop iteration re-gates the redirect target
      }
      return response;
    }
    throw const FormatException('Mint request exceeded the redirect limit');
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  void close() {
    _client.close();
  }
}
