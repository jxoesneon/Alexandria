import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'identity_service.dart' show AlexandriaIdentity, IdentityService;

final encryptionServiceProvider = Provider((ref) => EncryptionService());

class EncryptionService {
  final AesGcm _algorithm = AesGcm.with256bits();
  final X25519 _x25519 = X25519();

  /// Wire version for peer-envelope ciphertexts produced by
  /// [encryptForPeer] / consumed by [decryptFromPeer].
  static const int peerEnvelopeVersion = 1;

  /// (round-6 red finding) Wire version for envelopes carrying several
  /// AEAD boxes — one per plausible interpretation of an ambiguous peer
  /// key (see [_resolvePeerAgreementKeyCandidates]). Layout:
  /// `version(1) ‖ ephemeralX25519Pub(32) ‖ boxCount(1) ‖ box × count`
  /// where every box is `nonce ‖ ciphertext ‖ tag` over the SAME
  /// plaintext and therefore has identical length.
  static const int peerEnvelopeVersionMulti = 2;

  Future<SecretKey> generateKey() async {
    return await _algorithm.newSecretKey();
  }

  Future<List<int>> keyToBytes(SecretKey key) async {
    return await key.extractBytes();
  }

  Future<SecretKey> keyFromBytes(List<int> bytes) async {
    return SecretKey(bytes);
  }

  Future<Uint8List> encryptData(Uint8List plaintext, SecretKey key) async {
    final secretBox = await _algorithm.encrypt(plaintext, secretKey: key);
    return Uint8List.fromList(secretBox.concatenation());
  }

