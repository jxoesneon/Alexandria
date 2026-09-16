// RED TEAM PoC - Round-4: UrlSafety.requirePublicFetchUri blocks every
// inet_aton IPv4 spelling and the obvious IPv6 ranges (::, ::1,
// fe80::/10, fc00::/7, ff00::/8, IPv4-MAPPED ::ffff:a.b.c.d) - but it
// does NOT recognise the OTHER IPv6 transition/translation forms that
// embed an IPv4 address the kernel will route to:
//
//   lib/services/url_safety.dart::_requirePublicIpv6Bytes
//
//   * NAT64 well-known prefix 64:ff9b::/96 - on NAT64 networks (mobile
//     carriers, Apple-mandated NAT64 nets, cloud VPCs) the last 32 bits
//     ARE an IPv4 destination: 64:ff9b::a9fe:a9fe == 169.254.169.254 -
//     the cloud metadata endpoint the v4 gate was built to protect.
//   * 6to4 2002::/16 - bytes 2..5 are the tunnelled IPv4; anycast relays
//     forward to it: 2002:7f00:1:: == 127.0.0.1.
//   * Teredo 2001::/32 - embeds the (obfuscated) client IPv4.
//   * IPv4-compatible ::/96 (deprecated) - ::7f00:1 == 127.0.0.1 on
//     stacks that still honour it.
//   * IPv4-translated ::ffff:0:0/96 (SIIT) - ::ffff:0:7f00:1 embeds
//     127.0.0.1 but raw[10..11] are 00,00 so the existing v4-mapped
//     check misses it.
//
// Verified empirically: InternetAddress.tryParse accepts every one of
// these and _requirePublicIpv6Bytes lets them through - a Crossref
// pdfUrl or LNURL callback of https://[64:ff9b::a9fe:a9fe]/ fetches the
// metadata service wherever NAT64/6to4/Teredo routing exists.
//
// Asserts the SECURE expectation: every IPv6 form that embeds or
// tunnels an IPv4 address must be refused when the embedded address is
// non-public.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/url_safety.dart';

Future<void> _expectRefused(String url) async {
  Object? threw;
  try {
    await UrlSafety.requirePublicFetchUri(Uri.parse(url));
  } catch (e) {
    threw = e;
  }
  expect(threw, isNotNull,
      reason: '$url was NOT refused — the IPv6 transition mechanism '
          'embeds a private IPv4 the gate does not inspect, so the SSRF '
          'wall is routable around on NAT64/6to4/Teredo networks.');
}

void main() {
  group('IPv4-in-IPv6 transition tunnels must be gated', () {
    // NAT64 well-known prefix (RFC 6052): last 32 bits = IPv4.
    test('NAT64 64:ff9b::/96 embedding link-local/metadata IPv4', () async {
      await _expectRefused('https://[64:ff9b::a9fe:a9fe]/latest/meta-data');
      await _expectRefused('https://[64:ff9b::7f00:1]/x'); // 127.0.0.1
      await _expectRefused('https://[64:ff9b::a00:1]/x'); // 10.0.0.1
      await _expectRefused('https://[64:ff9b::c0a8:1]/x'); // 192.168.0.1
    });

    // 6to4 (RFC 3056): bytes 2..5 = tunnelled IPv4.
    test('6to4 2002::/16 embedding loopback/private IPv4', () async {
      await _expectRefused('https://[2002:7f00:1::]/x'); // 127.0.0.1
      await _expectRefused('https://[2002:a9fe:a9fe::]/x'); // 169.254.169.254
      await _expectRefused('https://[2002:0a00:01::]/x'); // 10.0.0.1
    });

    // Teredo (RFC 4380): 2001:0000::/32.
    test('Teredo 2001::/32 tunnelling', () async {
      await _expectRefused('https://[2001:0:4136:e378:8000:63bf:3fff:fdd2]/x');
    });

    // Deprecated IPv4-compatible ::/96 - :: and ::1 are already refused;
    // the rest of the range is not.
    test('IPv4-compatible ::/96 embedding', () async {
      await _expectRefused('https://[::7f00:1]/x'); // 127.0.0.1
      await _expectRefused('https://[::a9fe:a9fe]/x'); // 169.254.169.254
    });

    // SIIT IPv4-translated ::ffff:0:0/96 - the existing mapped check
    // only inspects raw[10..11]==0xffff; this form puts the ffff at
    // bytes 8..9.
    test('IPv4-translated ::ffff:0:0/96 embedding', () async {
      await _expectRefused('https://[::ffff:0:7f00:1]/x'); // 127.0.0.1
      await _expectRefused('https://[::ffff:0:a9fe:a9fe]/x'); // 169.254.169.254
    });
  });

  group('round-3 IPv6 controls still hold (verification)', () {
    test('v4-mapped ::ffff:a.b.c.d is refused for private embeds', () async {
      Object? threw;
      try {
        await UrlSafety.requirePublicFetchUri(
            Uri.parse('https://[::ffff:7f00:1]/x'));
      } catch (e) {
        threw = e;
      }
      expect(threw, isNotNull);
    });

    test('isPublicAddress agrees for a NAT64 literal', () {
      final addr = InternetAddress.tryParse('64:ff9b::a9fe:a9fe')!;
      expect(UrlSafety.isPublicAddress(addr), isFalse,
          reason: 'isPublicAddress (exported for socket-level callers) also '
              'treats the NAT64-embedded link-local address as public.');
    });
  });
}
