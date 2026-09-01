import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fastCdcServiceProvider = Provider((ref) => FastCdcService());

class Chunk {
  final int offset;
  final int length;
  final String hash;
  final Uint8List data;

  Chunk({
    required this.offset,
    required this.length,
    required this.hash,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'offset': offset,
        'length': length,
        'hash': hash,
      };
}

class FastCdcConfig {
  final int minSize;
  final int avgSize;
  final int maxSize;

  const FastCdcConfig({
    this.minSize = 2048, // 2 KB
    this.avgSize = 8192, // 8 KB
    this.maxSize = 32768, // 32 KB
  });
}

class FastCdcService {
  final FastCdcConfig config;

  FastCdcService({this.config = const FastCdcConfig()});

  static const List<int> _gearTable = [
    0x96041042,
    0xa1529141,
    0x19932142,
    0xa9963143,
    0x29994144,
    0xb1a95145,
    0x39b36146,
    0xb9bd7147,
    0x49c78148,
    0xc1d19149,
    0x59dba14a,
    0xc9e5b14b,
    0x69efc14c,
    0xd1f9d14d,
    0x7a03e14e,
    0xda0df14f,
    0x8a170150,
    0xe2211151,
    0x9a2b2152,
    0xea353153,
    0xaa3f4154,
    0xf2495155,
    0xba536156,
    0xfa5d7157,
    0xca678158,
    0x02719159,
    0xda7ba15a,
    0x0a85b15b,
    0xea8fc15c,
    0x1299d15d,
    0xfaa3e15e,
    0x1aadf15f,
    0x0ab70160,
    0x22c11161,
    0x1acb2162,
    0x2ad53163,
    0x2adf4164,
    0x32e95165,
    0x3af36166,
    0x3afd7167,
    0x4b078168,
    0x43119169,
    0x5b1ba16a,
    0x4b25b16b,
    0x6b2fc16c,
    0x5339d16d,
    0x7b43e16e,
    0x5b4df16f,
    0x8b570170,
    0x63611171,
    0x9b6b2172,
    0x6b753173,
    0xab7f4174,
    0x73895175,
    0xbb936176,
    0x7b9d7177,
    0xcba78178,
    0x83b19179,
    0xdbbba17a,
    0x8bc5b17b,
    0xebcfc17c,
    0x93d9d17d,
    0xfbe3e17e,
    0x9bedf17f,
    0x0bf70180,
    0xa4011181,
    0x1c0b2182,
    0xac153183,
    0x2c1f4184,
    0xb4295185,
    0x3c336186,
    0xbc3d7187,
    0x4c478188,
    0xc4519189,
    0x5c5ba18a,
    0xcc65b18b,
    0x6c6fc18c,
    0xd479d18d,
    0x7c83e18e,
    0xdc8df18f,
    0x8c970190,
    0xe4a11191,
    0x9cab2192,
    0xecb53193,
    0xacbf4194,
    0xf4c95195,
    0xbcd36196,
    0xfcdd7197,
    0xcce78198,
    0x04e19199,
    0xdcfba19a,
    0x0cf5b19b,
    0xecffc19c,
    0x1509d19d,
    0xfd13e19e,
    0x1d1df19f,
    0x0d2701a0,
    0x253111a1,
    0x1d3b21a2,
    0x2d4531a3,
    0x2d4f41a4,
    0x355951a5,
    0x3d6361a6,
    0x3d6d71a7,
    0x4d7781a8,
    0x458191a9,
    0x5d8ba1aa,
    0x4d95b1ab,
    0x6d9fc1ac,
    0x55a9d1ad,
    0x7db3e1ae,
    0x5dbdf1af,
    0x8dc701b0,
    0x65d111b1,
    0x9ddb21b2,
    0x6de531b3,
    0xadef41b4,
    0x75f951b5,
    0xbdf361b6,
    0x7bfd71b7,
    0xce0781b8,
    0x861191b9,
    0xde1ba1ba,
    0x8e25b1bb,
    0xee2fc1bc,
    0x9639d1bd,
    0xfe43e1be,
    0x9e4df1bf,
    0x0e5701c0,
    0xa66111c1,
    0x1e6b21c2,
    0xae7531c3,
    0x2e7f41c4,
    0xb68951c5,
    0x3e9361c6,
    0xbe9d71c7,
    0x4ea781c8,
    0xc6b191c9,
    0x5ebba1ca,
    0xcec5b1cb,
    0x6ecfc1cc,
    0xd6d9d1cd,
    0x7ef3e1ce,
    0xdeedf1cf,
    0x8ef701d0,
    0xe70111d1,
    0x9f0b21d2,
    0xef1531d3,
    0xaf1f41d4,
    0xf72951d5,
    0xbf3361d6,
    0xff3d71d7,
    0xcf4781d8,
    0x075191d9,
    0xdf5ba1da,
    0x0f65b1db,
    0xef6fc1dc,
    0x1779d1dd,
    0xff83e1de,
    0x1f8df1df,
    0x0f9701e0,
    0x27a111e1,
    0x1fab21e2,
    0x2fb531e3,
    0x2fbf41e4,
    0x37c951e5,
    0x3fd361e6,
    0x3fdd71e7,
    0x4fe781e8,
    0x47e191e9,
    0x5ffba1ea,
    0x4ff5b1eb,
    0x6fffc1ec,
    0x5809d1ed,
    0x8013e1ee,
    0x581df1ef,
    0x902701f0,
    0x683111f1,
    0xa03b21f2,
    0x684531f3,
    0xb04f41f4,
    0x785951f5,
    0xc06361f6,
    0x786d71f7,
    0xd07781f8,
    0x888191f9,
    0xe08ba1fa,
    0x8895b1fb,
    0xf09fc1fc,
    0x98a9d1fd,
    0x00b3e1fe,
    0x98bdf1ff,
    0x10c70100,
    0xa8d11101,
    0x20db2102,
    0xa8e53103,
    0x30ef4104,
    0xb8f95105,
    0x40f36106,
    0xb8fd7107,
    0x51078108,
    0xc9119109,
    0x611ba10a,
    0xc925b10b,
    0x712fc10c,
    0xd939d10d,
    0x8143e10e,
    0xd94df10f,
    0x91570110,
    0xe9611111,
    0xa16b2112,
    0xe9753113,
    0xb17f4114,
    0xf9895115,
    0xc1936116,
    0xf99d7117,
    0xd1a78118,
    0x09b19119,
    0xe1bba11a,
    0x09c5b11b,
    0xf1cfc11c,
    0x19d9d11d,
    0x01e3e11e,
    0x19edf11f,
    0x11f70120,
    0x2a011121,
    0x220b2122,
    0x2a153123,
    0x321f4124,
    0x3a295125,
    0x42336126,
    0x3a3d7127,
    0x52478128,
    0x4a519129,
    0x625ba12a,
    0x4a65b12b,
    0x726fc12c,
    0x5a79d12d,
    0x8283e12e,
    0x5a8df12f,
    0x92970130,
    0x6aa11131,
    0xa2ab2132,
    0x6ab53133,
    0xb2bf4134,
    0x7ac95135,
    0xc2d36136,
    0x7add7137,
    0xd2e78138,
    0x8ae19139,
    0xe2fba13a,
    0x8af5b13b,
    0xf2ffc13c,
    0x9b09d13d,
    0x0313e13e,
    0x9b1df13f,
  ];

