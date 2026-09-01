import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/media/hardware_schematics_service.dart';

void main() {
  group('Hardware Schematics Parser Tests', () {
    late HardwareSchematicsService hardwareService;

    setUp(() {
      hardwareService = HardwareSchematicsService();
    });

    test('parses KiCad schematic metadata and symbols', () {
      const sch = '''
      (kicad_sch (version 20230121) (generator eeschema)
        (title_block
          (title "Alexandria Hardware Node")
          (rev "1.0")
          (company "Open Preservation Initiative")
        )
        (symbol "R1" (pin 1) (pin 2))
        (symbol "C1" (pin 1) (pin 2))
        (symbol "U1" (pin 1) (pin 2) (pin 3))
      )
      ''';

      final meta = hardwareService.parseKiCadSchematic(sch);
      expect(meta.title, equals('Alexandria Hardware Node'));
      expect(meta.revision, equals('1.0'));
      expect(meta.components.length, equals(3));
      expect(meta.components, contains('R1'));
    });
  });
}
