import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Tracks which sleep prevention method was successfully enabled
enum _EnableMethod {
  none,
  systemdInhibit,
  xdgScreensaver,
  caffeinate,
  windows,
}

class SleepPreventionService {
  Process? _process;
  bool _isActive = false;
  _EnableMethod _enableMethod =
      _EnableMethod.none; // Track method for symmetric cleanup

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
        _enableMethod = _EnableMethod.systemdInhibit;
        debugPrint('[✓] Sleep prevention enabled (systemd-inhibit)');
      } catch (e) {
        debugPrint(
            '[✗] systemd-inhibit not available, trying xdg-screensaver...');
        // Fallback: xdg-screensaver
        try {
          await Process.run('xdg-screensaver', ['suspend', '0']);
          _isActive = true;
          _enableMethod = _EnableMethod.xdgScreensaver;
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
        _enableMethod = _EnableMethod.windows;
        debugPrint('[✓] Sleep prevention enabled (SetThreadExecutionState)');
      } catch (e) {
        debugPrint('[✗] Windows sleep prevention failed: $e');
      }
    } else if (!kIsWeb && Platform.isMacOS) {
      // macOS: caffeinate command
      try {
        _process = await Process.start('caffeinate', ['-d']);
        _isActive = true;
        _enableMethod = _EnableMethod.caffeinate;
        debugPrint('[✓] Sleep prevention enabled (caffeinate)');
      } catch (e) {
        debugPrint('[✗] caffeinate failed');
      }
    }
  }

  Future<void> disable() async {
    if (!_isActive) return;

    // CORRECTNESS [PLATFORM-01]: Use tracked method for symmetric cleanup
    switch (_enableMethod) {
      case _EnableMethod.systemdInhibit:
      case _EnableMethod.caffeinate:
        // Kill persistent process (systemd-inhibit or caffeinate)
        _process?.kill();
        _process = null;
        break;

      case _EnableMethod.xdgScreensaver:
        // Resume xdg-screensaver explicitly
        try {
          await Process.run('xdg-screensaver', ['resume', '0']);
        } catch (e) {
          debugPrint('[✗] Failed to resume xdg-screensaver: $e');
        }
        break;

      case _EnableMethod.windows:
        // Reset Windows execution state to allow sleep
        try {
          SetThreadExecutionState(ES_CONTINUOUS);
          debugPrint('[✓] Sleep prevention disabled (Windows)');
        } catch (e) {
          debugPrint('[✗] Failed to reset Windows execution state: $e');
        }
        break;

      case _EnableMethod.none:
        // No cleanup needed
        break;
    }

    _isActive = false;
    _enableMethod = _EnableMethod.none;
    debugPrint('[✓] Sleep prevention disabled');
  }

  bool get isActive => _isActive;
}

// Global instance (24/7 operation)
final sleepPreventionService = SleepPreventionService();
