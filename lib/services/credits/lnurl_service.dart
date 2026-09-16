import 'dart:convert';
import 'package:http/http.dart' as http;

import '../url_safety.dart';

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

/// Non-redirecting fetch transport for an LNURL network leg.
///
/// Implementations MUST return the raw response - including 3xx
/// statuses - without following `Location` internally. The service
/// re-gates every redirect target through
/// [UrlSafety.requirePublicFetchUri] before following it manually
/// (round-3 red finding). `package:http` clients follow redirects
/// inside `send()`/`get()` by default, so a plain `Client.get` is NOT a
/// compliant transport for production use; tests may inject
/// `mockClient.get` since MockClient never follows.
typedef LnurlFetch = Future<http.Response> Function(Uri uri);

/// Service implementing LUD-16 & LUD-06 LNURL-pay resolution to obtain real BOLT11 invoices
class LnurlService {
  /// Transport for the `.well-known/lnurlp` metadata leg only.
  final http.Client _client;

  /// Transport for the attacker-influenced `callback` leg (round-3 red
  /// finding). This is deliberately SEPARATE from [_client]: a
  /// general-purpose `http.Client` follows redirects inside `send()`
  /// (dart:io `HttpClientRequest.followRedirects` defaults to true,
  /// maxRedirects 5), so a gate-clean public callback could 302 the
  /// fetch into `http://169.254.169.254/…` with zero re-validation and
  /// the service could never observe it. The default transport is a
  /// dedicated client issued `followRedirects: false` requests; every
  /// redirect target re-enters the SSRF gate before it is fetched.
  late final LnurlFetch _callbackFetch;
  final http.Client? _ownedCallbackClient;

  LnurlService({http.Client? client, LnurlFetch? callbackTransport})
      : _client = client ?? http.Client(),
        _ownedCallbackClient =
            callbackTransport == null ? http.Client() : null {
    _callbackFetch = callbackTransport ?? _defaultCallbackFetch;
  }

  /// Resolves a Lightning Address (user@domain.com) into a real BOLT11 payment request
  Future<LnurlPayInvoice> resolveAddressToInvoice({
    required String lightningAddress,
    required int amountSats,
  }) async {
    final parts = lightningAddress.trim().split('@');
    if (parts.length != 2) {
      throw ArgumentError(
          'Invalid Lightning Address format: $lightningAddress');
    }

    final user = parts[0];
    final domain = parts[1];

    // Step 1: Query .well-known/lnurlp endpoint. The domain itself is
    // user-controlled input, so this leg is gated exactly like the
    // callback (round-3 red finding).
    final endpointUrl = Uri.https(domain, '/.well-known/lnurlp/$user');
    final res = await _gatedGet(endpointUrl, fetch: _wellKnownFetch);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError(
          'Failed to resolve LNURL endpoint for $lightningAddress (HTTP ${res.statusCode})');
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

    // Step 2: Request BOLT11 payment request from callback URL.
    // SSRF gate (round-2 red finding, deepened in round-3): the callback
    // is attacker-controlled input from an untrusted .well-known
    // document. It is fetched through [_callbackFetch] - a transport
    // that provably cannot follow redirects internally - and every hop
    // is re-gated by [UrlSafety.requirePublicFetchUri] (https, or http
    // for .onion; every inet_aton spelling parsed; DNS answers checked).
    final callbackBase = Uri.parse(callback);
    final callbackUri = callbackBase.replace(queryParameters: {
      ...callbackBase.queryParameters,
      'amount': amountMilliSats.toString(),
    });

    final callbackRes = await _gatedGet(callbackUri, fetch: _callbackFetch);

    if (callbackRes.statusCode < 200 || callbackRes.statusCode >= 300) {
      throw StateError(
          'LNURL callback failed with HTTP ${callbackRes.statusCode}');
    }

    final invoiceData =
        jsonDecode(utf8.decode(callbackRes.bodyBytes)) as Map<String, dynamic>;
    final pr = invoiceData['pr'] as String?;
    if (pr == null ||
        !pr.toLowerCase().startsWith('lnbc') &&
            !pr.toLowerCase().startsWith('lntb')) {
      throw StateError(
          'Invalid or missing BOLT11 invoice returned by LNURL callback: $pr');
    }

    return LnurlPayInvoice(
      pr: pr,
      amountSats: amountSats,
      recipientAddress: lightningAddress,
    );
  }

  /// The .well-known leg: a non-redirecting request through the
  /// injected/primary client.
  Future<http.Response> _wellKnownFetch(Uri uri) =>
      _sendNonRedirecting(_client, uri);

  /// The default callback-leg transport: a dedicated client whose
  /// requests disable redirect following entirely.
  Future<http.Response> _defaultCallbackFetch(Uri uri) =>
      _sendNonRedirecting(_ownedCallbackClient!, uri);

  /// Issues one GET that never follows redirects at the transport
  /// layer - the 3xx response is returned to the caller so the target
  /// can be re-validated before it is fetched.
  static Future<http.Response> _sendNonRedirecting(
      http.Client client, Uri uri) {
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['Accept'] = 'application/json'
      ..headers['User-Agent'] = 'Alexandria-Client/1.0';
    return client
        .send(request)
        .timeout(const Duration(seconds: 10))
        .then(http.Response.fromStream);
  }

  /// Gated GET for every LNURL network leg (round-3 red finding).
  ///
  /// Each request URL passes [UrlSafety.requirePublicFetchUri] BEFORE a
  /// single byte is requested, and every redirect `Location` is resolved
  /// against the current URL and re-gated on the next hop. The hop
  /// count is bounded by [UrlSafety.maxRedirectHops].
  Future<http.Response> _gatedGet(Uri uri, {required LnurlFetch fetch}) async {
    var current = uri;
    for (var hop = 0; hop <= UrlSafety.maxRedirectHops; hop++) {
      await UrlSafety.requirePublicFetchUri(current, allowOnionHttp: true);
      final response = await fetch(current);
      final location = response.headers['location'];
      if (_isRedirect(response.statusCode) && location != null) {
        final next = Uri.tryParse(location);
        if (next == null) {
          throw const FormatException(
              'LNURL response carried an unparseable redirect target');
        }
        current = current.resolveUri(next);
        continue; // next loop iteration gates the redirect target
      }
      return response;
    }
    throw const FormatException('LNURL request exceeded the redirect limit');
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  void close() {
    _client.close();
    _ownedCallbackClient?.close();
  }
}
