import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/external_player_service.dart';

void main() {
  group('ExternalPlayerService (test/services)', () {
    late ExternalPlayerService player;

    setUp(() {
      player = ExternalPlayerService();
    });

    test('provider exposes a service instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(externalPlayerServiceProvider),
        isA<ExternalPlayerService>(),
      );
    });

    test('VlcPlaybackOptions builds full command line arguments', () {
      const options = VlcPlaybackOptions(
        fullscreen: true,
        loop: true,
        subtitlePath: '/subs.srt',
        equalizerPreset: 'classical',
        startTimeSeconds: 120,
        audioTrackIndex: 2,
        httpControlPort: 8088,
      );

      final args = options.toCommandLineArgs('http://example.com/video.mp4');
      expect(args.first, equals('http://example.com/video.mp4'));
      expect(args, contains('--fullscreen'));
      expect(args, contains('--loop'));
      expect(args, contains('--sub-file=/subs.srt'));
      expect(args, contains('--equalizer-preset=classical'));
      expect(args, contains('--start-time=120'));
      expect(args, contains('--audio-track=2'));
      expect(args, contains('--extraintf=http'));
      expect(args, contains('--http-port=8088'));
    });

    test('VlcPlaybackOptions default arguments include only the target', () {
      const options = VlcPlaybackOptions();
      final args = options.toCommandLineArgs('http://example.com/video.mp4');
      expect(args, equals(['http://example.com/video.mp4']));
    });

    test('buildVlcCommand with default options on current platform', () {
      final cmd = player.buildVlcCommand('http://example.com/video.mp4');
      expect(cmd, isNotEmpty);
      expect(cmd.first, anyOf(equals('open'), equals('vlc')));
    });

    test('buildVlcCommand with custom VLC path and all options', () {
      player.setCustomAppPath(SupportedApp.vlc, '/my/custom/vlc');
      const options = VlcPlaybackOptions(
        fullscreen: true,
        audioTrackIndex: 1,
      );

      final cmd = player.buildVlcCommand('http://example.com/video.mp4',
          options: options);
      expect(cmd, isNotEmpty);
      expect(
          cmd.any((a) =>
              a.contains('fullscreen') || a == 'VLC' || a == '/my/custom/vlc'),
          isTrue);
    });

    test('buildAppCommand covers all supported apps', () {
      const target = '/path/to/file';
      const extra = ['--extra'];

      for (final app in SupportedApp.values) {
        final cmd = player.buildAppCommand(app, target, extraArgs: extra);
        expect(cmd, isNotEmpty, reason: 'Command for $app should not be empty');
      }
    });

    test('custom and default executable paths roundtrip', () {
      for (final app in SupportedApp.values) {
        expect(player.getCustomAppPath(app), isNull);
        player.setCustomAppPath(app, '/custom/$app');
        expect(player.getCustomAppPath(app), equals('/custom/$app'));
      }
    });

    test('buildAppCommand uses the custom executable path when provided', () {
      player.setCustomAppPath(
          SupportedApp.calibre, '/Applications/Calibre.app');
      final cmd = player.buildAppCommand(SupportedApp.calibre, '/book.epub');
      if (Platform.isMacOS) {
        expect(cmd, contains('/Applications/Calibre.app'));
      }
    });

    // Note: the Windows and Linux branches are platform-guarded by
    // Platform.isWindows / Platform.isLinux and are not coverable when
    // running on macOS.
    test('buildVlcCommand on macOS uses open and the target', () {
      if (!Platform.isMacOS) {
        return;
      }
      final cmd = player.buildVlcCommand('/my/video.mp4');
      expect(cmd, equals(['open', '-a', 'VLC', '/my/video.mp4']));
    });

    test('buildVlcCommand with options on macOS forwards --args', () {
      if (!Platform.isMacOS) {
        return;
      }
      const options = VlcPlaybackOptions(fullscreen: true, loop: true);
      final cmd = player.buildVlcCommand('/my/video.mp4', options: options);
      expect(cmd.first, 'open');
      expect(cmd, contains('--args'));
      expect(cmd, contains('--fullscreen'));
      expect(cmd, contains('--loop'));
    });

    test('buildVlcCommand on macOS respects custom VLC path', () {
      if (!Platform.isMacOS) {
        return;
      }
      player.setCustomAppPath(SupportedApp.vlc, '/custom/VLC');
      final cmd = player.buildVlcCommand('/my/video.mp4');
      expect(cmd, contains('/custom/VLC'));
    });

    test('buildAppCommand for each app on macOS returns a non-empty command',
        () {
      if (!Platform.isMacOS) {
        return;
      }
      const target = '/path/to/file';
      for (final app in SupportedApp.values) {
        final cmd = player.buildAppCommand(app, target);
        expect(cmd, isNotEmpty);
        expect(cmd.first, equals('open'));
      }
    });

    test('buildAppCommand for replayWeb on macOS is a simple open', () {
      if (!Platform.isMacOS) {
        return;
      }
      final cmd =
          player.buildAppCommand(SupportedApp.replayWeb, '/archive.wacz');
      expect(cmd, equals(['open', '/archive.wacz']));
    });

    test('buildAppCommand for systemDefault on macOS is a simple open', () {
      if (!Platform.isMacOS) {
        return;
      }
      final cmd =
          player.buildAppCommand(SupportedApp.systemDefault, '/doc.pdf');
      expect(cmd, equals(['open', '/doc.pdf']));
    });

    test('buildAppCommand for codeEditor on macOS uses Visual Studio Code', () {
      if (!Platform.isMacOS) {
        return;
      }
      final cmd = player.buildAppCommand(SupportedApp.codeEditor, '/project');
      expect(cmd, contains('Visual Studio Code'));
    });
  });
}
