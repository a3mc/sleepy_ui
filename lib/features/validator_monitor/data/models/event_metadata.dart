// Event metadata models for timeline reconstruction
// Spec: docs/ALERTS_METADATA_SPEC.md

class AlertPhaseInfo {
  final String phase; // "Idle" | "Detecting" | "Active" | "Recovering"
  final int count;
  final int threshold;

  const AlertPhaseInfo({
    required this.phase,
    required this.count,
    required this.threshold,
  });

  factory AlertPhaseInfo.fromJson(Map<String, dynamic> json) {
    return AlertPhaseInfo(
      phase: json['phase'] as String,
      count: json['count'] as int,
      threshold: json['threshold'] as int,
    );
  }

  bool get isIdle => phase == 'Idle';
  bool get isDetecting => phase == 'Detecting';
  bool get isActive => phase == 'Active';
  bool get isRecovering => phase == 'Recovering';
}

class MetricState {
  final bool degraded;
  final int consecutiveCount;
  final int warningThreshold;
  final int criticalThreshold;

  const MetricState({
    required this.degraded,
    required this.consecutiveCount,
    required this.warningThreshold,
    required this.criticalThreshold,
  });

  factory MetricState.fromJson(Map<String, dynamic> json) {
    return MetricState(
      degraded: json['degraded'] as bool,
      consecutiveCount: json['consecutive_count'] as int,
      warningThreshold: json['warning_threshold'] as int,
      criticalThreshold: json['critical_threshold'] as int,
    );
  }
}

class TemporalInfo {
  final String level; // "None" | "Warning" | "Critical"
  final bool alertSentThisCycle; // Alert delivery marker for timeline
  final MetricState voteDistance;
  final MetricState rootDistance;
  final MetricState credits;
  // DATA-04: Consecutive healthy cycles required to reset counters
  final int counterResetThreshold;

  const TemporalInfo({
    required this.level,
    // DATA-04: Defaults to false if backend omits field (indicates no alert sent this cycle)
    required this.alertSentThisCycle,
    required this.voteDistance,
    required this.rootDistance,
    required this.credits,
    required this.counterResetThreshold,
  });

  factory TemporalInfo.fromJson(Map<String, dynamic> json) {
    return TemporalInfo(
      level: json['level'] as String,
      // DATA-04: Defaults to false if backend omits field (no alert sent this cycle)
      alertSentThisCycle: (json['alert_sent_this_cycle'] as bool?) ?? false,
      voteDistance:
          MetricState.fromJson(json['vote_distance'] as Map<String, dynamic>),
      rootDistance:
          MetricState.fromJson(json['root_distance'] as Map<String, dynamic>),
      credits: MetricState.fromJson(json['credits'] as Map<String, dynamic>),
      counterResetThreshold: json['counter_reset_threshold'] as int,
    );
  }

  bool get isWarning => level == 'Warning';
  bool get isCritical => level == 'Critical';
  bool get isNone => level == 'None';
}

/// Historical fork alert data (persists after event completes)
class ForkAlertData {
  final String eventId;
  final int detectedAt; // Unix timestamp (seconds)
  final int creditsLost; // Initial credits lost at detection
  final int stabilizedCreditsLost; // Final credits lost after stabilization
  final int baselineGap;
  final int currentGap;
  final int stabilizedGap;
  final double? rankAveraged;
  final int? loopsToStabilize;
  final int? stabilizedRootDistance;
  final int? stabilizedVoteDistance;
  final int? creditsRecovered;
  final bool? recoveredToTip;

  const ForkAlertData({
    required this.eventId,
    required this.detectedAt,
    required this.creditsLost,
    required this.stabilizedCreditsLost,
    required this.baselineGap,
    required this.currentGap,
    required this.stabilizedGap,
    this.rankAveraged,
    this.loopsToStabilize,
    this.stabilizedRootDistance,
    this.stabilizedVoteDistance,
    this.creditsRecovered,
    this.recoveredToTip,
  });

  factory ForkAlertData.fromJson(Map<String, dynamic> json) {
    return ForkAlertData(
      eventId: json['event_id'] as String,
      detectedAt: json['detected_at'] as int,
      creditsLost: json['credits_lost'] as int,
      stabilizedCreditsLost: json['stabilized_credits_lost'] as int,
      baselineGap: json['baseline_gap'] as int,
      currentGap: json['current_gap'] as int,
      stabilizedGap: json['stabilized_gap'] as int,
      rankAveraged: (json['rank_averaged'] as num?)?.toDouble(),
      loopsToStabilize: json['loops_to_stabilize'] as int?,
      stabilizedRootDistance: json['stabilized_root_distance'] as int?,
      stabilizedVoteDistance: json['stabilized_vote_distance'] as int?,
      creditsRecovered: json['credits_recovered'] as int?,
      recoveredToTip: json['recovered_to_tip'] as bool?,
    );
  }
}

