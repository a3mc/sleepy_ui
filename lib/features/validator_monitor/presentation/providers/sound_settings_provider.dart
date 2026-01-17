import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;

class SoundSettings {
  final bool enabled;
  final double volume;

  SoundSettings({required this.enabled, required this.volume});

  SoundSettings copyWith({bool? enabled, double? volume}) {
    return SoundSettings(
      enabled: enabled ?? this.enabled,
      volume: volume ?? this.volume,
    );
  }
}

final soundSettingsProvider =
    StateNotifierProvider<SoundSettingsNotifier, SoundSettings>((ref) {
  return SoundSettingsNotifier();
});

final soundEnabledProvider = Provider<bool>((ref) {
  return ref.watch(soundSettingsProvider).enabled;
});

final soundVolumeProvider = Provider<double>((ref) {
  return ref.watch(soundSettingsProvider).volume;
});

class SoundSettingsNotifier extends StateNotifier<SoundSettings> {
  FlutterSecureStorage? _storage;
  File? _configFile;
  Timer? _saveTimer;
  static const _soundKey = 'alert_sounds_enabled';
  static const _volumeKey = 'alert_sounds_volume';
  static const _appName = 'sleepy_ui';

  SoundSettingsNotifier() : super(SoundSettings(enabled: true, volume: 0.7)) {
    _initialize();
  }

  Future<void> _initialize() async {
    if (kIsWeb) return;

    try {
      // Desktop: Use JSON config file
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        final String configPath;
        if (Platform.isLinux) {
          configPath =
              path.join(Platform.environment['HOME']!, '.config', _appName);
        } else if (Platform.isMacOS) {
          configPath = path.join(Platform.environment['HOME']!, 'Library',
              'Application Support', _appName);
        } else {
          configPath = path.join(Platform.environment['APPDATA']!, _appName);
        }

        final configDir = Directory(configPath);
        await configDir.create(recursive: true);
        _configFile = File(path.join(configPath, 'config.json'));

        if (await _configFile!.exists()) {
          final content = await _configFile!.readAsString();
          if (content.trim().isNotEmpty) {
            final config = jsonDecode(content) as Map<String, dynamic>;
            if (mounted) {
              state = SoundSettings(
                enabled: config[_soundKey] as bool? ?? true,
                volume: (config[_volumeKey] as num?)?.toDouble() ?? 0.7,
              );
            }
          }
        }
      } else {
        // Android: Use secure storage
        _storage = const FlutterSecureStorage(
          iOptions:
              IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );
        final enabledStr = await _storage!.read(key: _soundKey);
        final volumeStr = await _storage!.read(key: _volumeKey);
        if (mounted) {
          state = SoundSettings(
            enabled: enabledStr == 'true' || enabledStr == null,
            volume: volumeStr != null ? double.tryParse(volumeStr) ?? 0.7 : 0.7,
          );
        }
      }
    } catch (e) {
      debugPrint('[SoundSettings] Init: $e');
    }
  }

  Future<void> _save() async {
    // Debounce: cancel previous timer and start new one
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _performSave);
  }

  Future<void> _performSave() async {
    try {
      if (_configFile != null) {
        // Desktop: JSON config file
        Map<String, dynamic> config = {};
        if (await _configFile!.exists()) {
          final content = await _configFile!.readAsString();
          if (content.trim().isNotEmpty) {
            config = jsonDecode(content) as Map<String, dynamic>;
            debugPrint(
                '[SoundSettings] Read existing keys: ${config.keys.toList()}');
          }
        }
        config[_soundKey] = state.enabled;
        config[_volumeKey] = (state.volume * 100).round() / 100;
        debugPrint('[SoundSettings] Writing keys: ${config.keys.toList()}');
        await _configFile!.writeAsString(jsonEncode(config));
      } else if (_storage != null) {
        // Android: Secure storage
        await _storage!.write(key: _soundKey, value: state.enabled.toString());
        await _storage!.write(key: _volumeKey, value: state.volume.toString());
        debugPrint('[SoundSettings] Saved to secure storage (Android)');
      }
    } catch (e) {
      debugPrint('[SoundSettings] Save failed: $e');
    }
  }

  Future<void> toggle() async {
    state = state.copyWith(enabled: !state.enabled);
    await _save();
  }

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    await _save();
  }

  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume.clamp(0.0, 1.0));
    await _save();
  }
}
