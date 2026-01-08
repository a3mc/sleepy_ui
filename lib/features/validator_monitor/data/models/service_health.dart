// Health endpoint response
class ServiceHealth {
  final String status;
  final String storage;
  final String monitor;
  final int uptimeSeconds;

  const ServiceHealth({
    required this.status,
    required this.storage,
    required this.monitor,
    required this.uptimeSeconds,
  });

  factory ServiceHealth.fromJson(Map<String, dynamic> json) {
    return ServiceHealth(
      status: json['status'] as String,
      storage: json['storage'] as String,
      monitor: json['monitor'] as String,
      uptimeSeconds: json['uptime_seconds'] as int,
    );
  }

  bool get isHealthy => status == 'healthy' && monitor == 'active';
}
