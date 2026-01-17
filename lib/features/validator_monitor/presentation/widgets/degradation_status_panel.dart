import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../data/models/event_metadata.dart';
import '../../data/models/validator_snapshot.dart';
import '../providers/alert_sound_provider.dart';
import '../providers/sound_settings_provider.dart';

class DegradationStatusPanel extends ConsumerStatefulWidget {
  final EventMetadata? events;
  final int? currentCreditsGap; // Current gap to rank_1
  final int? creditsLost; // Calculated: confirmed_gap - detection_gap
  final int? gapAtDetection; // Gap when fork Stabilizing started
  final List<ValidatorSnapshot> snapshots; // For jitter detection

  const DegradationStatusPanel({
    super.key,
    required this.events,
    this.currentCreditsGap,
    this.creditsLost,
    this.gapAtDetection,
    required this.snapshots,
  });

  @override
  ConsumerState<DegradationStatusPanel> createState() =>
      _DegradationStatusPanelState();
}

class _DegradationStatusPanelState
    extends ConsumerState<DegradationStatusPanel> {
  String? _previousLevel; // Track level changes for recovery detection
  bool _degradationConfirmed =
      false; // Track if we've seen 2 consecutive losses

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(DegradationStatusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.events != null && widget.events != oldWidget.events) {
      unawaited(_processSoundTriggers());
    }
  }

  Future<void> _processSoundTriggers() async {
    try {
      final soundService = await ref.read(alertSoundServiceProvider.future);
      final soundEnabled = ref.read(soundEnabledProvider);

      // Check if latest snapshot is part of jitter cancellation
      final isJitter = _detectJitterCancellation();

      // Use BACKEND's temporal.level - same logic as visual markers
      final temporal = widget.events?.temporal;

      // BEEP: Start after 2 consecutive Credits losses, continue until full recovery
      if (widget.snapshots.length >= 2 && temporal != null && soundEnabled) {
        final latest = widget.snapshots.last.creditsPerformanceGap;
        final previous =
            widget.snapshots[widget.snapshots.length - 2].creditsPerformanceGap;
        final twoConsecutive = latest > 0 && previous > 0;
        final backendTracking = temporal.credits.consecutiveCount > 0;

        // Set flag when 2 consecutive confirmed
        if (twoConsecutive) {
          _degradationConfirmed = true;
        }

        // Reset flag when backend completes full recovery
        if (!backendTracking) {
          _degradationConfirmed = false;
        }

        // Beep once confirmed and backend still tracking
        if (_degradationConfirmed && backendTracking && !isJitter) {
          await soundService.playBeep();
        }
      }

      if (temporal != null) {
        final currentLevel = temporal.level;

        // ORANGE LINE (Warning alert sent): Warning→None (recovered before critical)
        if (currentLevel == 'None' && _previousLevel == 'Warning') {
          debugPrint(
              '[DegradationPanel] ORANGE LINE: Playing WARNING (recovered before critical)');
          await soundService.playWarning();
        }
        // RED LINE (Critical alert sent): any→Critical (escalated)
        else if (currentLevel == 'Critical' && _previousLevel != 'Critical') {
          debugPrint(
              '[DegradationPanel] RED LINE: Playing CRITICAL (escalated)');
          await soundService.playCritical();
        }
        // GREEN DOT (Recovery from critical): Critical→None
        else if (currentLevel == 'None' && _previousLevel == 'Critical') {
          debugPrint(
              '[DegradationPanel] GREEN DOT: Playing RECOVERY (recovered from critical)');
          await soundService.playRecovery();
        }

        _previousLevel = currentLevel;
      }
    } catch (e) {
      debugPrint('[DegradationStatusPanel] Sound trigger error: $e');
    }
  }

  /// Detect if current snapshot is part of a jitter cancellation pattern
  /// Uses EXACT same logic as circular_blade_painter.dart "holes drilling"
  /// Returns true if latest snapshot is in a grayed (canceled) segment
  bool _detectJitterCancellation() {
    if (widget.snapshots.length < 2) return false;

    // Check last ~10 snapshots for cancellation pairs (same as visual buffer)
    final checkCount = widget.snapshots.length.clamp(2, 10);
    final startIdx = widget.snapshots.length - checkCount;

    // Find all grayed segments (EXACT painter logic from circular_blade_painter.dart:184-188)
    final grayedIndices = <int>{};
    for (int i = 0; i < checkCount - 1; i++) {
      final currentIdx = startIdx + i;
      final nextIdx = startIdx + i + 1;

      final currentGap = widget.snapshots[currentIdx].creditsPerformanceGap;
      final nextGap = widget.snapshots[nextIdx].creditsPerformanceGap;

      // Zero tolerance: exact cancellation only, exclude (0,0) pairs
      if (currentGap + nextGap == 0 && currentGap != 0) {
        grayedIndices.add(currentIdx);
        grayedIndices.add(nextIdx);
      }
    }

    // Check if latest snapshot (last index) is grayed
    final latestIdx = widget.snapshots.length - 1;
    final isGrayed = grayedIndices.contains(latestIdx);

    if (isGrayed) {
      final latest = widget.snapshots[latestIdx].creditsPerformanceGap;
      debugPrint(
          '[DegradationPanel] JITTER SUPPRESSION: latest snapshot (gap=$latest) is in grayed segment');
    }

    return isGrayed;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events == null) return const SizedBox.shrink();

    final activeDetections = _getAllDetections();

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 300),
        tween: Tween(begin: 0.0, end: 1.0),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: child,
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: _getBorderColor(activeDetections),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: _getBorderColor(activeDetections).withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(activeDetections),
              ...activeDetections.map(
                (detection) => _buildDetectionItem(detection),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(List<_Detection> detections) {
    final maxSeverity = detections.isEmpty
        ? 0
        : detections.map((d) => d.severity).reduce(math.max);

    final priorityOrder = ['V Halt', 'N Halt', 'Credits', 'Vote', 'Root'];

    final criticalDetections =
        detections.where((d) => d.severity >= 3).toList();
    final warningDetections = detections.where((d) => d.severity == 2).toList();
    criticalDetections.sort((a, b) {
      final aIndex = priorityOrder.indexOf(a.label);
      final bIndex = priorityOrder.indexOf(b.label);
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });
    warningDetections.sort((a, b) {
      final aIndex = priorityOrder.indexOf(a.label);
      final bIndex = priorityOrder.indexOf(b.label);
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });

    IconData icon;
    String title;
    Color color;

    if (maxSeverity >= 3) {
      icon = Icons.error;
      if (criticalDetections.length == 1) {
        title = 'CRITICAL: ${criticalDetections.first.label.toUpperCase()}';
      } else {
        title = 'CRITICAL ALERTS ACTIVE (${criticalDetections.length})';
      }
      color = const Color(0xFFFF0000);
    } else if (maxSeverity >= 2) {
      icon = Icons.warning;
      if (warningDetections.length == 1) {
        title = 'WARNING: ${warningDetections.first.label.toUpperCase()}';
      } else {
        title = 'WARNING ALERTS ACTIVE (${warningDetections.length})';
      }
      color = const Color(0xFFFF6600);
    } else {
      icon = Icons.check_circle_outline;
      title = 'SYSTEM MONITORING';
      color = const Color(0xFF4CAF50);
    }

    // Add reset threshold to title when available
    final resetInfo = widget.events != null
        ? ' • Reset: ${widget.events!.temporal.counterResetThreshold}'
        : '';

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              if (resetInfo.isNotEmpty)
                Text(
                  resetInfo,
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetectionItem(_Detection detection) {
    // Wrapped item with subtle background for visual separation
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A), // Subtle background
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: detection.color.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // First line: • Label: [████████████]
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Dot indicator
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: detection.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: detection.color.withValues(alpha: 0.5),
                      blurRadius: 4,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Label
              SizedBox(
                width: 55,
                child: Text(
                  '${detection.label}:',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Progress bar (takes remaining space)
              Expanded(
                child: _buildProgressBar(detection),
              ),
            ],
          ),
          // Second line: Status text
          Padding(
            padding: const EdgeInsets.only(left: 69, top: 1),
            child: Text(
              detection.statusText,
              style: TextStyle(
                color: detection.color,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(_Detection detection) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Background track
            Container(
              height: 5, // Reduced from 6 for compact layout
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            // Progress fill with gradient
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 400),
              tween: Tween(begin: 0.0, end: detection.progress),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                final width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth * value
                    : 0.0;
                return Container(
                  height: 5, // Reduced from 6
                  width: width,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        detection.color.withValues(alpha: 0.6),
                        detection.color,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2.5),
                    boxShadow: [
                      BoxShadow(
                        color: detection.color.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                );
              },
            ),
            // Threshold markers
            if (detection.thresholdMarkers != null)
              ...detection.thresholdMarkers!.map((marker) {
                return Positioned(
                  left: constraints.maxWidth * marker.position - 1,
                  child: Container(
                    width: 2,
                    height: 5, // Match progress bar height
                    color: marker.color,
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  List<_Detection> _getAllDetections() {
    final detections = <_Detection>[];

    final vote = widget.events!.temporal.voteDistance;
    final root = widget.events!.temporal.rootDistance;
    final credits = widget.events!.temporal.credits;

    detections.add(_Detection(
      label: 'Vote',
      count: vote.consecutiveCount,
      warningThreshold: vote.warningThreshold,
      criticalThreshold: vote.criticalThreshold,
      level: widget.events!.temporal.level,
      resetThreshold: widget.events!.temporal.counterResetThreshold,
      isActive: vote.degraded,
    ));

    detections.add(_Detection(
      label: 'Root',
      count: root.consecutiveCount,
      warningThreshold: root.warningThreshold,
      criticalThreshold: root.criticalThreshold,
      level: widget.events!.temporal.level,
      resetThreshold: widget.events!.temporal.counterResetThreshold,
      isActive: root.degraded,
    ));

    detections.add(_Detection(
      label: 'Credits',
      count: credits.consecutiveCount,
      warningThreshold: credits.warningThreshold,
      criticalThreshold: credits.criticalThreshold,
      level: widget.events!.temporal.level,
      resetThreshold: widget.events!.temporal.counterResetThreshold,
      isActive: credits.degraded,
    ));

    if (widget.events!.delinquent.isDetecting ||
        widget.events!.delinquent.isActive) {
      detections.add(_Detection.validatorAlert(
        label: 'Entity Inactive',
        alert: widget.events!.delinquent,
      ));
    }

    if (widget.events!.creditsStagnant.isDetecting ||
        widget.events!.creditsStagnant.isActive) {
      detections.add(_Detection.validatorAlert(
        label: 'V Halt',
        alert: widget.events!.creditsStagnant,
      ));
    } else {
      // Show as healthy when not detecting
      detections.add(_Detection.placeholder(
        label: 'V Halt',
      ));
    }

    if (widget.events!.networkHalted.isDetecting ||
        widget.events!.networkHalted.isActive) {
      detections.add(_Detection.validatorAlert(
        label: 'N Halt',
        alert: widget.events!.networkHalted,
      ));
    } else {
      // Show as healthy when not detecting
      detections.add(_Detection.placeholder(
        label: 'N Halt',
      ));
    }

    return detections;
  }

  Color _getBorderColor(List<_Detection> detections) {
    if (detections.isEmpty) return const Color(0xFF4CAF50);
    final maxSeverity = detections.map((d) => d.severity).reduce(math.max);
    if (maxSeverity >= 3) return const Color(0xFFFF0000);
    if (maxSeverity >= 2) return const Color(0xFFFF6600);
    if (maxSeverity >= 1) return const Color(0xFF9370DB); // Purple for fork
    return const Color(0xFF4CAF50);
  }
}

class _Detection {
  final String label;
  final Color color;
  final double progress;
  final String statusText;
  final String? subtitle;
  final int severity;
  final List<_ThresholdMarker>? thresholdMarkers;
  final bool isActive;
  final int resetThreshold;

  _Detection({
    required this.label,
    required int count,
    required int warningThreshold,
    required int criticalThreshold,
    required String level,
    required this.resetThreshold,
    this.isActive = true,
  })  : color = _getTemporalColor(
            count, warningThreshold, criticalThreshold, level),
        progress = count / criticalThreshold,
        statusText = _getTemporalStatus(
            count, warningThreshold, criticalThreshold, level),
        subtitle = isActive
            ? _getTemporalSubtitle(count, warningThreshold, criticalThreshold,
                level, resetThreshold)
            : 'No degradation detected',
        severity =
            _getTemporalSeverity(count, warningThreshold, criticalThreshold),
        thresholdMarkers = [
          _ThresholdMarker(
            position: warningThreshold / criticalThreshold,
            color:
                count > 0 ? const Color(0xFFFF6600) : const Color(0xFF303030),
          ),
          _ThresholdMarker(
            position: 1.0,
            color:
                count > 0 ? const Color(0xFFFF0000) : const Color(0xFF303030),
          ),
        ];

  _Detection.validatorAlert({
    required this.label,
    required AlertPhaseInfo alert,
  })  : color =
            alert.isActive ? const Color(0xFFFF6600) : const Color(0xFFFFAA00),
        progress = alert.count / alert.threshold,
        statusText = '${alert.count}/${alert.threshold} cycles',
        subtitle = alert.isActive
            ? 'Alert confirmed and active'
            : 'Confirming before alert',
        severity = alert.isActive ? 2 : 1,
        thresholdMarkers = null,
        isActive = alert.isDetecting || alert.isActive,
        resetThreshold = 0;

  // Placeholder for always-visible but inactive alerts
  _Detection.placeholder({
    required this.label,
  })  : color = const Color(0xFF4CAF50), // Green for healthy
        progress = 0.0,
        statusText = 'Healthy',
        subtitle = 'No issues detected',
        severity = 0,
        thresholdMarkers = null,
        isActive = false,
        resetThreshold = 0;

  static Color _getTemporalColor(
      int count, int warning, int critical, String level) {
    if (level == 'Critical') return const Color(0xFFFF0000); // Red
    if (level == 'Warning') return const Color(0xFFFF6600); // Orange
    if (count == 0) return const Color(0xFF4CAF50); // Green when healthy
    if (count >= warning * 0.8) {
      return const Color(0xFFFFAA00); // Yellow - approaching warning
    }
    return const Color(0xFFAAAAAA); // Gray - accumulating but low
  }

  static String _getTemporalStatus(
      int count, int warning, int critical, String level) {
    if (count == 0) return 'Healthy';
    if (level == 'Critical') return 'CRITICAL ALERT';
    if (level == 'Warning') return 'WARNING ALERT';
    final toWarning = warning - count;
    if (toWarning <= 2) return 'WARNING IN $toWarning';
    return '$count/$critical cycles';
  }

  static String? _getTemporalSubtitle(
      int count, int warning, int critical, String level, int resetThreshold) {
    if (level == 'Critical') return 'Alert sent at $critical cycles';
    if (level == 'Warning') return 'Alert sent at $warning cycles';
    if (count == 0) return 'Needs $resetThreshold consecutive healthy to reset';
    return 'Warning at $warning, Critical at $critical';
  }

  static int _getTemporalSeverity(int count, int warning, int critical) {
    if (count >= critical) return 3; // Critical
    if (count >= warning) return 2; // Warning
    if (count > 0) return 1; // Accumulating (for beep sounds)
    return 0; // Healthy
  }
}

class _ThresholdMarker {
  final double position; // 0.0 to 1.0
  final Color color;

  _ThresholdMarker({
    required this.position,
    required this.color,
  });
}
