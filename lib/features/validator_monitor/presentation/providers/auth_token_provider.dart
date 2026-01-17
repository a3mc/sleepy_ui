import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;

// Custom exception for token validation failures
class TokenValidationException implements Exception {
  final String message;

  TokenValidationException(this.message);

  @override
  String toString() => 'TokenValidationException: $message';
}

// Custom exception for storage initialization failures
class StorageInitializationException implements Exception {
  final String message;
  final Object? originalError;

  StorageInitializationException(this.message, [this.originalError]);

  @override
  String toString() =>
      'StorageInitializationException: $message${originalError != null ? ' (Cause: $originalError)' : ''}';
}

// Auth token state notifier with secure storage and validation
class AuthTokenNotifier extends StateNotifier<AsyncValue<String?>> {
  FlutterSecureStorage? _storage;
  File? _configFile;
  static const _tokenKey = 'bearer_token';
  static const _appName = 'sleepy_ui';

  AuthTokenNotifier() : super(const AsyncValue.loading()) {
    _initialize();
  }

  // Read config from JSON file (desktop platforms)
  Future<Map<String, dynamic>> _readDesktopConfig() async {
    if (_configFile == null || !await _configFile!.exists()) {
      return {};
    }
    try {
      final content = await _configFile!.readAsString();
      if (content.trim().isEmpty) return {};
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[Storage] Failed to read config: $e');
      return {};
    }
  }

  // Write config to JSON file (desktop platforms - plain text with OS permissions)
  Future<void> _writeDesktopConfig(Map<String, dynamic> config) async {
    // Linux: Use umask for file permissions (0600 - owner read/write only)
    if (Platform.isLinux && !await _configFile!.exists()) {
      await Process.run(
          'sh', ['-c', 'umask 0077 && touch "${_configFile!.path}"']);
    }
    // macOS/Windows: Direct write (OS handles permissions via directory ACLs)
    await _configFile!.writeAsString(jsonEncode(config));
  }

  // Initialize storage and read token
  Future<void> _initialize() async {
    state = const AsyncValue.loading();
    try {
      // Platform-specific storage initialization
      if (kIsWeb) {
        throw StorageInitializationException(
            'Web platform storage is insecure for bearer tokens. '
            'Use backend session management or accept localStorage with security warning.');
      }

      // Use single JSON config file on Linux, macOS, and Windows
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        final String configPath;

        if (Platform.isLinux) {
          final home = Platform.environment['HOME'];
          if (home == null) {
            throw StorageInitializationException(
                'HOME environment variable not set');
          }
          configPath = path.join(home, '.config', _appName);
        } else if (Platform.isMacOS) {
          final home = Platform.environment['HOME'];
          if (home == null) {
            throw StorageInitializationException(
                'HOME environment variable not set');
          }
          configPath =
              path.join(home, 'Library', 'Application Support', _appName);
        } else {
          // Windows: %APPDATA%\sleepy_ui
          final appData = Platform.environment['APPDATA'];
          if (appData == null) {
            throw StorageInitializationException(
                'APPDATA environment variable not set');
          }
          configPath = path.join(appData, _appName);
          debugPrint('[Storage] Windows APPDATA path: $configPath');
        }

        final configDir = Directory(configPath);
        debugPrint('[Storage] Creating directory: ${configDir.path}');
        await configDir.create(recursive: true);
        debugPrint('[Storage] Directory exists: ${await configDir.exists()}');

        _configFile = File(path.join(configDir.path, 'config.json'));
        debugPrint('[Storage] Config file path: ${_configFile!.path}');

        final config = await _readDesktopConfig();
        final token = config['bearer_token'] as String?;
        debugPrint(
            '[Storage] Token loaded: ${token != null ? "present" : "null"}');
        state = AsyncValue.data(token);
      } else {
        // Use Android Keystore (encrypted secure storage)
        _storage = const FlutterSecureStorage(
          iOptions:
              IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );
        final token = await _storage!.read(key: _tokenKey);
        state = AsyncValue.data(token);
      }
    } catch (error, stackTrace) {
      debugPrint('[Storage] INITIALIZATION FAILED: $error');
      debugPrint('[Storage] Stack trace: $stackTrace');
      state = AsyncValue.error(error, stackTrace);
    }
  }

  // Validate token format (public static for UI layer consistency)
  static String? validateTokenInput(String token) {
    if (token.isEmpty) {
      return 'Token cannot be empty';
    }

    if (token.length < 32) {
      return 'Token must be at least 32 characters';
    }

    if (token.length > 512) {
      return 'Token exceeds maximum length (512 characters)';
    }

    // Alphanumeric plus hyphens and underscores (matches UI validation)
    final tokenPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
    if (!tokenPattern.hasMatch(token)) {
      return 'Token contains invalid characters (only alphanumeric, hyphens, and underscores allowed)';
    }

    return null;
  }

  // Save token with validation
  Future<void> saveToken(String token) async {
    if (_storage == null && _configFile == null) {
      throw StorageInitializationException('Storage not initialized');
    }

    // Normalize token before validation
    final trimmedToken = token.trim();

    // Validate trimmed token
    final validationError = validateTokenInput(trimmedToken);
    if (validationError != null) {
      throw TokenValidationException(validationError);
    }

    state = const AsyncValue.loading();
    try {
      if (_configFile != null) {
        debugPrint('[Storage] Saving token to: ${_configFile!.path}');
        final config = await _readDesktopConfig();
        config['bearer_token'] = trimmedToken;
        await _writeDesktopConfig(config);
        debugPrint('[Storage] Token saved successfully');
      } else {
        await _storage!.write(key: _tokenKey, value: trimmedToken);
      }
      state = AsyncValue.data(trimmedToken);
    } catch (error, stackTrace) {
      debugPrint('[Storage] SAVE FAILED: $error');
      debugPrint('[Storage] Stack trace: $stackTrace');
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  // Delete token
  Future<void> deleteToken() async {
    if (_storage == null && _configFile == null) {
      throw StorageInitializationException('Storage not initialized');
    }

    state = const AsyncValue.loading();
    try {
      if (_configFile != null) {
        final config = await _readDesktopConfig();
        config.remove('bearer_token');
        await _writeDesktopConfig(config);
      } else {
        await _storage!.delete(key: _tokenKey);
      }
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

// Auth token provider
final authTokenNotifierProvider =
    StateNotifierProvider<AuthTokenNotifier, AsyncValue<String?>>((ref) {
  return AuthTokenNotifier();
});
