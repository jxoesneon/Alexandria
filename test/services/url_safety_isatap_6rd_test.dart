// Tests for the round-5 residual closure in UrlSafety: ISATAP and 6rd
// transition tunnels embed an IPv4 under SITE-CHOSEN prefixes, so the
// round-4 fixed-prefix denylist can't see them.
//
//   * ISATAP (RFC 5214): IID = 0000:5EFE:vvvv:vvvv or
//     0200:5EFE:vvvv:vvvv - bytes 12-15 are the tunnel destination;
//     it is re-gated through the IPv4 private-range table.
//   * 6rd (RFC 5969): the embedded v4 follows an operator-chosen
//     prefix; for a FULL 32-bit embed inside a ≤/64 delegated prefix
//     the prefix is ≤/32, so byte-aligned windows at offsets 0..4 are
//     scanned against the dangerous-v4 table.
//   * Global-unicast gate: anything fetchable is 2000::/3 (or
//     v4-mapped); all other v6 spellings are refused outright.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/url_safety.dart';

Future<void> _expectRefused(String url) async {
  Object? threw;
  try {
    await UrlSafety.requirePublicFetchUri(Uri.parse(url));
  } catch (e) {
    threw = e;
  }
  expect(threw, isNotNull, reason: '$url was NOT refused');
}

Future<void> _expectAllowed(String url) async {
  try {
    await UrlSafety.requirePublicFetchUri(Uri.parse(url));
  } catch (e) {
    fail('$url was refused but should be public: $e');
  }
}

/// Builds a global-unicast v6 literal carrying [v4] as a 32-bit
/// embed starting at [bitOffset] - simulating a 6rd operator
/// prefix of ANY length (nibble-boundary or arbitrary, e.g. /28,
/// /29, /36). The embed is OR-ed into a zeroed buffer and the
/// 2000::/3 marker bits are forced AFTERWARDS so prefix material
/// can never corrupt the window (every tested offset is ≥ 3, so
/// the top three bits lie outside the embed).
String _v6WithEmbed(int v4, int bitOffset) {
  final raw = Uint8List(16);
  for (var i = 0; i < 32; i++) {
    final bit = bitOffset + i;
    if (((v4 >> (31 - i)) & 1) == 1) {
      raw[bit >> 3] |= 1 << (7 - (bit & 7));
    }
  }
  raw[0] = (raw[0] & 0x1f) | 0x20; // 2000::/3 global unicast
  return InternetAddress.fromRawAddress(raw).address;
}

/// Same construction for a PARTIAL 24-bit embed - the shape a
/// 6rd relay configured with `IPv4PrefixLen = 8` leaves: only the
/// low 24 bits of the tunnelled v4 sit in the literal.
String _v6WithEmbed24(int v4low24, int bitOffset) {
  final raw = Uint8List(16);
  for (var i = 0; i < 24; i++) {
    final bit = bitOffset + i;
    if (((v4low24 >> (23 - i)) & 1) == 1) {
      raw[bit >> 3] |= 1 << (7 - (bit & 7));
    }
  }
  raw[0] = (raw[0] & 0x1f) | 0x20; // 2000::/3 global unicast
  return InternetAddress.fromRawAddress(raw).address;
}

