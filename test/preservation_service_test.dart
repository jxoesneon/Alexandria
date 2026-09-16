import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/preservation_service.dart';

void main() {
  group('PreservationService Health & Healing Tests', () {
    late ProviderContainer container;
    late PreservationService preservation;

    setUp(() {
      container = ProviderContainer();
      preservation = container.read(preservationServiceProvider);
    });

    tearDown(() {
      preservation.stopBackgroundPreservation();
      container.dispose();
    });

    test('background preservation lifecycle starts and stops cleanly', () {
      expect(preservation.isRunning, isFalse);
      preservation.startBackgroundPreservation();
      expect(preservation.isRunning, isTrue);
      preservation.stopBackgroundPreservation();
      expect(preservation.isRunning, isFalse);
    });

    test('checks content health and heals pinned items', () async {
      // healContent → IpfsService.pinCid now requires the block to be
      // actually retrievable (round-2 fix — phantom pins are refused),
      // so the test stores real content first.
      final ipfs = container.read(ipfsServiceProvider);
      final cid = await ipfs
          .addFile(Uint8List.fromList('pinned preservation payload'.codeUnits));

      final health = await preservation.checkContentHealth(cid);
      expect(
          health,
          isIn([
            HealthStatus.healthy,
            HealthStatus.endangered,
            HealthStatus.lost
          ]));

      final heal = await preservation.healContent(cid);
      expect(heal, isTrue);

      // A fabricated identifier must NOT heal — nothing to pin.
      expect(await preservation.healContent('bafy_sample_test'), isFalse);
    });
  });
}