  List<Chunk> chunk(Uint8List data) {
    if (data.isEmpty) return [];

    final chunks = <Chunk>[];
    var offset = 0;
    final totalLen = data.length;

    const maskS = 0x0000DFFF; // Normalization mask for [min, avg]
    const maskL = 0x00000FFF; // Normalization mask for [avg, max]

    while (offset < totalLen) {
      if (totalLen - offset <= config.minSize) {
        final chunkData = data.sublist(offset);
        chunks.add(Chunk(
          offset: offset,
          length: chunkData.length,
          hash: sha256.convert(chunkData).toString(),
          data: chunkData,
        ));
        break;
      }

      var fingerPrint = 0;
      var len = config.minSize;
      final maxLen = (totalLen - offset < config.maxSize)
          ? (totalLen - offset)
          : config.maxSize;
      final avgLen = (totalLen - offset < config.avgSize)
          ? (totalLen - offset)
          : config.avgSize;

      // Small region: [min, avg]
      while (len < avgLen) {
        final byte = data[offset + len];
        fingerPrint = ((fingerPrint << 1) + _gearTable[byte]) & 0xFFFFFFFF;
        if ((fingerPrint & maskS) == 0) {
          break;
        }
        len++;
      }

      // Large region: [avg, max]
      if ((fingerPrint & maskS) != 0) {
        while (len < maxLen) {
          final byte = data[offset + len];
          fingerPrint = ((fingerPrint << 1) + _gearTable[byte]) & 0xFFFFFFFF;
          if ((fingerPrint & maskL) == 0) {
            break;
          }
          len++;
        }
      }

      final chunkData = data.sublist(offset, offset + len);
      chunks.add(Chunk(
        offset: offset,
        length: len,
        hash: sha256.convert(chunkData).toString(),
        data: chunkData,
      ));

      offset += len;
    }

    return chunks;
  }
}
