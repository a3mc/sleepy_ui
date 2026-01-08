import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sleepy_ui/features/validator_monitor/presentation/providers/endpoint_config_provider.dart';

void main() {
  group('EndpointConfig', () {
    test('generates correct baseUrl from config', () {
      final httpConfig = EndpointConfig(
        host: 'example.com',
        port: 8080,
        useHttps: false,
      );
      expect(httpConfig.baseUrl, 'http://example.com:8080');

      final httpsConfig = EndpointConfig(
        host: 'secure.example.com',
        port: 443,
        useHttps: true,
      );
      expect(httpsConfig.baseUrl, 'https://secure.example.com:443');
    });

    test('copyWith creates modified config', () {
      const original = EndpointConfig(
        host: 'old.example.com',
        port: 8080,
        useHttps: false,
      );

      final modified =
          original.copyWith(host: 'new.example.com', useHttps: true);

      expect(modified.host, 'new.example.com');
      expect(modified.port, 8080); // Unchanged
      expect(modified.useHttps, true);
    });

    test('validate returns null for valid config', () {
      const config = EndpointConfig(
        host: 'example.com',
        port: 8080,
        useHttps: true,
      );

      expect(config.validate(), isNull);
    });

    test('validate rejects empty host', () {
      const config = EndpointConfig(
        host: '',
        port: 8080,
        useHttps: true,
      );

      expect(config.validate(), 'Host cannot be empty');
    });

    test('validate rejects invalid hostname format', () {
      const config = EndpointConfig(
        host: 'invalid..hostname',
        port: 8080,
        useHttps: true,
      );

      expect(config.validate(), 'Invalid hostname or IP address format');
    });

    test('validate accepts valid IP addresses', () {
      const config = EndpointConfig(
        host: '192.168.1.100',
        port: 8080,
        useHttps: false,
      );

      expect(config.validate(), isNull);
    });

    test('validate rejects port below 1', () {
      const config = EndpointConfig(
        host: 'example.com',
        port: 0,
        useHttps: true,
      );

      expect(config.validate(), 'Port must be between 1 and 65535');
    });

    test('validate rejects port above 65535', () {
      const config = EndpointConfig(
        host: 'example.com',
        port: 65536,
        useHttps: true,
      );

      expect(config.validate(), 'Port must be between 1 and 65535');
    });

    test('equality operator works correctly', () {
      const config1 = EndpointConfig(
        host: 'example.com',
        port: 8080,
        useHttps: true,
      );

      const config2 = EndpointConfig(
        host: 'example.com',
        port: 8080,
        useHttps: true,
      );

      const config3 = EndpointConfig(
        host: 'other.com',
        port: 8080,
        useHttps: true,
      );

      expect(config1, equals(config2));
      expect(config1, isNot(equals(config3)));
    });
  });

  group('EndpointConfigStorage', () {
    late SharedPreferences prefs;
    late EndpointConfigStorage storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      storage = EndpointConfigStorage(prefs: prefs);
    });

    test('read returns null when no data stored', () async {
      final config = await storage.read();

      expect(config, isNull);
    });

    test('write and read persists configuration', () async {
      const testConfig = EndpointConfig(
        host: 'test.example.com',
        port: 9000,
        useHttps: true,
      );

      await storage.write(testConfig);
      final readConfig = await storage.read();

      expect(readConfig, equals(testConfig));
    });

    test('delete removes configuration', () async {
      const testConfig = EndpointConfig(
        host: 'test.example.com',
        port: 9000,
        useHttps: true,
      );

      await storage.write(testConfig);
      expect(await storage.read(), equals(testConfig));

      await storage.delete();
      expect(await storage.read(), isNull);
    });
  });

  group('EndpointConfigException', () {
    test('toString includes message', () {
      final exception = EndpointConfigException('Test error');

      expect(exception.toString(), 'EndpointConfigException: Test error');
    });
  });
}
