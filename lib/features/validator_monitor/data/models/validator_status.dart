// Status endpoint response model (polled every 5-10s)
class ValidatorStatus {
  final DateTime timestamp;
  final bool inDegradedState;
  final int degradedDurationSecs;
  final int epoch;
  final int rank;
  final bool delinquent;
  final int activeValidators;
  final int delinquentValidators;
  final String forkTrackingPhase;
  final int forkAlertLevel;
  final String forkAlertColor;
  final bool forkRequiresAttention;
  final double progressPercent;
  final String estimatedTimeRemaining;

  const ValidatorStatus({
    required this.timestamp,
    required this.inDegradedState,
    required this.degradedDurationSecs,
    required this.epoch,
    required this.rank,
    required this.delinquent,
    required this.activeValidators,
    required this.delinquentValidators,
    required this.forkTrackingPhase,
    required this.forkAlertLevel,
    required this.forkAlertColor,
    required this.forkRequiresAttention,
    required this.progressPercent,
    required this.estimatedTimeRemaining,
  });

  factory ValidatorStatus.fromJson(Map<String, dynamic> json) {
    final alertState = json['alert_state'] as Map<String, dynamic>;
    final general = json['general'] as Map<String, dynamic>;
    final ourValidator = json['our_validator'] as Map<String, dynamic>;

    // fork_tracking may be null during backend refactoring - handle gracefully
    final forkTracking = json['fork_tracking'] as Map<String, dynamic>?;
    final uiState = forkTracking?['ui_state'] as Map<String, dynamic>?;

    return ValidatorStatus(
      timestamp: DateTime.parse(json['timestamp'] as String),
      inDegradedState: alertState['in_degraded_state'] as bool,
      degradedDurationSecs: alertState['degraded_duration_secs'] as int,
      epoch: general['epoch'] as int,
      rank: ourValidator['rank'] as int,
      delinquent: ourValidator['delinquent'] as bool,
      activeValidators: general['validators_active'] as int,
      delinquentValidators: general['validators_delinquent'] as int,
      forkTrackingPhase: (forkTracking?['phase_name'] as String?) ?? 'Unknown',
      forkAlertLevel: (uiState?['alert_level'] as int?) ?? 0,
      forkAlertColor: (uiState?['color'] as String?) ?? 'gray',
      forkRequiresAttention: (uiState?['requires_attention'] as bool?) ?? false,
      progressPercent: (general['progress_percent'] as num?)?.toDouble() ?? 0.0,
      estimatedTimeRemaining:
          (general['estimated_time_remaining'] as String?) ?? 'N/A',
    );
  }
}
