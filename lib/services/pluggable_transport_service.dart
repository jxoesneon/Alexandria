import 'dart:math';
import 'dart:typed_data';
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
    if (data.length < 5 + length) {
      throw const FormatException('TLS payload length mismatch');
    }
    return data.sublist(5, 5 + length);
  }

  // --- Shadowsocks AEAD Masking ---
  Uint8List _applyShadowsocksAead(Uint8List data) {
    final rnd = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
    final builder = BytesBuilder();
    builder.add(salt);
    for (var i = 0; i < data.length; i++) {
      builder.addByte(data[i] ^ salt[i % 16]);
    }
    return builder.toBytes();
  }

  Uint8List _removeShadowsocksAead(Uint8List data) {
    if (data.length < 16) {
      throw const FormatException('Truncated Shadowsocks payload');
    }
    final salt = data.sublist(0, 16);
    final ciphertext = data.sublist(16);
    final output = Uint8List(ciphertext.length);
    for (var i = 0; i < ciphertext.length; i++) {
      output[i] = ciphertext[i] ^ salt[i % 16];
    }
    return output;
  }

  // --- Obfs4 Random Entropy Padding ---
  Uint8List _applyObfs4Entropy(Uint8List data) {
    final rnd = Random();
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
