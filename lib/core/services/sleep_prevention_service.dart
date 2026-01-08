import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

class SleepPreventionService {
  Process? _process;
  bool _isActive = false;

  Future<void> enable() async {
    if (_isActive) return;

    if (!kIsWeb && Platform.isLinux) {
      // Attempt systemd-inhibit (most modern distros)
      try {
        _process = await Process.start(
          'systemd-inhibit',
          [
            '--what=idle:sleep',
            '--who=Sleepy UI',
            '--why=Validator monitoring active',
            '--mode=block',
            'cat', // Keep process alive
          ],
        );
        _isActive = true;
        debugPrint('[✓] Sleep prevention enabled (systemd-inhibit)');
      } catch (e) {
        debugPrint(
            '[✗] systemd-inhibit not available, trying xdg-screensaver...');
        // Fallback: xdg-screensaver
        try {
          await Process.run('xdg-screensaver', ['suspend', '0']);
          _isActive = true;
          debugPrint('[✓] Sleep prevention enabled (xdg-screensaver)');
        } catch (e) {
          debugPrint('[✗] Sleep prevention unavailable on this system');
        }
      }
    } else if (!kIsWeb && Platform.isWindows) {
      // Windows: SetThreadExecutionState via win32 package
      try {
        // ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED
        // Prevents system sleep and keeps display on
        SetThreadExecutionState(
            ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED);
        _isActive = true;
        debugPrint('[✓] Sleep prevention enabled (SetThreadExecutionState)');
      } catch (e) {
        debugPrint('[✗] Windows sleep prevention failed: $e');
      }
    } else if (!kIsWeb && Platform.isMacOS) {
      // macOS: caffeinate command
      try {
        _process = await Process.start('caffeinate', ['-d']);
        _isActive = true;
        debugPrint('[✓] Sleep prevention enabled (caffeinate)');
      } catch (e) {
        debugPrint('[✗] caffeinate failed');
      }
    }
  }

  Future<void> disable() async {
    if (!_isActive) return;

    if (!kIsWeb && Platform.isLinux) {
      _process?.kill();
      // If using xdg-screensaver, reset
      try {
        await Process.run('xdg-screensaver', ['resume', '0']);
      } catch (e) {
        // Ignore
      }
    } else if (!kIsWeb && Platform.isWindows) {
      // Windows: Reset to default (allow sleep)
      try {
        SetThreadExecutionState(ES_CONTINUOUS);
        debugPrint('[✓] Sleep prevention disabled (Windows)');
      } catch (e) {
        debugPrint('[✗] Failed to reset Windows execution state: $e');
      }
    } else if (!kIsWeb && Platform.isMacOS) {
      _process?.kill();
    }

    _process = null;
    _isActive = false;
    debugPrint('[✓] Sleep prevention disabled');
  }

  bool get isActive => _isActive;
}

// Global instance (24/7 operation)
final sleepPreventionService = SleepPreventionService();
