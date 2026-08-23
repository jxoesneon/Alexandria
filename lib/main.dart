import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/theme/app_theme.dart';
import 'ui/scaffold/main_scaffold.dart';
import 'services/preservation_service.dart';

void main() {
  runApp(const ProviderScope(child: AlexandriaApp()));
}

class AlexandriaApp extends ConsumerStatefulWidget {
  const AlexandriaApp({super.key});

  @override
  ConsumerState<AlexandriaApp> createState() => _AlexandriaAppState();
}

class _AlexandriaAppState extends ConsumerState<AlexandriaApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(preservationServiceProvider).startBackgroundPreservation();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alexandria',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const MainScaffold(),
      debugShowCheckedModeBanner: false,
    );
  }
}
