import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../../data/models/event_metadata.dart';

/// Completed fork incident record
class ForkIncident {
  final DateTime timestamp;
  final String? eventId;
  final int creditsLost; // Immediate detection value
  final int stabilizedCreditsLost; // Final accurate loss
  final int baselineGap;
  final int stabilizedGap;
  final Duration detectionDuration; // Time from detection to alert

  const ForkIncident({
    required this.timestamp,
    this.eventId,
    required this.creditsLost,
    required this.stabilizedCreditsLost,
    required this.baselineGap,
    required this.stabilizedGap,
    required this.detectionDuration,
  });

  int get actualLoss => stabilizedCreditsLost;
  int get lossDiscrepancy => (stabilizedCreditsLost - creditsLost).abs();
  bool get hadWorsening => stabilizedCreditsLost > creditsLost;
}

/// Fork incident history state
class ForkHistoryState {
  final List<ForkIncident> incidents;
  final DateTime? lastIncidentTime;
  final int totalCreditsLost;

  const ForkHistoryState({
    required this.incidents,
    this.lastIncidentTime,
    required this.totalCreditsLost,
  });

  ForkHistoryState copyWith({
    List<ForkIncident>? incidents,
    DateTime? lastIncidentTime,
    int? totalCreditsLost,
  }) {
    return ForkHistoryState(
      incidents: incidents ?? this.incidents,
      lastIncidentTime: lastIncidentTime ?? this.lastIncidentTime,
      totalCreditsLost: totalCreditsLost ?? this.totalCreditsLost,
    );
  }
}

/// Fork history notifier
/// Tracks completed fork events via last_alert.event_id changes
class ForkHistoryNotifier extends StateNotifier<ForkHistoryState> {
  ForkHistoryNotifier()
      : super(const ForkHistoryState(
          incidents: [],
          totalCreditsLost: 0,
        ));

  // Track last seen event_id to detect new alerts
  String? _lastSeenEventId;

  /// Update fork state and detect new completed alerts
  void updateForkState(ForkInfo fork) {
    final lastAlert = fork.lastAlert;

    // No alert data yet
    if (lastAlert == null) return;

    // Detect new alert by event_id change (reliable even if cycles missed)
    if (lastAlert.eventId != _lastSeenEventId) {
      if (kDebugMode) {
        print('[ForkHistory] [✓] New fork alert detected!');
        print('[ForkHistory]   - Event ID: ${lastAlert.eventId}');
        print(
            '[ForkHistory]   - Credits lost (initial): ${lastAlert.creditsLost}');
        print(
            '[ForkHistory]   - Stabilized loss: ${lastAlert.stabilizedCreditsLost}');
        print(
            '[ForkHistory]   - Recovered to tip: ${lastAlert.recoveredToTip}');
      }

      // Convert Unix timestamp to DateTime
      final timestamp =
          DateTime.fromMillisecondsSinceEpoch(lastAlert.detectedAt * 1000);

      final incident = ForkIncident(
        timestamp: timestamp,
        eventId: lastAlert.eventId,
        creditsLost: lastAlert.creditsLost,
        stabilizedCreditsLost: lastAlert.stabilizedCreditsLost,
        baselineGap: lastAlert.baselineGap,
        stabilizedGap: lastAlert.stabilizedGap,
        detectionDuration: Duration(
            seconds: (lastAlert.loopsToStabilize ?? 0) * 3), // loops * 3sec
      );

      _addIncident(incident);
      _lastSeenEventId = lastAlert.eventId;

      if (kDebugMode) {
        print(
            '[ForkHistory] [✓] Incident recorded! Total incidents: ${state.incidents.length}, Total loss: ${state.totalCreditsLost}');
      }
    }
  }

  void _addIncident(ForkIncident incident) {
    final updatedIncidents = [...state.incidents, incident];
    final totalLoss = updatedIncidents.fold<int>(
      0,
      (sum, inc) => sum + inc.stabilizedCreditsLost,
    );

    state = ForkHistoryState(
      incidents: updatedIncidents,
      lastIncidentTime: incident.timestamp,
      totalCreditsLost: totalLoss,
    );
  }

  /// Clear all history
  void clearHistory() {
    state = const ForkHistoryState(
      incidents: [],
      totalCreditsLost: 0,
    );
    _lastSeenEventId = null;
  }

  /// Remove specific incident
  void removeIncident(int index) {
    if (index < 0 || index >= state.incidents.length) return;

    final updatedIncidents = List<ForkIncident>.from(state.incidents)
      ..removeAt(index);

    final totalLoss = updatedIncidents.fold<int>(
      0,
      (sum, inc) => sum + inc.stabilizedCreditsLost,
    );

    state = ForkHistoryState(
      incidents: updatedIncidents,
      lastIncidentTime:
          updatedIncidents.isNotEmpty ? updatedIncidents.last.timestamp : null,
      totalCreditsLost: totalLoss,
    );
  }

  /// Add test data (development only)
  void addTestIncidents() {
    if (!kDebugMode) return;

    final now = DateTime.now();
    final testIncidents = [
      ForkIncident(
        timestamp: now.subtract(const Duration(hours: 3, minutes: 45)),
        eventId: 'test-fork-001',
        creditsLost: 42,
        stabilizedCreditsLost: 58,
        baselineGap: -180,
        stabilizedGap: -194,
        detectionDuration: const Duration(seconds: 87),
      ),
      ForkIncident(
        timestamp: now.subtract(const Duration(hours: 2, minutes: 15)),
        eventId: 'test-fork-002',
        creditsLost: 31,
        stabilizedCreditsLost: 31,
        baselineGap: -145,
        stabilizedGap: -145,
        detectionDuration: const Duration(seconds: 62),
      ),
      ForkIncident(
        timestamp: now.subtract(const Duration(hours: 1, minutes: 20)),
        eventId: 'test-fork-003',
        creditsLost: 89,
        stabilizedCreditsLost: 112,
        baselineGap: -267,
        stabilizedGap: -295,
        detectionDuration: const Duration(seconds: 104),
      ),
      ForkIncident(
        timestamp: now.subtract(const Duration(minutes: 38)),
        eventId: 'test-fork-004',
        creditsLost: 24,
        stabilizedCreditsLost: 28,
        baselineGap: -98,
        stabilizedGap: -102,
        detectionDuration: const Duration(seconds: 71),
      ),
      ForkIncident(
        timestamp: now.subtract(const Duration(minutes: 12)),
        eventId: 'test-fork-005',
        creditsLost: 67,
        stabilizedCreditsLost: 73,
        baselineGap: -201,
        stabilizedGap: -218,
        detectionDuration: const Duration(seconds: 93),
      ),
    ];

    for (final incident in testIncidents) {
      _addIncident(incident);
    }

    if (kDebugMode) {
      print(
          '[ForkHistory] [✓] Added ${testIncidents.length} test incidents. Total: ${state.totalCreditsLost}');
    }
  }
}

/// Fork incident history provider
final forkHistoryProvider =
    StateNotifierProvider<ForkHistoryNotifier, ForkHistoryState>((ref) {
  return ForkHistoryNotifier();
});
