import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final externalPlayerServiceProvider = Provider((ref) => ExternalPlayerService());

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
    if (equalizerPreset != null) args.add('--equalizer-preset=$equalizerPreset');
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

  List<String> buildVlcCommand(String targetPathOrUrl, {VlcPlaybackOptions options = const VlcPlaybackOptions()}) {
    final customPath = _customExecutablePaths[SupportedApp.vlc];
    final vlcArgs = options.toCommandLineArgs(targetPathOrUrl);

    if (Platform.isMacOS) {
      final bin = customPath ?? 'VLC';
      return ['open', '-a', bin, targetPathOrUrl, if (vlcArgs.length > 1) '--args', ...vlcArgs.sublist(1)];
    } else if (Platform.isWindows) {
      final bin = customPath ?? 'vlc.exe';
      return ['cmd.exe', '/c', 'start', '""', bin, ...vlcArgs];
    } else {
      final bin = customPath ?? 'vlc';
      return [bin, ...vlcArgs];
    }
  }

  List<String> buildAppCommand(SupportedApp app, String targetPathOrUrl, {List<String> extraArgs = const []}) {
    final customPath = _customExecutablePaths[app];

    switch (app) {
      case SupportedApp.vlc:
        return buildVlcCommand(targetPathOrUrl);

      case SupportedApp.calibre:
        if (Platform.isMacOS) return ['open', '-a', customPath ?? 'Calibre', targetPathOrUrl];
        if (Platform.isWindows) return ['cmd.exe', '/c', 'start', '""', customPath ?? 'calibre.exe', targetPathOrUrl];
        return [customPath ?? 'foliate', targetPathOrUrl, ...extraArgs];

      case SupportedApp.blender:
        if (Platform.isMacOS) return ['open', '-a', customPath ?? 'Blender', targetPathOrUrl];
        if (Platform.isWindows) return ['cmd.exe', '/c', 'start', '""', customPath ?? 'blender.exe', targetPathOrUrl];
        return [customPath ?? 'blender', targetPathOrUrl, ...extraArgs];

      case SupportedApp.kicad:
        if (Platform.isMacOS) return ['open', '-a', customPath ?? 'KiCad', targetPathOrUrl];
        if (Platform.isWindows) return ['cmd.exe', '/c', 'start', '""', customPath ?? 'kicad.exe', targetPathOrUrl];
        return [customPath ?? 'kicad', targetPathOrUrl, ...extraArgs];

      case SupportedApp.codeEditor:
        if (Platform.isMacOS) return ['open', '-a', customPath ?? 'Visual Studio Code', targetPathOrUrl];
        if (Platform.isWindows) return ['cmd.exe', '/c', 'start', '""', customPath ?? 'code.cmd', targetPathOrUrl];
        return [customPath ?? 'code', targetPathOrUrl, ...extraArgs];

      case SupportedApp.replayWeb:
      case SupportedApp.systemDefault:
        if (Platform.isMacOS) return ['open', targetPathOrUrl];
        if (Platform.isWindows) return ['cmd.exe', '/c', 'start', '""', targetPathOrUrl];
        return ['xdg-open', targetPathOrUrl];
    }
  }
}
