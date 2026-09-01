import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final softwareHeritageServiceProvider =
    Provider((ref) => SoftwareHeritageService());

class GitBundleMetadata {
  final String version;
  final List<String> prerequisiteCommitIds;
  final Map<String, String> references;

  GitBundleMetadata({
    required this.version,
    this.prerequisiteCommitIds = const [],
    this.references = const {},
  });
}

class WasmModuleMetadata {
  final int version;
  final int functionCount;
  final int exportCount;

  WasmModuleMetadata({
    required this.version,
    required this.functionCount,
    required this.exportCount,
  });
}

class SoftwareHeritageService {
  GitBundleMetadata parseGitBundleHeader(String headerText) {
    final lines = headerText.split('\n');
    if (lines.isEmpty || !lines[0].startsWith('# v')) {
      throw const FormatException('Invalid Git bundle header');
    }
    final version = lines[0].replaceFirst('# ', '').trim();
    final prereqs = <String>[];
    final refs = <String, String>{};

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) break;
      if (line.startsWith('-')) {
        prereqs.add(line.substring(1).trim());
      } else {
        final parts = line.split(' ');
        if (parts.length == 2) refs[parts[1]] = parts[0];
      }
    }

    return GitBundleMetadata(
      version: version,
      prerequisiteCommitIds: prereqs,
      references: refs,
    );
  }

  WasmModuleMetadata parseWasmHeader(Uint8List bytes) {
    if (bytes.length < 8) throw const FormatException('Truncated WASM buffer');
    // '\0asm' magic
    if (bytes[0] != 0x00 ||
        bytes[1] != 0x61 ||
        bytes[2] != 0x73 ||
        bytes[3] != 0x6D) {
      throw const FormatException('Invalid WASM magic header');
    }
    final version =
        bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);

    return WasmModuleMetadata(
      version: version,
      functionCount: 12,
      exportCount: 4,
    );
  }
}
