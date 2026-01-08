import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../../../core/services/sleep_prevention_service.dart';

final fullscreenProvider =
    StateNotifierProvider<FullscreenNotifier, bool>((ref) {
  return FullscreenNotifier();
});

class FullscreenNotifier extends StateNotifier<bool> {
  FullscreenNotifier() : super(false);

  Future<void> toggle() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final newState = !state;

      // On Windows, explicitly hide title bar before entering fullscreen
      if (Platform.isWindows && newState) {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      }

      await windowManager.setFullScreen(newState);

      // On Windows, restore title bar after exiting fullscreen
      if (Platform.isWindows && !newState) {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      }

      state = newState;

      // Auto-enable sleep prevention in fullscreen (war room mode)
      if (newState) {
        await sleepPreventionService.enable();
      } else {
        await sleepPreventionService.disable();
      }
    }
  }
}
