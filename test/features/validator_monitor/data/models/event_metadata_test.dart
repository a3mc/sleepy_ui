import 'package:flutter_test/flutter_test.dart';
import 'package:sleepy_ui/features/validator_monitor/data/models/event_metadata.dart';

void main() {
  group('TemporalInfo.fromJson', () {
    test('parses complete JSON with all fields present', () {
      final json = {
        'level': 'Warning',
        'alert_sent_this_cycle': true,
        'vote_distance': {
          'degraded': true,
          'consecutive_count': 5,
          'warning_threshold': 6,
          'critical_threshold': 12,
        },
        'root_distance': {
          'degraded': false,
          'consecutive_count': 0,
          'warning_threshold': 6,
          'critical_threshold': 12,
        },
        'credits': {
          'degraded': false,
          'consecutive_count': 0,
          'warning_threshold': 6,
          'critical_threshold': 12,
        },
        'counter_reset_threshold': 3,
      };

      final temporal = TemporalInfo.fromJson(json);

      expect(temporal.level, 'Warning');
      expect(temporal.alertSentThisCycle, true);
      expect(temporal.voteDistance.degraded, true);
      expect(temporal.counterResetThreshold, 3);
    });

    test('handles missing alert_sent_this_cycle field with false default', () {
      final json = {
        'level': 'None',
        // 'alert_sent_this_cycle': missing!
        'vote_distance': {
          'degraded': false,
          'consecutive_count': 0,
          'warning_threshold': 6,
          'critical_threshold': 12,
        },
        'root_distance': {
          'degraded': false,
          'consecutive_count': 0,
          'warning_threshold': 6,
          'critical_threshold': 12,
        },
        'credits': {
          'degraded': false,
          'consecutive_count': 0,
          'warning_threshold': 6,
          'critical_threshold': 12,
        },
        'counter_reset_threshold': 3,
      };

      final temporal = TemporalInfo.fromJson(json);

      // Should default to false instead of throwing
      expect(temporal.alertSentThisCycle, false);
      expect(temporal.level, 'None');
    });

    test('handles explicit null alert_sent_this_cycle with false default', () {
      final json = {
        'level': 'Critical',
        'alert_sent_this_cycle': null, // Explicit null
        'vote_distance': {
          'degraded': true,
          'consecutive_count': 8,
          'warning_threshold': 6,
          'critical_threshold': 12,
        },
        'root_distance': {
          'degraded': true,
          'consecutive_count': 8,
          'warning_threshold': 6,
          'critical_threshold': 12,
        },
        'credits': {
          'degraded': false,
          'consecutive_count': 0,
          'warning_threshold': 6,
          'critical_threshold': 12,
        },
        'counter_reset_threshold': 3,
      };

      final temporal = TemporalInfo.fromJson(json);

      expect(temporal.alertSentThisCycle, false);
      expect(temporal.level, 'Critical');
    });
  });

  group('ForkInfo.fromJson', () {
    test('parses complete JSON with all fields present', () {
      final json = {
        'phase': 'Stabilizing',
        'alert_sent_this_cycle': true,
        'loops_since_detection': 5,
        'gap_settle_wait': 8,
        'gap_stable_confirm': 3,
        'credits_lost': 76,
        'stabilized_credits_lost': null,
        'baseline_gap': 150,
        'current_gap': 226,
        'stabilized_gap': null,
      };

      final fork = ForkInfo.fromJson(json);

      expect(fork.phase, 'Stabilizing');
      expect(fork.alertSentThisCycle, true);
      expect(fork.loopsSinceDetection, 5);
      expect(fork.creditsLost, 76);
      expect(fork.stabilizedCreditsLost, null);
      expect(fork.baselineGap, 150);
      expect(fork.currentGap, 226);
      expect(fork.stabilizedGap, null);
    });

    test('handles missing alert_sent_this_cycle field with false default', () {
      final json = {
        'phase': 'Idle',
        // 'alert_sent_this_cycle': missing!
        'loops_since_detection': null,
        'gap_settle_wait': 8,
        'gap_stable_confirm': 3,
        'credits_lost': null,
        'stabilized_credits_lost': 64,
        'baseline_gap': null,
        'current_gap': null,
        'stabilized_gap': 214,
      };

      final fork = ForkInfo.fromJson(json);

      // Should default to false instead of throwing
      expect(fork.alertSentThisCycle, false);
      expect(fork.phase, 'Idle');
      expect(fork.stabilizedCreditsLost, 64);
      expect(fork.stabilizedGap, 214);
    });

    test('handles Idle phase with stabilized values', () {
      final json = {
        'phase': 'Idle',
        'alert_sent_this_cycle': false,
        'loops_since_detection': null,
        'gap_settle_wait': 8,
        'gap_stable_confirm': 3,
        'credits_lost': null,
        'stabilized_credits_lost': 64,
        'baseline_gap': null,
        'current_gap': null,
        'stabilized_gap': 214,
      };

      final fork = ForkInfo.fromJson(json);

      expect(fork.isIdle, true);
      expect(fork.loopsSinceDetection, null);
      expect(fork.creditsLost, null);
      expect(fork.stabilizedCreditsLost, 64);
      expect(fork.stabilizedGap, 214);
    });

    test('handles fork detection phase with current values', () {
      final json = {
        'phase': 'Stabilizing',
        'alert_sent_this_cycle': true,
        'loops_since_detection': 2,
        'gap_settle_wait': 8,
        'gap_stable_confirm': 3,
        'credits_lost': 76,
        'stabilized_credits_lost': null,
        'baseline_gap': 150,
        'current_gap': 226,
        'stabilized_gap': null,
      };

      final fork = ForkInfo.fromJson(json);

      expect(fork.isStabilizing, true);
      expect(fork.loopsSinceDetection, 2);
      expect(fork.creditsLost, 76);
      expect(fork.stabilizedCreditsLost, null);
      expect(fork.currentGap, 226);
    });
  });

  group('MetricState.fromJson', () {
    test('parses degraded metric state', () {
      final json = {
        'degraded': true,
        'consecutive_count': 5,
        'warning_threshold': 6,
        'critical_threshold': 12,
      };

      final metric = MetricState.fromJson(json);

      expect(metric.degraded, true);
      expect(metric.consecutiveCount, 5);
      expect(metric.warningThreshold, 6);
      expect(metric.criticalThreshold, 12);
    });

    test('parses healthy metric state', () {
      final json = {
        'degraded': false,
        'consecutive_count': 0,
        'warning_threshold': 6,
        'critical_threshold': 12,
      };

      final metric = MetricState.fromJson(json);

      expect(metric.degraded, false);
      expect(metric.consecutiveCount, 0);
    });
  });

  group('AlertPhaseInfo.fromJson', () {
    test('parses Idle phase', () {
      final json = {
        'phase': 'Idle',
        'count': 0,
        'threshold': 3,
      };

      final alert = AlertPhaseInfo.fromJson(json);

      expect(alert.phase, 'Idle');
      expect(alert.isIdle, true);
      expect(alert.count, 0);
      expect(alert.threshold, 3);
    });

    test('parses Active phase', () {
      final json = {
        'phase': 'Active',
        'count': 5,
        'threshold': 3,
      };

      final alert = AlertPhaseInfo.fromJson(json);

      expect(alert.phase, 'Active');
      expect(alert.isActive, true);
      expect(alert.count, 5);
    });
  });

  group('ForkInfo.progress', () {
    test('calculates progress during stabilization', () {
      final json = {
        'phase': 'Stabilizing',
        'alert_sent_this_cycle': false,
        'loops_since_detection': 5,
        'gap_settle_wait': 8,
        'gap_stable_confirm': 3,
        'credits_lost': 76,
        'stabilized_credits_lost': null,
        'baseline_gap': 150,
        'current_gap': 226,
        'stabilized_gap': null,
      };

      final fork = ForkInfo.fromJson(json);

      // Total cycles = 8 + 3 = 11, current = 5, progress = 5/11 ≈ 0.45
      expect(fork.progress, closeTo(0.45, 0.01));
    });

    test('returns null progress when Idle', () {
      final json = {
        'phase': 'Idle',
        'alert_sent_this_cycle': false,
        'loops_since_detection': null,
        'gap_settle_wait': 8,
        'gap_stable_confirm': 3,
        'credits_lost': null,
        'stabilized_credits_lost': 64,
        'baseline_gap': null,
        'current_gap': null,
        'stabilized_gap': 214,
      };

      final fork = ForkInfo.fromJson(json);

      expect(fork.progress, null);
    });
  });
}
