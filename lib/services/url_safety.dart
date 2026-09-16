import 'dart:io';
import 'dart:typed_data';

/// Shared SSRF gate for URLs derived from untrusted remote metadata
/// (round-3 red finding — extracted so the LNURL callback leg and the
/// DOI-harvester PDF fetch enforce ONE policy).
///
/// The gate is deliberately layered:
///   1. Scheme: `https` only; `http` is permitted solely for Tor
///      `.onion` hidden services when `allowOnionHttp` is set (no public
///      CA can issue for them — the standard LUD convention).
///   2. Host spelling: EVERY `inet_aton` form the OS resolver would
///      accept is parsed locally — dotted quads, short forms
///      (`127.1`), octal octets (`0177.0.0.1`), hex octets
///      (`0x7f.0.0.1`), and single-integer (`2130706433`) — so no
///      numeric spelling of a private address can sail through as a
///      "hostname". Literal IPv6 gets the same range treatment.
///   3. Hostname names: `localhost`, `*.localhost` (trailing-dot FQDNs
///      normalized) and `.local`/`.internal`-style names are refused.
///   4. Resolution: hostnames are resolved via [InternetAddress.lookup]
///      and EVERY answer must be public — a hostname pointing into
///      loopback/private/link-local/CGNAT/ULA space is refused.
///
/// Residual: a DNS lookup that fails (offline resolver, NXDOMAIN under
/// test harnesses) is treated leniently — the fetch transport fails
/// closed on its own when the name genuinely does not resolve. Full
/// DNS-rebinding protection additionally needs resolve-and-pin at the
/// socket layer, which dart:io does not expose; that remains a known
/// limitation documented in the LNURL round-2 fix.
class UrlSafety {
  UrlSafety._();

  /// Bound on redirect hops a gated fetch loop may follow; each hop is
  /// re-gated through [requirePublicFetchUri].
  static const int maxRedirectHops = 5;

  /// Normalizes a URI host for policy checks: lowercase and strips the
  /// trailing-dot FQDN marker so `localhost.` cannot dodge a name check.
  static String normalizeHost(String host) {
    var h = host.toLowerCase();
    while (h.endsWith('.')) {
      h = h.substring(0, h.length - 1);
    }
    return h;
  }

  /// Throws [StateError] when [uri] must not be fetched. Returns
  /// normally only for a fetchable public target.
  static Future<void> requirePublicFetchUri(
    Uri uri, {
    bool allowOnionHttp = false,
  }) async {
    final host = normalizeHost(uri.host);
    if (host.isEmpty) {
      throw StateError('Refusing to fetch URL with no host: $uri');
    }

    final isOnion = host.endsWith('.onion');
    if (uri.scheme == 'https') {
      // allowed scheme
    } else if (allowOnionHttp && uri.scheme == 'http' && isOnion) {
      // Tor hidden service — http is the only option and stays in Tor.
    } else {
      throw StateError(
          'Refusing to fetch non-https URL${allowOnionHttp ? ' (http allowed only for .onion)' : ''}: $uri');
    }

    // .onion routing is Tor's problem — no IP semantics apply.
    if (isOnion) return;

    if (_isLocalName(host)) {
      throw StateError('Refusing to fetch a local hostname: $uri');
    }

    // Literal IPv4 in ANY inet_aton spelling.
    final v4 = parseInetAton(host);
    if (v4 != null) {
      _requirePublicIpv4Bytes(v4, uri);
      return;
    }

    // Literal IPv6 (Uri.host may or may not keep brackets).
    final v6Host = host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host;
    final v6 = InternetAddress.tryParse(v6Host);
    if (v6 != null && v6.type == InternetAddressType.IPv6) {
      requirePublicAddress(v6, uri);
      return;
    }

    // Hostname: resolve and demand every answer be public (round-3 red
    // finding — kills DNS spellings that re-encode private addresses as
    // names). A failed lookup is lenient: the transport fails closed on
    // its own for genuinely unresolvable names, and pinning the resolved
    // address is not available through dart:io's HttpClient anyway.
    try {
      final addresses = await InternetAddress.lookup(host);
      for (final address in addresses) {
        requirePublicAddress(address, uri);
      }
    } on StateError {
      rethrow;
    } catch (_) {
      // Resolver unavailable — syntactic verdict stands.
    }
  }

