import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final externalPlayerServiceProvider =
    Provider((ref) => ExternalPlayerService());

enum SupportedApp {
  vlc,
  calibre,
  blender,
  replayWeb,
  kicad,
  codeEditor,
  systemDefault,
}

class VlcPlaybackOptions {
  final bool fullscreen;
  final bool loop;
  final String? subtitlePath;
  final String? equalizerPreset;
  final int? startTimeSeconds;
  final int? audioTrackIndex;
  final int? httpControlPort;

  const VlcPlaybackOptions({
    this.fullscreen = false,
    this.loop = false,
    this.subtitlePath,
    this.equalizerPreset,
    this.startTimeSeconds,
    this.audioTrackIndex,
    this.httpControlPort,
  });

  List<String> toCommandLineArgs(String targetPathOrUrl) {
    final args = <String>[targetPathOrUrl];
    if (fullscreen) args.add('--fullscreen');
    if (loop) args.add('--loop');
    if (subtitlePath != null) args.add('--sub-file=$subtitlePath');
    if (equalizerPreset != null) {
      args.add('--equalizer-preset=$equalizerPreset');
    }
    if (startTimeSeconds != null) args.add('--start-time=$startTimeSeconds');
    if (audioTrackIndex != null) args.add('--audio-track=$audioTrackIndex');
    if (httpControlPort != null) {
      args.add('--extraintf=http');
      args.add('--http-port=$httpControlPort');
    }
    return args;
  }
}

class ExternalPlayerService {
  final Map<SupportedApp, String> _customExecutablePaths = {};

  void setCustomAppPath(SupportedApp app, String path) {
    _customExecutablePaths[app] = path;
  }

  String? getCustomAppPath(SupportedApp app) => _customExecutablePaths[app];

  /// Characters that must never appear in a launch target — shell
  /// metacharacters and control bytes (round-3 red finding). No shell is
  /// invoked anywhere anymore, but these are still rejected so a target
  /// crafted for a hypothetical downstream shell path fails here first.
  static final RegExp _unsafeTargetChars =
      RegExp(r'[&|;<>()$`"\\\n\r\x00-\x1f]');

  /// Validates that [target] is safe to hand to an external process as
  /// an argv element: either an `http(s)://` URL or a plain filesystem
  /// path with no shell metacharacters, no leading `-` (option/flag
  /// injection into the player binary — e.g. VLC `--extraintf`), and no
  /// URI scheme other than http(s) (kills `file:`, `javascript:`,
  /// `data:` smuggling).
  static bool isSafeExternalTarget(String target) {
    if (target.isEmpty || target.length > 4096) return false;
    if (_unsafeTargetChars.hasMatch(target)) return false;
    if (target.startsWith('-')) return false;
    final uri = Uri.tryParse(target);
    if (uri != null && uri.hasScheme) {
      // A Windows drive letter ('C:\…') parses as scheme 'c' — that is
      // already excluded above by the backslash ban, so any scheme here
      // must be http/https.
      return uri.scheme == 'http' || uri.scheme == 'https';
    }
    // Bare path — must not smuggle a scheme through whitespace tricks.
    if (target.contains(':')) return false;
    return true;
  }

  /// Throws [ArgumentError] when [target] fails [isSafeExternalTarget].
  static String _checkedTarget(String target) {
    if (!isSafeExternalTarget(target)) {
      throw ArgumentError(
          'Refusing unsafe external-player target: $target');
    }
    return target;
  }

  List<String> buildVlcCommand(String targetPathOrUrl,
      {VlcPlaybackOptions options = const VlcPlaybackOptions()}) {
    final target = _checkedTarget(targetPathOrUrl);
    final customPath = _customExecutablePaths[SupportedApp.vlc];
    final vlcArgs = options.toCommandLineArgs(target);

    if (Platform.isMacOS) {
      final bin = customPath ?? 'VLC';
      return [
        'open',
        '-a',
        bin,
        target,
        if (vlcArgs.length > 1) '--args',
        ...vlcArgs.sublist(1)
      ];
    } else if (Platform.isWindows) {
      // (round-3 red finding) no cmd.exe /c start — the executable is
      // launched directly so the target can never be re-parsed as a
      // shell command line.
      final bin = customPath ?? 'vlc.exe';
      return [bin, ...vlcArgs];
    } else {
      final bin = customPath ?? 'vlc';
      return [bin, ...vlcArgs];
    }
  }

  /// Windows "open with default handler" without a shell: explorer.exe
  /// takes the target as a plain argv element — it performs no command
  /// interpretation (round-3 red finding: replaces cmd.exe /c start).
  static const String _windowsShellOpen = 'explorer.exe';

  List<String> buildAppCommand(SupportedApp app, String targetPathOrUrl,
      {List<String> extraArgs = const []}) {
    final target = _checkedTarget(targetPathOrUrl);
    final customPath = _customExecutablePaths[app];

    switch (app) {
      case SupportedApp.vlc:
        return buildVlcCommand(target);

      case SupportedApp.calibre:
        if (Platform.isMacOS) {
          return ['open', '-a', customPath ?? 'Calibre', target];
        }
        if (Platform.isWindows) {
          return [customPath ?? 'calibre.exe', target];
        }
        return [customPath ?? 'foliate', target, ...extraArgs];

      case SupportedApp.blender:
        if (Platform.isMacOS) {
          return ['open', '-a', customPath ?? 'Blender', target];
        }
        if (Platform.isWindows) {
          return [customPath ?? 'blender.exe', target];
        }
        return [customPath ?? 'blender', target, ...extraArgs];

      case SupportedApp.kicad:
        if (Platform.isMacOS) {
          return ['open', '-a', customPath ?? 'KiCad', target];
        }
        if (Platform.isWindows) {
          return [customPath ?? 'kicad.exe', target];
        }
        return [customPath ?? 'kicad', target, ...extraArgs];

      case SupportedApp.codeEditor:
        if (Platform.isMacOS) {
          return [
            'open',
            '-a',
            customPath ?? 'Visual Studio Code',
            target
          ];
        }
        if (Platform.isWindows) {
          return [customPath ?? 'code.cmd', target];
        }
        return [customPath ?? 'code', target, ...extraArgs];

      case SupportedApp.replayWeb:
      case SupportedApp.systemDefault:
        if (Platform.isMacOS) return ['open', target];
        if (Platform.isWindows) {
          return [_windowsShellOpen, target];
        }
        return ['xdg-open', target];
    }
  }
}
