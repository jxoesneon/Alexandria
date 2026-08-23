import 'package:flutter_riverpod/flutter_riverpod.dart';

final hardwareSchematicsServiceProvider = Provider((ref) => HardwareSchematicsService());

class KiCadSchematicMetadata {
  final String? title;
  final String? revision;
  final String? company;
  final List<String> components;

  KiCadSchematicMetadata({
    this.title,
    this.revision,
    this.company,
    this.components = const [],
  });
}

class HardwareSchematicsService {
  KiCadSchematicMetadata parseKiCadSchematic(String source) {
    final titleMatch = RegExp(r'\(title\s+"([^"]+)"\)').firstMatch(source);
    final revMatch = RegExp(r'\(rev\s+"([^"]+)"\)').firstMatch(source);
    final compMatch = RegExp(r'\(company\s+"([^"]+)"\)').firstMatch(source);

    final symbolMatches = RegExp(r'\(symbol\s+"([^"]+)"').allMatches(source);
    final components = symbolMatches.map((m) => m.group(1)!).toList();

    return KiCadSchematicMetadata(
      title: titleMatch?.group(1),
      revision: revMatch?.group(1),
      company: compMatch?.group(1),
      components: components,
    );
  }
}
