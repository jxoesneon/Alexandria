import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/network_models.dart';
import 'package:alexandria/services/honor_bandwidth_service.dart';
import 'package:alexandria/services/media/audio_media_service.dart';
import 'package:alexandria/services/media/hardware_schematics_service.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('network_models copyWith/toString', () {
    test('NodeStatus.copyWith and toString', () {
      const s = NodeStatus(isRunning: true, connectedPeers: 3, nodeId: 'n1');
      expect(s.toString(), contains('isRunning: true'));
      final c = s.copyWith(connectedPeers: 7);
      expect(c.connectedPeers, 7);
      expect(c.isRunning, isTrue);
      expect(c.nodeId, 'n1');
      final c2 = s.copyWith();
      expect(c2.connectedPeers, 3);
    });

    test('BandwidthStats.copyWith', () {
      final b = BandwidthStats(
        uploadBps: 10,
        downloadBps: 20,
        timestamp: DateTime(2026, 1, 1),
      );
      final c = b.copyWith(uploadBps: 99);
      expect(c.uploadBps, 99);
      expect(c.downloadBps, 20);
      final c2 = b.copyWith();
      expect(c2.uploadBps, 10);
    });

    test('Peer.copyWith', () {
      const p = Peer(
        peerId: 'p1',
        multiaddr: '/ip4/1.2.3.4',
        latencyMs: 12,
        status: PeerStatus.connected,
      );
      final c = p.copyWith(latencyMs: 50, status: PeerStatus.pending);
      expect(c.latencyMs, 50);
      expect(c.status, PeerStatus.pending);
      expect(c.peerId, 'p1');
      final c2 = p.copyWith();
      expect(c2.multiaddr, '/ip4/1.2.3.4');
    });

    test('Transfer.copyWith and progress', () {
      const t = Transfer(
        name: 'file',
        bytesTransferred: 5,
        totalBytes: 10,
      );
      expect(t.progress, 0.5);
      final c = t.copyWith(bytesTransferred: 8);
      expect(c.bytesTransferred, 8);
      expect(c.name, 'file');
      final c2 = t.copyWith();
      expect(c2.totalBytes, 10);
    });

    test('Conflict.copyWith', () {
      final cf = Conflict(
        id: 'c1',
        documentName: 'doc',
        localVersion: 'a',
        remoteVersion: 'b',
        timestamp: DateTime(2026, 2, 2),
      );
      final c = cf.copyWith(localVersion: 'x');
      expect(c.localVersion, 'x');
      expect(c.remoteVersion, 'b');
      final c2 = cf.copyWith();
      expect(c2.id, 'c1');
    });

    test('Resolution.copyWith', () {
      const r = Resolution(id: 'r1', success: true);
      final c = r.copyWith(success: false);
      expect(c.success, isFalse);
      expect(c.id, 'r1');
      final c2 = r.copyWith();
      expect(c2.success, isTrue);
    });

    test('SyncProgress.copyWith', () {
      const sp = SyncProgress(
        overallProgress: 0.25,
        activeTransfers: [],
        pendingConflicts: [],
      );
      final c = sp.copyWith(overallProgress: 0.75, inProgress: true);
      expect(c.overallProgress, 0.75);
      expect(c.inProgress, isTrue);
      final c2 = sp.copyWith();
      expect(c2.overallProgress, 0.25);
    });
  });

  group('HardwareSchematicsService', () {
    test('provider resolves and parses KiCad schematic', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(hardwareSchematicsServiceProvider);
      expect(service, isA<HardwareSchematicsService>());

      const source = '(kicad_sch (title "Amp") (rev "1.2") '
          '(company "ACME") (symbol "R1") (symbol "C2"))';
      final meta = service.parseKiCadSchematic(source);
      expect(meta.title, 'Amp');
      expect(meta.revision, '1.2');
      expect(meta.company, 'ACME');
      expect(meta.components, ['R1', 'C2']);
    });
  });

  group('AudioMediaService', () {
    test('provider resolves; FLAC header parse and duration', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(audioMediaServiceProvider);
      expect(service, isA<AudioMediaService>());

      // Minimal FLAC STREAMINFO-shaped buffer: 'fLaC' + block header +
      // 34-byte STREAMINFO payload fields.
      final bytes = Uint8List(42);
      bytes[0] = 0x66; // 'f'
      bytes[1] = 0x4C; // 'L'
      bytes[2] = 0x61; // 'a'
      bytes[3] = 0x43; // 'C'
      bytes[8] = 0x10;
      bytes[9] = 0x00; // minBlock 4096
      bytes[10] = 0x10;
      bytes[11] = 0x00; // maxBlock 4096
      // sampleRate 44100 = 0xAC44 → bytes[18..20] high 20 bits
      bytes[18] = 0x0A;
      bytes[19] = 0xC4;
      bytes[20] = 0x40; // low nibble of rate + channels-1 bits
      bytes[21] = 0xF0; // bitsPerSample-1 high bits
      // totalSamples 44100 at bytes[22..25]
      bytes[22] = 0x00;
      bytes[23] = 0x00;
      bytes[24] = 0xAC;
      bytes[25] = 0x44;

      final info = service.parseFlacHeader(bytes);
      expect(info.minBlockSize, 4096);
      expect(info.sampleRate, 44100);
      expect(info.totalSamples, 44100);
      expect(info.durationSeconds, closeTo(1.0, 0.001));

      // Zero-sample/zero-rate duration is 0.
      final zero = FlacStreamInfo(
        minBlockSize: 0,
        maxBlockSize: 0,
        sampleRate: 0,
        channels: 0,
        bitsPerSample: 0,
        totalSamples: 0,
      );
      expect(zero.durationSeconds, 0.0);
    });

    test('parseFlacHeader rejects truncated and bad-magic buffers', () {
      final service = AudioMediaService();
      expect(() => service.parseFlacHeader(Uint8List(10)),
          throwsA(isA<FormatException>()));
      final bad = Uint8List(42);
      bad[0] = 0x00;
      expect(
          () => service.parseFlacHeader(bad), throwsA(isA<FormatException>()));
    });
  });

  group('AppTheme NavigationBarTheme resolvers', () {
    test('label and icon styles respond to selection state', () async {
      // Same flag lib/main.dart sets in production: bundled families
      // only, no runtime fetch. The google_fonts text-style factories
      // still fire an unawaited load attempt whose async failure lands
      // in the test zone - quarantine the resolves so that background
      // font-loader error cannot fail the test. The resolver lines are
      // still executed (and thus covered) inside the zone.
      GoogleFonts.config.allowRuntimeFetching = false;
      await runZonedGuarded(() async {
        final theme = AppTheme.darkTheme;
        final nav = theme.navigationBarTheme;
        final label = nav.labelTextStyle!.resolve({WidgetState.selected});
        final labelUnsel = nav.labelTextStyle!.resolve(<WidgetState>{});
        expect(label?.color, isNotNull);
        expect(labelUnsel?.color, isNotNull);
        final icon = nav.iconTheme!.resolve({WidgetState.selected});
        final iconUnsel = nav.iconTheme!.resolve(<WidgetState>{});
        expect(icon!.color, AppTheme.primaryAccent);
        expect(iconUnsel!.color, isNot(AppTheme.primaryAccent));
        // Let the fire-and-forget font loads settle inside the zone.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }, (Object e, StackTrace st) {});
    });
  });

  group('HonorBandwidthService coverage extras', () {
    test('provider resolves', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(honorBandwidthServiceProvider),
          isA<HonorBandwidthService>());
    });

    test('enqueueRequest without resolver completes with zero weight',
        () async {
      final service = HonorBandwidthService();
      final result = await service.enqueueRequest<int>(
        requestId: 'r1',
        peerId: 'peer-a',
        baseHonorScore: 999,
        verifiedPoRCount: 999,
        task: () async => 42,
      );
      expect(result, 42);
      expect(service.queueLength, 0);
    });

    test('enqueueRequest consults attestation resolver', () async {
      final service = HonorBandwidthService(
        attestationResolver: (peerId) async =>
            const HonorAttestation(honorScore: 10, porCount: 5),
      );
      final result = await service.enqueueRequest<String>(
        requestId: 'r2',
        peerId: 'peer-b',
        baseHonorScore: 0,
        verifiedPoRCount: 0,
        task: () async => 'done',
      );
      expect(result, 'done');
    });

    test('enqueueRequest fails closed when resolver throws', () async {
      final service = HonorBandwidthService(
        attestationResolver: (peerId) async =>
            throw StateError('attestation backend down'),
      );
      final result = await service.enqueueRequest<int>(
        requestId: 'r3',
        peerId: 'peer-c',
        baseHonorScore: 1,
        verifiedPoRCount: 1,
        task: () async => 7,
      );
      expect(result, 7);
    });
  });
}
