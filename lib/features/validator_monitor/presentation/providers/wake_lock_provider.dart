import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

final wakeLockEnabledProvider =
    StateNotifierProvider<WakeLockNotifier, bool>((ref) {
  return WakeLockNotifier();
});

class WakeLockNotifier extends StateNotifier<bool> with WidgetsBindingObserver {
  WakeLockNotifier() : super(false) {
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.addObserver(this);
      _loadSetting();
    }
  }

  Future<void> _loadSetting() async {
    // Android only - default to true for auto-enable
    if (!kIsWeb && Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('wake_lock_auto_enable') ?? true;
      state = enabled;
      if (enabled) {
        await WakelockPlus.enable();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release wake lock when app goes to background (prevents battery drain)
    if (!kIsWeb && Platform.isAndroid) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        WakelockPlus.disable();
      } else if (state == AppLifecycleState.resumed && this.state) {
        // Re-enable if setting is still enabled
        WakelockPlus.enable();
      }
    }
  }

  Future<void> toggle() async {
    if (!kIsWeb && Platform.isAndroid) {
      final newState = !state;
      state = newState;

      if (newState) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wake_lock_auto_enable', newState);
    }
  }

  @override
  void dispose() {
    // Clean disable on provider disposal
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
      WakelockPlus.disable();
    }
    super.dispose();
  }
}
