import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'core/themes/app_theme.dart';
import 'core/services/sleep_prevention_service.dart';
import 'features/validator_monitor/presentation/screens/token_gate_screen.dart';

// Global ProviderContainer for cleanup on app exit
late final ProviderContainer _container;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop-only window manager initialization
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    // Window configuration: minimum width 508px for UI layout
    const windowOptions = WindowOptions(
      size: Size(1400, 900),
      minimumSize: Size(508, 930),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Lock to portrait mode on mobile platforms
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  _container = ProviderContainer();

  runApp(
    UncontrolledProviderScope(
      container: _container,
      child: const ValidatorMonitorApp(),
    ),
  );
}

class ValidatorMonitorApp extends StatefulWidget {
  const ValidatorMonitorApp({super.key});

  @override
  State<ValidatorMonitorApp> createState() => _ValidatorMonitorAppState();
}

class _ValidatorMonitorAppState extends State<ValidatorMonitorApp>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    // Register window close listener on desktop platforms
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    debugPrint('[App] Window close requested - cleaning up resources...');

    // Disable sleep prevention before exit
    await sleepPreventionService.disable();

    // Dispose ProviderContainer - triggers provider cleanup callbacks
    // Cancels SSE streams, timers, and HTTP clients
    _container.dispose();

    debugPrint('[App] Cleanup complete - allowing window close');

    // Allow window to close
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sleepy Validator Monitor',
      theme: AppTheme.darkTheme,
      home: const TokenGateScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
