import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/external_player_service.dart';

void main() {
  group('ExternalPlayerService Tests', () {
    late ExternalPlayerService playerService;

    setUp(() {
      playerService = ExternalPlayerService();
    });

    test('builds VLC command with playback options', () {
      const options = VlcPlaybackOptions(
        fullscreen: true,
        loop: true,
        subtitlePath: '/path/to/subs.srt',
        equalizerPreset: 'classical',
        startTimeSeconds: 120,
        audioTrackIndex: 2,
        httpControlPort: 8088,
      );

      final cmd = playerService.buildVlcCommand('http://127.0.0.1:8080/ipfs/bafytest', options: options);
      expect(cmd, isNotEmpty);
      expect(cmd.any((arg) => arg.contains('--fullscreen') || arg.contains('VLC')), isTrue);
    });

    test('builds application commands for supported apps', () {
      final calibreCmd = playerService.buildAppCommand(SupportedApp.calibre, '/path/to/book.epub');
      expect(calibreCmd, isNotEmpty);

      final blenderCmd = playerService.buildAppCommand(SupportedApp.blender, '/path/to/model.glb');
      expect(blenderCmd, isNotEmpty);

      final kicadCmd = playerService.buildAppCommand(SupportedApp.kicad, '/path/to/board.kicad_sch');
      expect(kicadCmd, isNotEmpty);
    });

    test('allows setting custom executable paths', () {
      playerService.setCustomAppPath(SupportedApp.vlc, '/usr/local/bin/vlc-custom');
      expect(playerService.getCustomAppPath(SupportedApp.vlc), equals('/usr/local/bin/vlc-custom'));
    });
  });
}
