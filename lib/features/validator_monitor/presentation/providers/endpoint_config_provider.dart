import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

// Endpoint configuration exception
class EndpointConfigException implements Exception {
  final String message;

  EndpointConfigException(this.message);

  @override
  String toString() => 'EndpointConfigException: $message';
}

// Endpoint configuration model
class EndpointConfig {
  final String host;
  final int port;
  final bool useHttps;

  const EndpointConfig({
    required this.host,
    required this.port,
    required this.useHttps,
  });

  // Generate base URL from config
  String get baseUrl => '${useHttps ? 'https' : 'http'}://$host:$port';

  // Copy with modifications
  EndpointConfig copyWith({
    String? host,
    int? port,
    bool? useHttps,
  }) {
    return EndpointConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      useHttps: useHttps ?? this.useHttps,
    );
  }

  // Validation
  String? validate() {
    if (host.isEmpty) {
      return 'Host cannot be empty';
    }

    // Basic hostname/IP validation
    final hostPattern = RegExp(
      r'^([a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?$|^(\d{1,3}\.){3}\d{1,3}$',
    );
    if (!hostPattern.hasMatch(host)) {
      return 'Invalid hostname or IP address format';
    }

    if (port < 1 || port > 65535) {
      return 'Port must be between 1 and 65535';
    }

    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EndpointConfig &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          useHttps == other.useHttps;

  @override
  int get hashCode => Object.hash(host, port, useHttps);

  @override
  String toString() => baseUrl;
}

// Shared preferences provider (cross-platform persistent storage)
final sharedPreferencesProvider =
    FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

// Endpoint config storage service
class EndpointConfigStorage {
  final SharedPreferences? _prefs;
  final File? _configFile;
  static const _appName = 'sleepy_ui';

  EndpointConfigStorage({SharedPreferences? prefs, File? configFile})
      : _prefs = prefs,
        _configFile = configFile;

  static Future<EndpointConfigStorage> create() async {
    if (!kIsWeb && Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home == null) throw Exception('HOME not set');

      final configDir = Directory(path.join(home, '.config', _appName));
      await configDir.create(recursive: true);
      final configFile = File(path.join(configDir.path, 'config.json'));

      return EndpointConfigStorage(configFile: configFile);
    } else {
      final prefs = await SharedPreferences.getInstance();
      return EndpointConfigStorage(prefs: prefs);
    }
  }

  Future<Map<String, dynamic>> _readLinuxConfig() async {
    if (_configFile == null) return {};
    if (!await _configFile.exists()) return {};
    return jsonDecode(await _configFile.readAsString()) as Map<String, dynamic>;
  }

  Future<void> _writeLinuxConfig(Map<String, dynamic> config) async {
    if (_configFile == null) throw Exception('Config file not initialized');
    // Set umask to 0077 so new files created with 0600 (no race condition)
    if (!await _configFile.exists()) {
      await Process.run(
          'sh', ['-c', 'umask 0077 && touch "${_configFile.path}"']);
    }
    // File now created with 0600, safe to write credentials
    await _configFile.writeAsString(jsonEncode(config));
  }

  Future<EndpointConfig?> read() async {
    if (_configFile != null) {
      final config = await _readLinuxConfig();
      final host = config['host'] as String?;
      final port = config['port'] as int?;
      final useHttps = config['use_https'] as bool?;

      if (host == null || port == null || useHttps == null) return null;

      final endpointConfig =
          EndpointConfig(host: host, port: port, useHttps: useHttps);
      if (endpointConfig.validate() != null) return null;

      return endpointConfig;
    } else {
      final host = _prefs?.getString('endpoint_host');
      final port = _prefs?.getInt('endpoint_port');
      final useHttps = _prefs?.getBool('endpoint_use_https');

      if (host == null || port == null || useHttps == null) return null;

      final config = EndpointConfig(host: host, port: port, useHttps: useHttps);
      if (config.validate() != null) return null;

      return config;
    }
  }

  Future<void> write(EndpointConfig config) async {
    if (_configFile != null) {
      final existing = await _readLinuxConfig();
      existing['host'] = config.host;
      existing['port'] = config.port;
      existing['use_https'] = config.useHttps;
      await _writeLinuxConfig(existing);
    } else {
      if (_prefs == null) throw Exception('SharedPreferences not initialized');
      await Future.wait([
        _prefs.setString('endpoint_host', config.host),
        _prefs.setInt('endpoint_port', config.port),
        _prefs.setBool('endpoint_use_https', config.useHttps),
      ]);
    }
  }

  Future<void> delete() async {
    if (_configFile != null) {
      final existing = await _readLinuxConfig();
      existing.remove('host');
      existing.remove('port');
      existing.remove('use_https');
      await _writeLinuxConfig(existing);
    } else {
      if (_prefs == null) throw Exception('SharedPreferences not initialized');
      await Future.wait([
        _prefs.remove('endpoint_host'),
        _prefs.remove('endpoint_port'),
        _prefs.remove('endpoint_use_https'),
      ]);
    }
  }
}

// Endpoint configuration notifier
class EndpointConfigNotifier
    extends StateNotifier<AsyncValue<EndpointConfig?>> {
  EndpointConfigStorage? _storage;

  EndpointConfigNotifier() : super(const AsyncValue.loading()) {
    _initialize();
  }

  // Initialize from storage
  Future<void> _initialize() async {
    state = const AsyncValue.loading();
    try {
      _storage = await EndpointConfigStorage.create();
      final config = await _storage!.read();
      state = AsyncValue.data(config);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  // Update endpoint configuration
  Future<void> updateConfig(EndpointConfig config) async {
    // Validate before saving
    final validationError = config.validate();
    if (validationError != null) {
      state = AsyncValue.error(
        EndpointConfigException(validationError),
        StackTrace.current,
      );
      return;
    }

    state = const AsyncValue.loading();
    try {
      _storage ??= await EndpointConfigStorage.create();
      await _storage!.write(config);
      state = AsyncValue.data(config);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  // Delete endpoint configuration
  Future<void> deleteConfig() async {
    try {
      _storage ??= await EndpointConfigStorage.create();
      await _storage!.delete();
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

// Endpoint config notifier provider
final endpointConfigNotifierProvider =
    StateNotifierProvider<EndpointConfigNotifier, AsyncValue<EndpointConfig?>>(
        (ref) {
  return EndpointConfigNotifier();
});

// Convenience provider for accessing current config (synchronous)
final currentEndpointConfigProvider = Provider<EndpointConfig?>((ref) {
  final configAsync = ref.watch(endpointConfigNotifierProvider);
  return configAsync.value;
});