void main() {
  group('ISATAP embedded IPv4 is re-gated (round-5 residual)', () {
    test('0000:5EFE IID embedding private IPv4 is refused', () async {
      // IID 0000:5efe:7f00:0001 → tunnel target 127.0.0.1
      await _expectRefused('https://[2001:db8:1::5efe:7f00:1]/x');
      // 10.0.0.1
      await _expectRefused('https://[2001:db8::5efe:a00:1]/x');
      // 169.254.169.254 - cloud metadata
      await _expectRefused('https://[2001:db8::5efe:a9fe:a9fe]/x');
      // 192.168.0.1
      await _expectRefused('https://[2001:db8::5efe:c0a8:1]/x');
    });

    test(
        '0200:5EFE IID form is inspected too (the tag is a hint '
        'only)', () async {
      await _expectRefused('https://[2001:db8::200:5efe:7f00:1]/x');
      await _expectRefused('https://[2001:db8::200:5efe:a9fe:a9fe]/x');
    });

    test(
        'ISATAP spelling with a genuinely public embed is not '
        'overblocked', () async {
      // IID 0000:5efe:0808:0808 → tunnel target 8.8.8.8 (public).
      await _expectAllowed('https://[2001:db8::5efe:808:808]/x');
    });
  });

  group('6rd embedded IPv4 heuristic (round-5 residual)', () {
    test('full v4 embed under a /32 operator prefix is refused', () async {
      // 2001:db8::/32 + embedded 10.0.0.1 at bytes 4-7.
      await _expectRefused('https://[2001:db8:a00:1::]/x');
      // embedded 127.0.0.1
      await _expectRefused('https://[2a01:e30:7f00:1::]/x');
      // embedded 169.254.169.254 - metadata endpoint
      await _expectRefused('https://[2a01:e30:a9fe:a9fe::]/x');
      // embedded 100.64.0.1 - CGNAT
      await _expectRefused('https://[2a01:e30:6440:1::]/x');
    });

    test('full v4 embed under /16 and /24 prefixes is refused', () async {
      // /16 prefix → embed at bytes 2-5: 2001:0a00:0001::
      await _expectRefused('https://[2001:a00:1::]/x');
      // /24 prefix → embed at bytes 3-6.
      await _expectRefused('https://[2a01:e30a:1::]/x'); // 10.x
      await _expectRefused('https://[2a01:e37f:1::]/x'); // 127.x
    });

    test('common public v6 literals are not overblocked', () async {
      await _expectAllowed('https://[2606:4700:4700::1111]/x');
      await _expectAllowed('https://[2001:4860:4860::8888]/x');
      await _expectAllowed('https://[2a00:1450:4001::1]/x');
      // v4-mapped public stays fetchable.
      await _expectAllowed('https://[::ffff:8.8.8.8]/x');
    });
  });

  group('6rd shifted-offset metadata embeds (round-6 residual push)', () {
    test('nibble-boundary embeds of cloud metadata IPs are refused', () async {
      // 169.254.169.254 at /28, /36, /44, /56-style embed offsets.
      for (final offset in [4, 12, 20, 28]) {
        final addr = _v6WithEmbed(0xa9fea9fe, offset);
        await _expectRefused('https://[$addr]/x');
      }
      // ECS task-credentials endpoint at a nibble offset too.
      await _expectRefused('https://[${_v6WithEmbed(0xa9feaa02, 12)}]/x');
    });

    test(
        'non-nibble (arbitrary prefix) embeds of metadata IPs are '
        'refused', () async {
      // Prefixes like /29, /33 - off the nibble grid entirely.
      for (final offset in [3, 7, 19, 29, 31]) {
        final addr = _v6WithEmbed(0xa9fea9fe, offset);
        await _expectRefused('https://[$addr]/x');
      }
    });

    test(
        'ordinary embeds at the same shifted offsets are not '
        'overblocked', () async {
      // A public value (8.8.8.8) at every scanned offset stays
      // fetchable - the denylist is exact-match, not a range.
      for (final offset in [4, 12, 20, 28]) {
        final addr = _v6WithEmbed(0x08080808, offset);
        await _expectAllowed('https://[$addr]/x');
      }
    });

    test('no false-positives on real global-unicast literals', () async {
      // The documented collision: the offset-12 window of Cloudflare's
      // anycast resolver decodes to 100.112.4.116 ∈ 100.64.0.0/10 -
      // a RANGE check at shifted offsets would refuse a real DNS
      // resolver. Exact-match does not.
      await _expectAllowed('https://[2606:4700:4700::1111]/x');
      await _expectAllowed('https://[2606:4700:4700::1001]/x');
      // More real public DNS/CDN literals.
      await _expectAllowed('https://[2001:4860:4860::8888]/x');
      await _expectAllowed('https://[2620:fe::fe]/x'); // Quad9
      await _expectAllowed('https://[2a10:50c0::ad1]/x'); // dns0.eu
      await _expectAllowed('https://[2a06:98c1:3120::3]/x');
      // Nibble-pattern near-misses of the metadata pattern that are
      // not an exact match at EITHER scanned width stay fetchable
      // (the byte-aligned windows of these spellings are all public
      // too).
      await _expectAllowed('https://[${_v6WithEmbed(0xa9fea9fc, 4)}]/x');
      await _expectAllowed('https://[${_v6WithEmbed(0xa9feb9fe, 4)}]/x');
      await _expectAllowed('https://[${_v6WithEmbed(0xa9fea9f0, 29)}]/x');
    });

    test('isPublicAddress agrees for shifted metadata embeds', () {
      final addr = InternetAddress.tryParse(_v6WithEmbed(0xa9fea9fe, 12))!;
      expect(UrlSafety.isPublicAddress(addr), isFalse);
    });
  });

  group('6rd partial embeds — v4PrefixLen = 8 shape (round-6 push)', () {
    test('low-24 metadata embeds are refused at any bit offset', () async {
      // 169.254.169.254 under a relay whose IPv4Prefix covers the
      // 169/8 high bits: the literal carries only fe.a9.fe.
      for (final offset in [4, 12, 20, 28, 40]) {
        await _expectRefused('https://[${_v6WithEmbed24(0xfea9fe, offset)}]/x');
      }
      // Off-nibble offsets, and the ECS-task-credentials variant.
      for (final offset in [3, 7, 19, 29]) {
        await _expectRefused('https://[${_v6WithEmbed24(0xfea9fe, offset)}]/x');
      }
      await _expectRefused('https://[${_v6WithEmbed24(0xfeaa02, 12)}]/x');
      await _expectRefused('https://[${_v6WithEmbed24(0xfea9fd, 33)}]/x');
    });

    test('ordinary low-24 values at the same offsets stay fetchable', () async {
      // 8.8.8.8's low 24 (08.08.08) is not a fingerprint.
      for (final offset in [4, 12, 20, 28]) {
        await _expectAllowed('https://[${_v6WithEmbed24(0x080808, offset)}]/x');
      }
      // Adjacent non-endpoint values (fe.a9.f0, fe.a8.fe) are not
      // exact matches either.
      await _expectAllowed('https://[${_v6WithEmbed24(0xfea9f0, 12)}]/x');
      await _expectAllowed('https://[${_v6WithEmbed24(0xfea8fe, 20)}]/x');
    });

    test(
        'a full-32 public embed whose low-24 IS the metadata '
        'fingerprint fails closed (documented ambiguity)', () async {
      // 168.254.169.254 is a PUBLIC v4 - but under a v4PrefixLen = 0
      // relay its full-32 embed presents the same 24-bit window a
      // v4PrefixLen = 8 metadata embed does. The gate cannot see the
      // relay config, so it refuses: fail-closed on that one literal.
      await _expectRefused('https://[${_v6WithEmbed(0xa8fea9fe, 4)}]/x');
      // Sanity: the neighbouring public embed whose low-24 differs
      // stays fetchable.
      await _expectAllowed('https://[${_v6WithEmbed(0xa8fea9f0, 4)}]/x');
    });
  });

  group('non-global-unicast IPv6 is refused outright', () {
    test('unallocated / IANA-reserved space is not fetchable', () async {
      await _expectRefused('https://[5000::1]/x');
      await _expectRefused('https://[0a00:1::]/x');
      await _expectRefused('https://[4000:ffff::1]/x');
    });
  });

  group('isPublicAddress agrees with the fetch gate', () {
    test('ISATAP private embed reports non-public', () {
      final addr = InternetAddress.tryParse('2001:db8::5efe:7f00:1')!;
      expect(UrlSafety.isPublicAddress(addr), isFalse);
    });

    test('6rd private embed reports non-public', () {
      final addr = InternetAddress.tryParse('2001:db8:a00:1::')!;
      expect(UrlSafety.isPublicAddress(addr), isFalse);
    });

    test('ordinary global unicast stays public', () {
      final addr = InternetAddress.tryParse('2606:4700:4700::1111')!;
      expect(UrlSafety.isPublicAddress(addr), isTrue);
    });
  });
}
