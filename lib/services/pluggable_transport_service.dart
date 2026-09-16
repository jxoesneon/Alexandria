import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pluggableTransportServiceProvider =
    Provider((ref) => PluggableTransportService());

enum ObfuscationProfile {
  none,
  tlsCamouflage,
  shadowsocksAead,
  obfs4Entropy,
}

class PluggableTransportService {
  ObfuscationProfile _currentProfile = ObfuscationProfile.tlsCamouflage;

  /// Pre-shared key for the [ObfuscationProfile.shadowsocksAead] profile.
  /// When the caller supplies none, a random per-session key is generated —
  /// frames can then only be deobfuscated by THIS service instance, which
  /// is the safe default: a keyed profile must never fall back to a
  /// publicly-known "key" (round-2 red finding: the previous profile had
  /// no key material at all and XORed with a cleartext salt).
  final Uint8List _preSharedKey;

  PluggableTransportService({Uint8List? preSharedKey})
      : _preSharedKey = preSharedKey ?? _randomBytes(32);

  /// Generates a fresh random session key — the correct key to share with
  /// a peer when configuring this profile out-of-band.
  static Uint8List generatePreSharedKey() => _randomBytes(32);

  static Uint8List _randomBytes(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
  }

  ObfuscationProfile get currentProfile => _currentProfile;

  void setProfile(ObfuscationProfile profile) {
    _currentProfile = profile;
  }

  Uint8List obfuscate(Uint8List payload) {
    switch (_currentProfile) {
      case ObfuscationProfile.none:
        return payload;
      case ObfuscationProfile.tlsCamouflage:
        return _applyTlsCamouflage(payload);
      case ObfuscationProfile.shadowsocksAead:
        return _applyShadowsocksAead(payload);
      case ObfuscationProfile.obfs4Entropy:
        return _applyObfs4Entropy(payload);
    }
  }

  Uint8List deobfuscate(Uint8List obfuscated) {
    switch (_currentProfile) {
      case ObfuscationProfile.none:
        return obfuscated;
      case ObfuscationProfile.tlsCamouflage:
        return _removeTlsCamouflage(obfuscated);
      case ObfuscationProfile.shadowsocksAead:
        return _removeShadowsocksAead(obfuscated);
      case ObfuscationProfile.obfs4Entropy:
        return _removeObfs4Entropy(obfuscated);
    }
  }

  // --- TLS 1.3 Application Data Record Camouflage ---
  Uint8List _applyTlsCamouflage(Uint8List data) {
    final builder = BytesBuilder();
    builder.addByte(0x17); // ContentType: Application Data
    builder.addByte(0x03); // Legacy Version Major: TLS 1.2
    builder
        .addByte(0x03); // Legacy Version Minor: TLS 1.3 handshake compatibility
    final length = data.length;
    builder.addByte((length >> 8) & 0xFF);
    builder.addByte(length & 0xFF);
    builder.add(data);
    return builder.toBytes();
  }

  Uint8List _removeTlsCamouflage(Uint8List data) {
    if (data.length < 5) {
      throw const FormatException('Truncated TLS camouflage record');
    }
    if (data[0] != 0x17 || data[1] != 0x03 || data[2] != 0x03) {
      throw const FormatException('Invalid TLS camouflage header');
    }
    final length = (data[3] << 8) | data[4];
    // Reject BOTH truncation and trailing bytes (round-2 red finding):
    // silently discarding a tail lets a MITM splice extra bytes into the
    // stream undetectably.
    if (data.length != 5 + length) {
      throw const FormatException('TLS payload length mismatch');
    }
    return data.sublist(5, 5 + length);
  }

  // --- Shadowsocks AEAD Masking ---
  //
  // Real AEAD semantics (round-2 red finding): the wire format is
  //   salt(16) ‖ mask
  //   mask  = armor XOR salt(repeating)          — cosmetic obfuscation
  //   armor = base64( nonce(16) ‖ ct ‖ tag(32) ) — transport-safe frame
  // where a session subkey is derived from the pre-shared key and the
  // random salt via HKDF-SHA256 (per Shadowsocks AEAD's "ss-subkey"),
  // the keystream is HMAC-SHA256(subkey, "enc" ‖ nonce ‖ counter) — a
  // keyed stream a passive observer cannot reconstruct — and `tag` is
  // HMAC-SHA256 over salt‖nonce‖ciphertext, verified before any
  // plaintext is released. The salt-mask+armor layer only randomizes
  // the wire appearance: an observer who unmasks it gets base64 of an
  // authenticated ciphertext, never plaintext. Tampered or keyless
  // input is REJECTED.
  static const int _ssSaltLen = 16;
  static const int _ssNonceLen = 16;
  static const int _ssTagLen = 32;

  static Uint8List _hmacSha256(List<int> key, List<int> msg) =>
      Uint8List.fromList(Hmac(sha256, key).convert(msg).bytes);

  /// HKDF-SHA256 (RFC 5869 extract+expand, single-block output).
  static Uint8List _hkdfSha256({
    required List<int> salt,
    required List<int> ikm,
    required List<int> info,
    int length = 32,
  }) {
    final prk = _hmacSha256(salt, ikm);
    final out = BytesBuilder();
    var t = <int>[];
    var counter = 1;
    while (out.length < length) {
      t = _hmacSha256(prk, [...t, ...info, counter]);
      out.add(t);
      counter++;
    }
    return Uint8List.fromList(out.toBytes().sublist(0, length));
  }