  /// Whether [address] is a public routable address. Exported so callers
  /// performing their own socket work can reuse the range table.
  static bool isPublicAddress(InternetAddress address) {
    try {
      requirePublicAddress(address, null);
      return true;
    } on StateError {
      return false;
    }
  }

  /// Throws when [address] falls in any non-public range.
  static void requirePublicAddress(InternetAddress address, [Uri? uri]) {
    final raw = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      _requirePublicIpv4Bytes(raw, uri);
      return;
    }
    _requirePublicIpv6Bytes(raw, uri);
  }

  /// Parses every IPv4 literal spelling `inet_aton` accepts:
  /// `a.b.c.d`, `a.b.c` (c fills 16 bits), `a.b` (b fills 24 bits),
  /// `a` (a fills 32 bits), with octal (`0`-prefixed) and hex
  /// (`0x`-prefixed) parts. Returns the 4 address bytes, or null when
  /// [host] is not a numeric IPv4 literal at all.
  static List<int>? parseInetAton(String host) {
    final parts = host.split('.');
    if (parts.isEmpty || parts.length > 4) return null;
    final values = <int>[];
    for (final part in parts) {
      final v = _parseInetAtonPart(part);
      if (v == null) return null;
      values.add(v);
    }
    final last = values.last;
    final int address;
    if (values.length == 1) {
      if (last > 0xFFFFFFFF) return null;
      address = last;
    } else {
      for (var i = 0; i < values.length - 1; i++) {
        if (values[i] > 0xFF) return null;
      }
      final lastBits = (5 - values.length) * 8;
      if (last >= (1 << lastBits)) return null;
      var head = 0;
      for (var i = 0; i < values.length - 1; i++) {
        head = (head << 8) | values[i];
      }
      address = (head << lastBits) | last;
    }
    return [
      (address >> 24) & 0xFF,
      (address >> 16) & 0xFF,
      (address >> 8) & 0xFF,
      address & 0xFF,
    ];
  }

  /// `inet_aton` part grammar: `0x` → hex, leading `0` → octal,
  /// otherwise decimal.
  static int? _parseInetAtonPart(String part) {
    if (part.isEmpty) return null;
    if (part.startsWith('0x') || part.startsWith('0X')) {
      final hex = part.substring(2);
      if (hex.isEmpty) return null;
      return int.tryParse(hex, radix: 16);
    }
    if (part.length > 1 && part.startsWith('0')) {
      return int.tryParse(part, radix: 8);
    }
    if (part == '0') return 0;
    return int.tryParse(part);
  }

  static bool _isLocalName(String host) {
    return host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.home.arpa') ||
        host == 'ip6-localhost' ||
        host == 'ip6-loopback';
  }

  static void _requirePublicIpv4Bytes(List<int> v4, [Uri? uri]) {
    final a = v4[0], b = v4[1], c = v4[2];
    final denied = a == 0 || // 0.0.0.0/8 "this network"
        a == 10 || // RFC-1918
        a == 127 || // loopback
        (a == 169 && b == 254) || // link-local (cloud metadata!)
        (a == 172 && b >= 16 && b <= 31) || // RFC-1918
        (a == 100 && b >= 64 && b <= 127) || // CGNAT 100.64/10
        (a == 192 && b == 168) || // RFC-1918
        (a == 192 && b == 0 && (c == 0 || c == 2)) || // IETF/TEST-NET-1
        (a == 198 && (b == 18 || b == 19)) || // benchmarking
        (a == 198 && b == 51 && c == 100) || // TEST-NET-2
        (a == 203 && b == 0 && c == 113) || // TEST-NET-3
        (a == 233 && b == 252 && c == 0) || // documentation MCAST
        a >= 224 || // multicast / reserved
        a == 255;
    if (denied) {
      throw StateError(
          'Refusing to fetch non-public IPv4 address${uri != null ? ': $uri' : ''}');
    }
  }

  static void _requirePublicIpv6Bytes(Uint8List raw, [Uri? uri]) {
    var denied = raw.every((b) => b == 0) || // :: unspecified
        (raw[15] == 1 && raw.sublist(0, 15).every((b) => b == 0)) || // ::1
        (raw[0] == 0xfe && (raw[1] & 0xC0) == 0x80) || // fe80::/10
        (raw[0] & 0xFE) == 0xfc || // fc00::/7 ULA
        raw[0] == 0xff; // ff00::/8 multicast

    // (round-4 red finding) IPv6 transition/translation mechanisms embed
    // an IPv4 address the kernel or a relay will route to — bypassing
    // the IPv4 gate above. Rather than extracting the embedded address
    // per-scheme (each has its own layout/obfuscation), the transition
    // prefixes are refused OUTRIGHT: no legitimate fetch target is a
    // literal NAT64/6to4/Teredo/SIIT/v4-compatible address, so the whole
    // class is denied fail-closed.
    //
    //   * ::/96 IPv4-compatible (deprecated): last 32 bits ARE the v4 —
    //     ::7f00:1 == 127.0.0.1. (:: and ::1 are inside this range.)
    //   * ::ffff:0:0/96 SIIT v4-translated: v4 in last 32 bits, ffff at
    //     bytes 8..9 — the v4-mapped check below never sees it.
    //   * 64:ff9b::/32 covers the NAT64 well-known prefix 64:ff9b::/96
    //     AND the local-use 64:ff9b:1::/48 (RFC 6052/8215): embedded v4
    //     at various offsets depending on prefix length.
    //   * 2002::/16 6to4: tunnelled v4 in bytes 2..5 — 2002:7f00:1:: is
    //     127.0.0.1 via anycast relay.
    //   * 2001:0000::/32 Teredo: embeds the (XOR-obfuscated) client v4.
    final first12Zero = raw.sublist(0, 12).every((b) => b == 0);
    denied = denied ||
        first12Zero || // ::/96 v4-compatible
        (raw.sublist(0, 8).every((b) => b == 0) &&
            raw[8] == 0xff &&
            raw[9] == 0xff &&
            raw[10] == 0 &&
            raw[11] == 0) || // ::ffff:0:0/96 SIIT v4-translated
        (raw[0] == 0x00 &&
            raw[1] == 0x64 &&
            raw[2] == 0xff &&
            raw[3] == 0x9b) || // 64:ff9b::/32 NAT64
        (raw[0] == 0x20 && raw[1] == 0x02) || // 2002::/16 6to4
        (raw[0] == 0x20 &&
            raw[1] == 0x01 &&
            raw[2] == 0 &&
            raw[3] == 0); // 2001:0000::/32 Teredo

    // IPv4-mapped ::ffff:a.b.c.d — re-check the embedded v4 address.
    final isV4Mapped = raw.sublist(0, 10).every((b) => b == 0) &&
        raw[10] == 0xff &&
        raw[11] == 0xff;
    if (!denied && isV4Mapped) {
      try {
        _requirePublicIpv4Bytes(raw.sublist(12), uri);
      } on StateError {
        denied = true;
      }
    }

    // (round-5 residual closure) ISATAP (RFC 5214): the interface
    // identifier embeds the tunnelled IPv4 as `0000:5EFE:vvvv:vvvv`
    // (private embeds) or `0200:5EFE:vvvv:vvvv` (formally "global"
    // embeds — the tag is a hint only, nothing enforces it, so BOTH
    // forms are inspected). Bytes 8-11 = 00 00 5E FE / 02 00 5E FE
    // mark the IID; bytes 12-15 are the actual tunnel destination the
    // ISATAP driver decapsulates toward — re-gate it through the full
    // IPv4 table. Unlike the fixed prefixes above, ISATAP lives under
    // site-chosen global-unicast prefixes, so it cannot be denied
    // outright — only the embedded v4 can be gated.
    if (!denied &&
        ((raw[8] == 0x00 || raw[8] == 0x02) &&
            raw[9] == 0x00 &&
            raw[10] == 0x5e &&
            raw[11] == 0xfe)) {
      try {
        _requirePublicIpv4Bytes(raw.sublist(12), uri);
      } on StateError {
        denied = true;
      }
    }

    // (round-5 residual closure) 6rd (RFC 5969): the tunnelled IPv4
    // sits immediately after an OPERATOR-CHOSEN 6rd prefix — there is
    // no fixed pattern to deny. What IS enumerable: for a FULL 32-bit
    // v4 to fit inside the delegated prefix (≤ /64), the 6rd prefix is
    // ≤ /32, so a byte-aligned full embed can only start at offsets
    // 0..4. Each candidate window is checked against the ranges a
    // tunnelled v4 could actually reach dangerously (loopback, RFC-1918,
    // link-local/metadata, CGNAT, benchmarking). Deliberately
    // NOT flagged: 0/8, multicast/reserved embeds, and the
    // documentation-only ranges (IETF protocol assignments,
    // TEST-NET-1/2/3, MCAST-TEST-NET) — none of those are routable to
    // a protected target, and flagging them only collides with
    // ordinary global-unicast literals (observed: dns0.eu's
    // 2a10:50c0::ad1 carries a c0:00:00 window at offset 3).
    // Residual forms: nibble-boundary 6rd prefixes (e.g. /28) that
    // shift the embed off the byte grid are covered by the bit-window
    // scan below; partial embeds whose shared high bits come from the
    // operator's configured v4 prefix are covered for the largest
    // enumerable shape (24-bit windows) and bounded beyond that —
    // see WORKING_ON.md.
    if (!denied) {
      for (var off = 0; off <= 4; off++) {
        if (_embeddedV4TargetsProtectedSpace(
            raw[off], raw[off + 1], raw[off + 2])) {
          denied = true;
          break;
        }
      }
    }

    // (round-6 residual push) 6rd prefixes are not constrained to byte
    // boundaries: a /28 or /36 (or any non-/8-multiple) operator prefix
    // shifts the 32-bit embed off the byte grid, and partial embeds
    // shift it further. RANGE checks cannot be applied at those bit
    // offsets — the windows overlap ordinary global-unicast spellings
    // (documented collision: the offset-12 window of the real
    // Cloudflare anycast literal 2606:4700:4700::1111 decodes to
    // 100.112.4.116 ∈ 100.64.0.0/10 — refusing on it would break a
    // legitimate DNS resolver address). What CAN be checked without
    // false-positives is an EXACT-match denylist of single-address
    // embeds whose 32-bit pattern is both uniquely high-value and
    // vanishingly unlikely to appear in an honest global-unicast
    // literal: the cloud metadata endpoints (the canonical SSRF
    // target). Every bit offset 0..32 inside the /64 embed region is
    // scanned, covering nibble-boundary AND arbitrary-prefix embeds.
    // Deliberately still open: shifted embeds of any OTHER protected
    // target — no exact list can enumerate private space. See
    // WORKING_ON.md.
    if (!denied) {
      for (var bit = 0; bit <= 32; bit++) {
        if (_isCriticalMetadataEmbed(raw, bit)) {
          denied = true;
          break;
        }
      }
    }

    // (round-6 residual push, partial embeds) A hostile/misconfigured
    // 6rd relay can compress the tunnelled v4 by configuring an
    // IPv4PrefixLen — only the LOW (32 − prefixLen) bits of the target
    // sit inside the literal; the discriminating high bits live in the
    // relay's config, invisible to this gate. The largest enumerable
    // shape is v4PrefixLen = 8: a 24-bit window carrying the low
    // octets of the metadata endpoints, scanned at every bit offset
    // 0..40 of the /64 embed region. Embeds of ≤16 bits
    // (v4PrefixLen ≥ 16) carry too few discriminating bits to match
    // without colliding constantly with ordinary literals — those
    // stay open (WORKING_ON.md). Residual ambiguity, accepted and
    // fail-closed: a 24-bit window match can equally be the low-24 of
    // a PUBLIC full-32 embed (e.g. 168.254.169.254 under a
    // v4PrefixLen = 0 relay) — the gate cannot see the relay config,
    // so it refuses that one literal rather than admit the tunnel.
    if (!denied) {
      for (var bit = 0; bit <= 40; bit++) {
        if (_isCriticalMetadataEmbed24(raw, bit)) {
          denied = true;
          break;
        }
      }
    }

    // (round-5 residual closure) The only legitimately fetchable v6
    // spellings left are global unicast — 2000::/3 — and the v4-mapped
    // form handled above. Everything else (IANA-reserved, unallocated,
    // or deprecated space) can route nowhere public and exists only as
    // an embedding/obfuscation surface — refuse it outright.
    if (!denied && !isV4Mapped && (raw[0] & 0xE0) != 0x20) {
      denied = true;
    }

    if (denied) {
      throw StateError(
          'Refusing to fetch non-public IPv6 address${uri != null ? ': $uri' : ''}');
    }
  }

  /// Extracts the [width]-bit window starting at [bitOffset] inside
  /// the first 64 bits of a v6 address — the region a 6rd embed can
  /// occupy (embed bit-length ≤ 32 after a ≤/32 operator prefix, all
  /// inside the delegated /64).
  static int _bitWindow(Uint8List raw, int bitOffset, int width) {
    var v = 0;
    for (var i = 0; i < width; i++) {
      final bit = bitOffset + i;
      v = (v << 1) | ((raw[bit >> 3] >> (7 - (bit & 7))) & 1);
    }
    return v;
  }

  /// Exact-match embeds refused at ANY bit offset: the cloud metadata
  /// endpoints — the single highest-value SSRF target class. These are
  /// deliberately NOT range-checked (see the 2606:4700:4700::1111
  /// collision note above); a coincidental full-32-bit match inside an
  /// honest global-unicast literal is the accepted residual, and even
  /// then the outcome is a fail-closed refusal of that one literal.
  static const List<int> _criticalMetadataEmbeds = [
    0xa9fea9fe, // 169.254.169.254 — AWS/GCP/Azure/… metadata
    0xa9fea9fd, // 169.254.169.253 — metadata variant
    0xa9feaa02, // 169.254.170.2 — AWS ECS task credentials
  ];

  /// Whether the 32-bit window at [bitOffset] is an exact
  /// metadata-endpoint embed.
  static bool _isCriticalMetadataEmbed(Uint8List raw, int bitOffset) =>
      _criticalMetadataEmbeds.contains(_bitWindow(raw, bitOffset, 32));

  /// Low-24-bit embed fingerprints of the metadata endpoints — what a
  /// 6rd relay configured with `IPv4PrefixLen = 8` leaves in the
  /// address (embed = `v4 & 0xFFFFFF`). 24 bits is the shortest window
  /// whose collision surface on ordinary global-unicast literals stays
  /// acceptably small; shorter embeds cannot be enumerated.
  static const List<int> _criticalMetadataEmbeds24 = [
    0xfea9fe, // low 24 of 169.254.169.254 — metadata
    0xfea9fd, // low 24 of 169.254.169.253 — metadata variant
    0xfeaa02, // low 24 of 169.254.170.2 — AWS ECS task credentials
  ];

  /// Whether the 24-bit window at [bitOffset] is a metadata-endpoint
  /// partial embed.
  static bool _isCriticalMetadataEmbed24(Uint8List raw, int bitOffset) =>
      _criticalMetadataEmbeds24.contains(_bitWindow(raw, bitOffset, 24));

  /// Whether the IPv4 address `[a].[b].[c].*` (first three octets)
  /// names a network a tunnelled packet could dangerously REACH:
  /// loopback, RFC-1918 private, link-local (cloud metadata!), CGNAT,
  /// and benchmarking space (routed inside some lab/org nets).
  /// Deliberately excluded: `0/8`, multicast and reserved space (no
  /// protected destination, and matching them collides with the zero
  /// windows of `::`-compressed literals), plus the documentation-only
  /// ranges (192.0.0.0/24 IETF assignments, TEST-NET-1/2/3,
  /// MCAST-TEST-NET) — a 6rd tunnel can never deliver a packet into
  /// documentation space, so flagging those windows only produced
  /// false-positives on real unicast literals (2a10:50c0::ad1).
  static bool _embeddedV4TargetsProtectedSpace(int a, int b, int c) {
    return a == 10 || // RFC-1918
        a == 127 || // loopback
        (a == 169 && b == 254) || // link-local (cloud metadata!)
        (a == 172 && b >= 16 && b <= 31) || // RFC-1918
        (a == 100 && b >= 64 && b <= 127) || // CGNAT 100.64/10
        (a == 192 && b == 168) || // RFC-1918
        (a == 198 && (b == 18 || b == 19)); // benchmarking
  }
}