  /// Decrypts an [encryptData] SecretBox. Returns null — rather than
  /// throwing — whenever the box is malformed or the MAC fails (wrong
  /// key, tampered ciphertext, or a ciphertext that was never a plain
  /// SecretBox, e.g. an [encryptForPeer] envelope probed with a
  /// public-derived key). Callers needing a hard failure should throw on
  /// the null result themselves.
  Future<Uint8List?> decryptData(Uint8List cipherData, SecretKey key) async {
    try {
      final secretBox = SecretBox.fromConcatenation(
        cipherData,
        nonceLength: _algorithm.nonceLength,
        macLength: _algorithm.macAlgorithm.macLength,
      );
      final decrypted = await _algorithm.decrypt(secretBox, secretKey: key);
      return Uint8List.fromList(decrypted);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Peer-addressed encryption (round-2 red finding)
  //
  // The previous implementation derived the AES key as
  // sha256(utf8(peerPublicKey)) — a deterministic function of a PUBLIC
  // string, so every observer could decrypt. This is now real ECIES:
  // an ephemeral X25519 keypair agrees with the recipient's X25519
  // public key, the shared secret is HKDF-SHA256'd into an AES-256-GCM
  // key bound to both public keys, and the envelope carries the
  // ephemeral public key so only the holder of the recipient's PRIVATE
  // key can recompute the shared secret.
  // ─────────────────────────────────────────────────────────────────

  /// Encrypts [data] so that only the holder of the private key matching
  /// [peerPublicKey] can decrypt it.
  ///
  /// [peerPublicKey] is a Base58/Base64/hex-encoded 32-byte key in one of
  /// the two spellings Alexandria uses:
  ///   * an Ed25519 identity public key (mapped to the birationally
  ///     equivalent X25519 Montgomery u-coordinate), or
  ///   * a raw X25519 u-coordinate — the bytes returned by
  ///     [IdentityService.x25519PublicKeyBytes] (round-3 red finding:
  ///     the previous code mapped EVERY 32-byte input as Ed25519, so a
  ///     raw u-coordinate was double-mapped and never agreed with the
  ///     advertised private key).
  ///
  /// (round-6 red finding) Key-type resolution is EXPLICIT — callers
  /// should prefix the encoded key with `ed25519:` or `x25519:` to pin
  /// the interpretation. An UNTAGGED 32-byte input that parses as a
  /// canonical Ed25519 point is genuinely ambiguous — ~50% of real
  /// X25519 u-coordinates also parse as valid Edwards encodings, so
  /// guessing either way silently seals the envelope to a point whose
  /// private key nobody holds. For an ambiguous input this method
  /// therefore emits a version-2 envelope carrying one AEAD box per
  /// candidate point (raw u AND mapped u); [decryptFromPeer] opens
  /// whichever box was sealed to the recipient's actual public key.
  /// Nothing is ever sealed to only a guessed interpretation.
  ///
  /// Undecodable or non-contributory identifiers are domain-separated-
  /// hashed into a u-coordinate: the resulting ciphertext is still
  /// confidential — an eavesdropper cannot derive the shared secret —
  /// but it is effectively sealed, since no private key is known to
  /// correspond to the mapped point. Callers should always pass the
  /// peer's real encoded key.
  ///
  /// Envelopes: v1 `version(1) ‖ ephemeralX25519Pub(32) ‖ nonce ‖ ct ‖
  /// tag`; v2 `version(1) ‖ ephemeralPub(32) ‖ boxCount(1) ‖ box×count`.
  Future<Uint8List> encryptForPeer(Uint8List data, String peerPublicKey) async {
    final candidates = _resolvePeerAgreementKeyCandidates(peerPublicKey);
    final ephemeral = await _x25519.newKeyPair();
    final ephemeralPub = await ephemeral.extractPublicKey();
    final ephemeralPubBytes = Uint8List.fromList(ephemeralPub.bytes);

    final boxes = <Uint8List>[];
    for (final peerU in candidates) {
      var shared = await _x25519.sharedSecretKey(
        keyPair: ephemeral,
        remotePublicKey: SimplePublicKey(peerU, type: KeyPairType.x25519),
      );

      // (round-3 red finding) contributory-behaviour check: if a
      // low-order peer input slipped past the blocklist, X25519 yields
      // an all-zero secret that an eavesdropper can reproduce without
      // any private key. A zero secret must never reach the AEAD layer —
      // seal the payload to an unreachable key instead of throwing, so
      // a hostile peer key can never turn encryption into a public
      // broadcast.
      var sharedBytes = Uint8List.fromList(await shared.extractBytes());
      if (_isAllZero(sharedBytes)) {
        // (round-4 latent finding) the substitute secret must be keyed
        // with the ephemeral PRIVATE material — the previous fallback
        // hashed only public input (the peer key), so ANY observer could
        // recompute the "unreachable" key and decrypt the envelope.
        // Ephemeral private bytes never leave this call, so no one —
        // including the recipient — can recompute this seal.
        final ephemeralPrivate =
            Uint8List.fromList((await ephemeral.extract()).bytes);
        sharedBytes = Uint8List.fromList(crypto.sha256.convert([
          ...utf8.encode('alexandria:x25519-non-contributory:v2'),
          ...ephemeralPrivate,
          ...peerU,
        ]).bytes);
        shared = SecretKey(sharedBytes);
      }

      final aeadKey = await _derivePeerAeadKey(
        shared,
        ephemeralPubBytes: ephemeralPubBytes,
        peerPubBytes: peerU,
      );
      final box = await _algorithm.encrypt(data, secretKey: aeadKey);
      boxes.add(Uint8List.fromList(box.concatenation()));
    }

    final out = BytesBuilder();
    if (boxes.length == 1) {
      // Unambiguous (or sealed-fallback) single-recipient envelope.
      out
        ..addByte(peerEnvelopeVersion)
        ..add(ephemeralPubBytes)
        ..add(boxes.single);
    } else {
      // (round-6 red finding) ambiguous peer key — one box per
      // candidate agreement point so the recipient opens whichever
      // interpretation matches their advertised key.
      out
        ..addByte(peerEnvelopeVersionMulti)
        ..add(ephemeralPubBytes)
        ..addByte(boxes.length);
      for (final box in boxes) {
        out.add(box);
      }
    }
    return out.toBytes();
  }

  /// Decrypts an [encryptForPeer] envelope using the recipient's X25519
  /// private key (see [ed25519SeedToX25519Seed] for deriving it from an
  /// Ed25519 identity seed, and [IdentityService.x25519PrivateKeyBytes]).
  Future<Uint8List> decryptFromPeer(
    Uint8List envelope,
    Uint8List agreementPrivateKey,
  ) async {
    const headerLen = 1 + 32;
    final minLen =
        headerLen + _algorithm.nonceLength + _algorithm.macAlgorithm.macLength;
    if (envelope.length < minLen) {
      throw const FormatException('Truncated peer-encryption envelope');
    }

    // (round-6 red finding) v2 envelopes carry `count` equal-length AEAD
    // boxes, one per candidate interpretation of an ambiguous peer key.
    // All boxes share the ephemeral key and the recipient's agreement
    // key, so exactly the box whose salt bound our real public key
    // authenticates — the others are ignored.
    final version = envelope[0];
    List<Uint8List> boxes;
    if (version == peerEnvelopeVersion) {
      boxes = [Uint8List.fromList(envelope.sublist(headerLen))];
    } else if (version == peerEnvelopeVersionMulti) {
      if (envelope.length < headerLen + 1) {
        throw const FormatException('Truncated peer-encryption envelope');
      }
      final count = envelope[headerLen];
      final payload = envelope.sublist(headerLen + 1);
      if (count < 2 ||
          payload.length % count != 0 ||
          payload.length ~/ count <
              _algorithm.nonceLength + _algorithm.macAlgorithm.macLength) {
        throw const FormatException(
            'Malformed multi-box peer-encryption envelope');
      }
      final boxLen = payload.length ~/ count;
      boxes = [
        for (var i = 0; i < count; i++)
          Uint8List.fromList(payload.sublist(i * boxLen, (i + 1) * boxLen)),
      ];
    } else {
      throw const FormatException('Unsupported peer-encryption version');
    }
    final ephemeralPub = Uint8List.fromList(envelope.sublist(1, headerLen));

    // (round-3 red finding) a low-order ephemeral key forces an all-zero
    // shared secret — refuse to even run the agreement rather than
    // produce a universally-decryptable envelope.
    if (_isLowOrderX25519Input(ephemeralPub)) {
      throw const FormatException(
          'Peer envelope carries a non-contributory ephemeral key');
    }

    final keyPair = await _x25519.newKeyPairFromSeed(agreementPrivateKey);
    final myPub = Uint8List.fromList((await keyPair.extractPublicKey()).bytes);
    final shared = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(ephemeralPub, type: KeyPairType.x25519),
    );

    // Defence in depth: any low-order input not on the blocklist still
    // collapses to the all-zero secret — reject it outright.
    if (_isAllZero(Uint8List.fromList(await shared.extractBytes()))) {
      throw const FormatException(
          'Peer envelope produced a non-contributory shared secret');
    }

    // Salt order must mirror encryptForPeer: ephemeral ‖ recipient pub.
    final aeadKey = await _derivePeerAeadKey(
      shared,
      ephemeralPubBytes: ephemeralPub,
      peerPubBytes: myPub,
    );

    // Try each box: only the one sealed to OUR agreement point
    // authenticates. On total failure surface the AEAD error, matching
    // the v1 contract (tampered → authentication error).
    Object? lastError;
    for (final boxBytes in boxes) {
      final box = SecretBox.fromConcatenation(
        boxBytes,
        nonceLength: _algorithm.nonceLength,
        macLength: _algorithm.macAlgorithm.macLength,
      );
      try {
        final plain = await _algorithm.decrypt(box, secretKey: aeadKey);
        return Uint8List.fromList(plain);
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    throw const FormatException('No peer-envelope box authenticated');
  }

  Future<SecretKey> _derivePeerAeadKey(
    SecretKey shared, {
    required Uint8List ephemeralPubBytes,
    required Uint8List peerPubBytes,
  }) {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    // Both public keys in the salt bind the AEAD key to this exact
    // ephemeral/recipient pair (key-commitment against confused-deputy
    // forwarding of envelopes between recipients).
    final salt = BytesBuilder()
      ..add(ephemeralPubBytes)
      ..add(peerPubBytes);
    return hkdf.deriveKey(
      secretKey: shared,
      nonce: salt.toBytes(),
      info: utf8.encode('alexandria:peer-e2e:v1'),
    );
  }

  /// Resolves [peerPublicKey] to the set of candidate 32-byte X25519
  /// Montgomery u-coordinates the envelope is sealed to.
  ///
  /// Accepts Base58 (the [AlexandriaIdentity.publicKeyBase58] spelling),
  /// Base64, or hex encodings. (round-6 red finding) The key-type
  /// resolution is EXPLICIT: an `ed25519:` prefix forces the
  /// Edwards→Montgomery birational map, an `x25519:` prefix forces the
  /// raw u-coordinate interpretation, and an untagged input that parses
  /// as a canonical Ed25519 point yields BOTH candidates — the birational
  /// map means ~50% of real Montgomery u-coordinates also parse as valid
  /// Edwards encodings, so picking one interpretation (~the previous
  /// `_isCanonicalEd25519Key` guess) silently sealed ~half of all
  /// advertised `x25519PublicKeyBytes` values to a point whose private
  /// key nobody holds. [encryptForPeer] emits one box per candidate so
  /// the recipient always opens the box sealed to their actual key.
  ///
  /// Every candidate is checked against the low-order blocklist — a
  /// low-order input (e.g. compressed y = −1, which maps to u = 0) is
  /// refused by sealing to an unreachable hash-derived point, exactly
  /// like an undecodable identifier: fail-closed, never fail-public.
  List<Uint8List> _resolvePeerAgreementKeyCandidates(String peerPublicKey) {
    var key = peerPublicKey.trim();
    // Explicit key-type tags — the unambiguous contract.
    bool? edOnly; // null = untagged, both interpretations allowed
    if (key.startsWith('ed25519:')) {
      edOnly = true;
      key = key.substring('ed25519:'.length);
    } else if (key.startsWith('x25519:')) {
      edOnly = false;
      key = key.substring('x25519:'.length);
    }

    final raw = _decodeKeyMaterial(key);
    if (raw == null || raw.length != 32) {
      return [_sealedU(peerPublicKey)];
    }

    final candidates = <Uint8List>[];
    if (edOnly != false && _isCanonicalEd25519Key(raw)) {
      try {
        final mapped = ed25519PublicToX25519(raw);
        if (!_isLowOrderX25519Input(mapped)) candidates.add(mapped);
      } catch (_) {
        // e.g. the Edwards identity (y = 1) has no Montgomery image.
      }
    }
    if (edOnly != true &&
        !_isLowOrderX25519Input(raw) &&
        !candidates.any((u) => _bytesEqual(u, raw))) {
      candidates.add(raw);
    }
    if (candidates.isEmpty) return [_sealedU(peerPublicKey)];
    return candidates;
  }

  /// Domain-separated hash of an identifier into a u-coordinate — a
  /// ciphertext sealed to this point is confidential but has no known
  /// private key.
  Uint8List _sealedU(String peerPublicKey) {
    return Uint8List.fromList(crypto.sha256
        .convert(utf8.encode('alexandria:x25519-unresolvable-peer:v1:'
            '$peerPublicKey'))
        .bytes);
  }

  static bool _isAllZero(Uint8List bytes) {
    var acc = 0;
    for (final b in bytes) {
      acc |= b;
    }
    return acc == 0;
  }

  /// libsodium-compatible list of X25519 public inputs that produce a
  /// non-contributory (all-zero) shared secret: the order-1, -2, -4 and
  /// -8 Montgomery points, in both canonical form and the +2²⁵⁵
  /// non-canonical encodings (round-3 red finding).
  static const List<List<int>> _x25519LowOrderBlocklist = [
    // 0 (order 4)
    [
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ],
    // 1 (order 1)
    [
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ],
    // order-8 point
    [
      0xe0,
      0xeb,
      0x7a,
      0x7c,
      0x3b,
      0x41,
      0xb8,
      0xae,
      0x16,
      0x56,
      0xe3,
      0xfa,
      0xf1,
      0x9f,
      0xc4,
      0x6a,
      0xda,
      0x09,
      0x8d,
      0xeb,
      0x9c,
      0x32,
      0xb1,
      0xfd,
      0x86,
      0x62,
      0x05,
      0x16,
      0x5f,
      0x49,
      0xb8,
      0x00
    ],
    // order-8 point
    [
      0x5f,
      0x9c,
      0x95,
      0xbc,
      0xa3,
      0x50,
      0x8c,
      0x24,
      0xb1,
      0xd0,
      0xb1,
      0x55,
      0x9c,
      0x83,
      0xef,
      0x5b,
      0x04,
      0x44,
      0x5c,
      0x39,
      0x15,
      0x8b,
      0x4e,
      0x1e,
      0x9a,
      0x4f,
      0x04,
      0xb4,
      0xe0,
      0xce,
      0x5e,
      0x39
    ],
    // p−1 (order 2)
    [
      0xec,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0x7f
    ],
    // p (=0, order 4)
    [
      0xed,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0x7f
    ],
    // p+1 (=1, order 1)
    [
      0xee,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0x7f
    ],
    // order-8 point, non-canonical (+2²⁵⁵)
    [
      0xcd,
      0xeb,
      0x7a,
      0x7c,
      0x3b,
      0x41,
      0xb8,
      0xae,
      0x16,
      0x56,
      0xe3,
      0xfa,
      0xf1,
      0x9f,
      0xc4,
      0x6a,
      0xda,
      0x09,
      0x8d,
      0xeb,
      0x9c,
      0x32,
      0xb1,
      0xfd,
      0x86,
      0x62,
      0x05,
      0x16,
      0x5f,
      0x49,
      0xb8,
      0x80
    ],
    // order-8 point, non-canonical (+2²⁵⁵)
    [
      0x4c,
      0x9c,
      0x95,
      0xbc,
      0xa3,
      0x50,
      0x8c,
      0x24,
      0xb1,
      0xd0,
      0xb1,
      0x55,
      0x9c,
      0x83,
      0xef,
      0x5b,
      0x04,
      0x44,
      0x5c,
      0x39,
      0x15,
      0x8b,
      0x4e,
      0x1e,
      0x9a,
      0x4f,
      0x04,
      0xb4,
      0xe0,
      0xce,
      0x5e,
      0xb9
    ],
    // p−1, non-canonical (+2²⁵⁵)
    [
      0xd9,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff
    ],
    // p, non-canonical (+2²⁵⁵)
    [
      0xda,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff
    ],
    // p+1, non-canonical (+2²⁵⁵)
    [
      0xdb,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff
    ],
  ];

  /// True when [u] (a 32-byte Montgomery u-coordinate, raw or masked)
  /// is a known non-contributory X25519 input.
  static bool _isLowOrderX25519Input(Uint8List u) {
    if (u.length != 32) return true; // not even a u-coordinate — refuse
    final masked = Uint8List.fromList(u)..[31] &= 0x7F;
    for (final entry in _x25519LowOrderBlocklist) {
      if (_bytesEqual(u, entry) || _bytesEqual(masked, entry)) return true;
    }
    return false;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Whether [bytes] is a canonical Ed25519 public-key encoding:
  /// little-endian y < p with the sign bit in the top bit, such that the
  /// curve equation x² = (y²−1)/(dy²+1) has a solution (i.e. the
  /// candidate is a quadratic residue). Used ONLY to disambiguate the
  /// two accepted 32-byte key spellings — never as a security boundary.
  static bool _isCanonicalEd25519Key(Uint8List bytes) {
    if (bytes.length != 32) return false;
    final p = BigInt.two.pow(255) - BigInt.from(19);
    final d = BigInt.parse(
        '37095705934669439343138083508754565189542113879843219016388785533085940283555');
    final yBytes = Uint8List.fromList(bytes)..[31] &= 0x7F;
    var y = BigInt.zero;
    for (var i = 31; i >= 0; i--) {
      y = (y << 8) | BigInt.from(yBytes[i]);
    }
    if (y >= p) return false; // non-canonical — not an Ed25519 key
    final y2 = (y * y) % p;
    final denominator = (d * y2 + BigInt.one) % p;
    if (denominator == BigInt.zero) return false;
    final v = ((y2 - BigInt.one) * denominator.modInverse(p)) % p;
    if (v == BigInt.zero) return true; // x = 0 always a square
    // Euler criterion: v is a quadratic residue iff v^((p−1)/2) ≡ 1.
    return v.modPow((p - BigInt.one) ~/ BigInt.two, p) == BigInt.one;
  }

  /// Best-effort decode of a key string across the encodings Alexandria
  /// uses on the wire. Returns null when nothing yields 32 bytes.
  Uint8List? _decodeKeyMaterial(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return null;
    // Hex (64 chars)
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmed)) {
      final out = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        out[i] = int.parse(trimmed.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return out;
    }
    // Base58 (Alexandria identity spelling)
    try {
      final decoded = AlexandriaIdentity.decodePublicKeyBase58(trimmed);
      if (decoded.length == 32) return decoded;
    } catch (_) {}
    // Base64
    try {
      final decoded = base64Decode(trimmed);
      if (decoded.length == 32) return decoded;
    } catch (_) {}
    return null;
  }

  /// Maps an Ed25519 public key to the Montgomery-form X25519 u-coordinate
  /// (u = (1 + y) / (1 − y) mod 2²⁵⁵−19), the standard conversion used by
  /// libsodium's crypto_sign_ed25519_pk_to_curve25519.
  static Uint8List ed25519PublicToX25519(Uint8List ed25519PublicKey) {
    if (ed25519PublicKey.length != 32) {
      throw ArgumentError('Ed25519 public key must be 32 bytes');
    }
    final p = BigInt.two.pow(255) - BigInt.from(19);
    // Clear the sign bit of the Edwards x-coordinate stored in the top
    // bit; y is the little-endian value of the remaining 255 bits.
    final yBytes = Uint8List.fromList(ed25519PublicKey);
    yBytes[31] &= 0x7F;
    var y = BigInt.zero;
    for (var i = 31; i >= 0; i--) {
      y = (y << 8) | BigInt.from(yBytes[i]);
    }
    final one = BigInt.one;
    final u = ((one + y) * (one - y).modInverse(p)) % p;
    final out = Uint8List(32);
    var v = u;
    for (var i = 0; i < 32; i++) {
      out[i] = (v & BigInt.from(0xFF)).toInt();
      v = v >> 8;
    }
    return out;
  }

  /// Converts an Ed25519 private seed to the corresponding X25519 private
  /// key: the clamped first half of SHA-512(seed) (libsodium's
  /// crypto_sign_ed25519_sk_to_curve25519 semantics — X25519 applies the
  /// clamp during scalar multiplication, so the unclamped half is passed).
  static Uint8List ed25519SeedToX25519Seed(Uint8List ed25519Seed) {
    if (ed25519Seed.length != 32) {
      throw ArgumentError('Ed25519 seed must be 32 bytes');
    }
    final h = crypto.sha512.convert(ed25519Seed).bytes;
    return Uint8List.fromList(h.sublist(0, 32));
  }
}