  Uint8List _ssSubkey(Uint8List salt) => _hkdfSha256(
        salt: salt,
        ikm: _preSharedKey,
        info: 'ss-subkey'.codeUnits,
      );

  /// Keystream block for [blockIndex] under [subkey]/[nonce].
  static Uint8List _ssKeystreamBlock(
      Uint8List subkey, Uint8List nonce, int blockIndex) {
    final ctr = ByteData(8)..setUint64(0, blockIndex);
    return _hmacSha256(subkey, [
      ...'enc'.codeUnits,
      ...nonce,
      ...ctr.buffer.asUint8List(),
    ]);
  }

  /// XORs [data] with [key] repeated — used for the cosmetic armor mask
  /// AND as the keyed keystream step (with an HMAC-derived stream).
  static Uint8List _ssXorRepeat(Uint8List data, List<int> key) {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] ^ key[i % key.length];
    }
    return out;
  }

  static Uint8List _ssXorKeystream(
      Uint8List data, Uint8List subkey, Uint8List nonce) {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i += 32) {
      final ks = _ssKeystreamBlock(subkey, nonce, i ~/ 32);
      final end = (i + 32 > data.length) ? data.length : i + 32;
      for (var j = i; j < end; j++) {
        out[j] = data[j] ^ ks[j - i];
      }
    }
    return out;
  }

  Uint8List _applyShadowsocksAead(Uint8List data) {
    final salt = _randomBytes(_ssSaltLen);
    final nonce = _randomBytes(_ssNonceLen);
    final subkey = _ssSubkey(salt);

    final ciphertext = _ssXorKeystream(data, subkey, nonce);
    final tag = _hmacSha256(subkey,
        [...'mac'.codeUnits, ...salt, ...nonce, ...ciphertext]);

    // Inner frame (binary): nonce ‖ ciphertext ‖ tag. Armored as base64
    // so the frame is transport-safe, then masked by the salt so the
    // wire still looks uniformly random. The mask is reversible by
    // anyone holding the wire — but unmasking yields only an
    // AUTHENTICATED CIPHERTEXT, never plaintext.
    final frame = (BytesBuilder()
          ..add(nonce)
          ..add(ciphertext)
          ..add(tag))
        .toBytes();
    final armor = Uint8List.fromList(utf8.encode(base64Encode(frame)));
    final masked = _ssXorRepeat(armor, salt);

    return (BytesBuilder()
          ..add(salt)
          ..add(masked))
        .toBytes();
  }

  Uint8List _removeShadowsocksAead(Uint8List data) {
    if (data.length <= _ssSaltLen) {
      throw const FormatException('Truncated Shadowsocks AEAD payload');
    }
    final salt = Uint8List.fromList(data.sublist(0, _ssSaltLen));
    final armor = _ssXorRepeat(
        Uint8List.fromList(data.sublist(_ssSaltLen)), salt);

    // The armor must be strict base64 and the frame must be long enough
    // to hold nonce‖tag — anything else is forged input (both decode
    // steps throw FormatException on malformed data).
    final frame = base64Decode(utf8.decode(armor));
    if (frame.length < _ssNonceLen + _ssTagLen) {
      throw const FormatException('Truncated Shadowsocks AEAD frame');
    }
    final nonce = Uint8List.fromList(frame.sublist(0, _ssNonceLen));
    final ciphertext = Uint8List.fromList(
        frame.sublist(_ssNonceLen, frame.length - _ssTagLen));
    final tag = frame.sublist(frame.length - _ssTagLen);

    final subkey = _ssSubkey(salt);
    final expected = _hmacSha256(subkey,
        [...'mac'.codeUnits, ...salt, ...nonce, ...ciphertext]);

    // Constant-time tag comparison: a mismatch means tampered (or
    // wrong-key) input and MUST be rejected before releasing plaintext.
    var diff = 0;
    for (var i = 0; i < _ssTagLen; i++) {
      diff |= tag[i] ^ expected[i];
    }
    if (diff != 0) {
      throw const FormatException(
          'Shadowsocks AEAD tag mismatch — tampered ciphertext');
    }

    return _ssXorKeystream(ciphertext, subkey, nonce);
  }

  // --- Obfs4 Random Entropy Padding ---
  Uint8List _applyObfs4Entropy(Uint8List data) {
    final rnd = Random.secure();
    final padLen = rnd.nextInt(32) + 1;
    final padding =
        Uint8List.fromList(List.generate(padLen, (_) => rnd.nextInt(256)));
    final builder = BytesBuilder();
    builder.addByte(padLen);
    builder.add(padding);
    builder.add(data);
    return builder.toBytes();
  }

  Uint8List _removeObfs4Entropy(Uint8List data) {
    if (data.isEmpty) throw const FormatException('Empty obfs4 payload');
    final padLen = data[0];
    if (data.length < 1 + padLen) {
      throw const FormatException('Truncated obfs4 frame');
    }
    return data.sublist(1 + padLen);
  }
}