class ForkInfo {
  final String phase; // "Idle" | "Stabilizing" | "RankSampling" | "Confirmed"
  final bool alertSentThisCycle; // Transient flag for current cycle
  final String? eventId; // Current event being tracked
  final int? detectedAt; // Unix timestamp when current fork detected
  final int? loopsSinceDetection; // null when Idle
  final int gapSettleWait;
  final int gapStableConfirm;
  final int? forkCooldownCycles; // Total cooldown duration (config)
  final int? cooldownCyclesRemaining; // Countdown timer (during cooldown)
  final int? creditsLost; // Current tracking: immediate detection value
  final int? stabilizedCreditsLost; // Current tracking: final loss
  final int? baselineGap; // Current tracking: gap before fork
  final int? currentGap; // Current tracking: real-time gap
  final int? stabilizedGap; // Current tracking: final settled gap
  final ForkAlertData? lastAlert; // Historical: most recent completed alert

  const ForkInfo({
    required this.phase,
    required this.alertSentThisCycle,
    this.eventId,
    this.detectedAt,
    required this.loopsSinceDetection,
    required this.gapSettleWait,
    required this.gapStableConfirm,
    this.forkCooldownCycles,
    this.cooldownCyclesRemaining,
    this.creditsLost,
    this.stabilizedCreditsLost,
    this.baselineGap,
    this.currentGap,
    this.stabilizedGap,
    this.lastAlert,
  });

  factory ForkInfo.fromJson(Map<String, dynamic> json) {
    final lastAlertJson = json['last_alert'] as Map<String, dynamic>?;
    return ForkInfo(
      phase: json['phase'] as String,
      // DATA-04: Defaults to false if backend omits field (no alert sent this cycle)
      alertSentThisCycle: (json['alert_sent_this_cycle'] as bool?) ?? false,
      eventId: json['event_id'] as String?,
      detectedAt: json['detected_at'] as int?,
      loopsSinceDetection: json['loops_since_detection'] as int?,
      gapSettleWait: json['gap_settle_wait'] as int,
      gapStableConfirm: json['gap_stable_confirm'] as int,
      forkCooldownCycles: json['fork_cooldown_cycles'] as int?,
      cooldownCyclesRemaining: json['cooldown_cycles_remaining'] as int?,
      creditsLost: json['credits_lost'] as int?,
      stabilizedCreditsLost: json['stabilized_credits_lost'] as int?,
      baselineGap: json['baseline_gap'] as int?,
      currentGap: json['current_gap'] as int?,
      stabilizedGap: json['stabilized_gap'] as int?,
      lastAlert:
          lastAlertJson != null ? ForkAlertData.fromJson(lastAlertJson) : null,
    );
  }

  bool get isIdle => phase == 'Idle';
  bool get isStabilizing => phase == 'Stabilizing';
  bool get isRankSampling => phase == 'RankSampling';
  bool get isConfirmed => phase == 'Confirmed';

  double? get progress {
    if (loopsSinceDetection == null) return null;
    final totalCycles = gapSettleWait + gapStableConfirm;
    return (loopsSinceDetection! / totalCycles).clamp(0.0, 1.0);
  }
}

class EpochBoundaryInfo {
  final bool inWindow;
  final int loopsRemaining;
  final bool suppressingAlerts;

  const EpochBoundaryInfo({
    required this.inWindow,
    required this.loopsRemaining,
    required this.suppressingAlerts,
  });

  factory EpochBoundaryInfo.fromJson(Map<String, dynamic> json) {
    return EpochBoundaryInfo(
      inWindow: json['in_window'] as bool,
      loopsRemaining: json['loops_remaining'] as int,
      suppressingAlerts: json['suppressing_alerts'] as bool,
    );
  }
}

class EventMetadata {
  final AlertPhaseInfo delinquent;
  final AlertPhaseInfo creditsStagnant;
  final AlertPhaseInfo networkHalted;
  final TemporalInfo temporal;
  final ForkInfo fork;
  final EpochBoundaryInfo epochBoundary;

  const EventMetadata({
    required this.delinquent,
    required this.creditsStagnant,
    required this.networkHalted,
    required this.temporal,
    required this.fork,
    required this.epochBoundary,
  });

  factory EventMetadata.fromJson(Map<String, dynamic> json) {
    return EventMetadata(
      delinquent:
          AlertPhaseInfo.fromJson(json['delinquent'] as Map<String, dynamic>),
      creditsStagnant: AlertPhaseInfo.fromJson(
          json['credits_stagnant'] as Map<String, dynamic>),
      networkHalted: AlertPhaseInfo.fromJson(
          json['network_halted'] as Map<String, dynamic>),
      temporal: TemporalInfo.fromJson(json['temporal'] as Map<String, dynamic>),
      fork: ForkInfo.fromJson(json['fork'] as Map<String, dynamic>),
      epochBoundary: EpochBoundaryInfo.fromJson(
          json['epoch_boundary'] as Map<String, dynamic>),
    );
  }
}
