import '../../../features/validator_monitor/presentation/providers/endpoint_config_provider.dart';

// API endpoint configuration
class ApiConstants {
  // Dynamic base URL - reads from EndpointConfigProvider
  // Throws exception if no endpoint configured
  static String getBaseUrl(EndpointConfig? config) {
    if (config == null) {
      throw Exception('No endpoint configured - configure in Settings');
    }
    return config.baseUrl;
  }

  // Endpoints
  static const String streamPath = '/stream';
  static const String statusPath = '/status';
  static const String healthPath = '/health';
  static const String historyPath = '/history';

  // Timeouts
  static const Duration httpTimeout = Duration(seconds: 30);
  static const Duration sseReconnectDelay = Duration(seconds: 2);
  static const Duration maxReconnectDelay = Duration(seconds: 30);

  // Polling intervals
  static const Duration statusPollInterval = Duration(seconds: 8);
  static const Duration healthCheckInterval = Duration(seconds: 60);

  // Data buffer configuration
  static const int maxHistoryBuffer = 60; // 60 seconds rolling window
  static const Duration staleDataThreshold = Duration(seconds: 5);
  static const Duration gapBackfillThreshold = Duration(seconds: 5);
}
