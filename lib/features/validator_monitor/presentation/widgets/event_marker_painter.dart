import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../data/models/validator_snapshot.dart';
import '../../data/models/event_metadata.dart';

// Renders 4 concentric marker rings around circular blade for event visualization
// Ring 1 (innermost): Validator alerts (delinquent/credits_stagnant/network_halted)
// Ring 2: Temporal degradation (vote/root/credits combined)
// Ring 3: Fork detection events
// Ring 4 (outermost): Epoch boundary suppression
//
// Coordinate System: Angles measured from 3 o'clock (0 radians) counter-clockwise
// 12 o'clock = -π/2, 3 o'clock = 0, 6 o'clock = π/2, 9 o'clock = π
class EventMarkerPainter extends CustomPainter {
  final List<ValidatorSnapshot> snapshots;
  final double innerRadius; // Start radius for marker rings
  final double ringSpacing; // Space between rings
  final double ringThickness; // Height of each ring

  EventMarkerPainter({
    required this.snapshots,
    required this.innerRadius,
    this.ringSpacing = 3.5,
    this.ringThickness = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    if (snapshots.isEmpty) return;

    // Calculate angle per segment (60 segments, newest at 12 o'clock)
    const segmentCount = 60;
    const sweepAngle = (2 * math.pi) / segmentCount;
    const newestAngle = -math.pi / 2; // 12 o'clock position

    // Find start index (show last 60 or all if less)
    final snapshotCount = snapshots.length;
    final startIndex =
        snapshotCount > segmentCount ? snapshotCount - segmentCount : 0;
    final itemsToDraw =
        snapshotCount > segmentCount ? segmentCount : snapshotCount;

    // Pre-compute ring radii to avoid repeated calculations in loop (performance optimization)
    final ring1Radius = innerRadius;
    final ring2Radius = innerRadius + ringSpacing + ringThickness;
    final ring3Radius = ring2Radius + ringSpacing + ringThickness;
    final ring4Radius = ring3Radius + ringSpacing + ringThickness;

    // Render event TRANSITIONS only (when phase changes)
    // CRITICAL: Draw from newest backward (same as blade rotation logic)
    for (int i = 0; i < itemsToDraw; i++) {
      // Index from newest (buffer end) backward in time
      final snapshotIndex = startIndex + (itemsToDraw - 1 - i);
      final snapshot = snapshots[snapshotIndex];

      // Extract events to avoid force unwrap
      final events = snapshot.events;
      if (events == null) continue;

      // Get previous snapshot for transition detection
      final prevSnapshot =
          snapshotIndex > 0 ? snapshots[snapshotIndex - 1] : null;

      // Calculate angle: newest at 12 o'clock, going clockwise
      final angle = newestAngle + (i * sweepAngle);

      // Ring 1: Validator alerts (only on phase transitions)
      _paintValidatorAlerts(
        canvas,
        center,
        angle,
        sweepAngle,
        ring1Radius,
        events,
        prevSnapshot?.events,
      );

      // Ring 2: Temporal degradation (trigger + resolution only)
      _paintTemporalDegradation(
        canvas,
        center,
        angle,
        sweepAngle,
        ring2Radius,
        events.temporal,
        prevSnapshot?.events?.temporal,
      );

      // Ring 3: Fork detection (phase changes only)
      _paintForkDetection(
        canvas,
        center,
        angle,
        sweepAngle,
        ring3Radius,
        events.fork,
        prevSnapshot?.events?.fork,
      );

      // Ring 4: Epoch boundary (entry/exit only)
      _paintEpochBoundary(
        canvas,
        center,
        angle,
        sweepAngle,
        ring4Radius,
        events.epochBoundary,
        prevSnapshot?.events?.epochBoundary,
      );
    }
  }

  void _paintValidatorAlerts(
    Canvas canvas,
    Offset center,
    double angle,
    double sweepAngle,
    double radius,
    EventMetadata events,
    EventMetadata? prevEvents,
  ) {
    final alerts = [
      (events.delinquent, prevEvents?.delinquent, 'delinquent'),
      (events.creditsStagnant, prevEvents?.creditsStagnant, 'credits_stagnant'),
      (events.networkHalted, prevEvents?.networkHalted, 'network_halted'),
    ];

    Color? markerColor;
    bool isDelinquency = false;

    // Check for phase transitions
    for (final (alert, prevAlert, name) in alerts) {
      // Track if this is DELINQUENCY (most critical)
      final isDelinquent = name == 'delinquent';

      // GREEN: Transition to Recovering or back to Idle (RESOLUTION)
      if (alert.isRecovering && prevAlert?.isRecovering != true) {
        markerColor =
            const Color(0xFF4CAF50); // Professional green - recovery started
        isDelinquency = isDelinquent;
        break;
      }
      if (alert.isIdle && prevAlert != null && !prevAlert.isIdle) {
        markerColor = const Color(0xFF4CAF50); // Professional green - cleared
        isDelinquency = isDelinquent;
        break;
      }

      // RED SKULL: Delinquency Active (VALIDATOR DEAD - most critical)
      if (isDelinquent && alert.isActive && prevAlert?.isActive != true) {
        markerColor =
            const Color(0xFFFF0000); // Red - delinquency alert (CRITICAL)
        isDelinquency = true;
        break;
      }

      // ORANGE: Other alerts Active (less critical than delinquency)
      if (!isDelinquent && alert.isActive && prevAlert?.isActive != true) {
        markerColor = const Color(0xFFFF4500); // Orange-red - alert triggered
        break;
      }

      // AMBER: Delinquency Detecting (VERY SERIOUS WARNING)
      if (isDelinquent && alert.isDetecting && prevAlert?.isDetecting != true) {
        markerColor =
            const Color(0xFFFF8C00); // Dark orange/amber - delinquency building
        isDelinquency = true;
        break;
      }

      // GOLD: Other alerts Detecting (normal warning)
      if (!isDelinquent &&
          alert.isDetecting &&
          prevAlert?.isDetecting != true) {
        markerColor = const Color(
            0xFFFFD700); // Gold - detection started (distinct from orange)
        break;
      }
    }

    if (markerColor != null) {
      // Use special marker for delinquency
      if (isDelinquency) {
        _drawDelinquencyMarker(
            canvas, center, angle, sweepAngle, radius, markerColor);
      } else {
        _drawMarker(canvas, center, angle, sweepAngle, radius, markerColor);
      }
    }
  }

  void _paintTemporalDegradation(
    Canvas canvas,
    Offset center,
    double angle,
    double sweepAngle,
    double radius,
    TemporalInfo temporal,
    TemporalInfo? prevTemporal,
  ) {
    // Only mark TRANSITIONS, not continuous state
    Color? markerColor;

    // GREEN: Transition from Warning/Critical to None (RESOLVED)
    if (temporal.isNone && prevTemporal != null && !prevTemporal.isNone) {
      markerColor =
          const Color(0xFF4CAF50); // Professional green - degradation cleared
    }
    // RED: Transition to Critical (CRITICAL ALERT)
    else if (temporal.isCritical && prevTemporal?.isCritical != true) {
      markerColor = const Color(0xFFFF0000); // Red - critical alert fired
    }
    // ORANGE: Transition to Warning (WARNING ALERT)
    else if (temporal.isWarning &&
        prevTemporal?.isWarning != true &&
        !temporal.isCritical) {
      markerColor = const Color(0xFFFF6600); // Orange - warning alert fired
    }
    // GRAY: First degradation detected (TRIGGER)
    else if (prevTemporal != null) {
      final metrics = [
        temporal.voteDistance,
        temporal.rootDistance,
        temporal.credits
      ];
      final prevMetrics = [
        prevTemporal.voteDistance,
        prevTemporal.rootDistance,
        prevTemporal.credits
      ];

      final anyDegraded = metrics.any((m) => m.degraded);
      final wasAllHealthy = prevMetrics.every((m) => !m.degraded);

      if (anyDegraded && wasAllHealthy) {
        markerColor =
            const Color(0xFFAAAAAA); // Gray - degradation started (evaluation)
      }
    }

    if (markerColor != null) {
      _drawMarker(canvas, center, angle, sweepAngle, radius, markerColor);
    }
  }

  void _paintForkDetection(
    Canvas canvas,
    Offset center,
    double angle,
    double sweepAngle,
    double radius,
    ForkInfo fork,
    ForkInfo? prevFork,
  ) {
    // Only mark phase TRANSITIONS
    Color? markerColor;

    // PURPLE: Fork confirmed (credit loss confirmed as real fork)
    if (fork.isConfirmed && prevFork?.isConfirmed != true) {
      markerColor = const Color(0xFF9900FF); // Purple - fork confirmed
    }
    // CYAN: Fork cleared (analysis complete, NO fork detected)
    else if (fork.isIdle && prevFork != null && !prevFork.isIdle) {
      markerColor =
          const Color(0xFF00FFFF); // Cyan - fork cleared (false positive)
    }
    // BLUE: Fork detection phases (Stabilizing, RankSampling, etc)
    else if (fork.phase != 'Idle' &&
        fork.phase != 'Confirmed' &&
        prevFork != null &&
        fork.phase != prevFork.phase) {
      markerColor = const Color(0xFF0099FF); // Blue - fork analysis in progress
    }

    if (markerColor != null) {
      _drawMarker(canvas, center, angle, sweepAngle, radius, markerColor);
    }
  }

  void _paintEpochBoundary(
    Canvas canvas,
    Offset center,
    double angle,
    double sweepAngle,
    double radius,
    EpochBoundaryInfo epochBoundary,
    EpochBoundaryInfo? prevEpochBoundary,
  ) {
    // Only mark window entry/exit
    Color? markerColor;

    // Gray: Epoch boundary entered (suppression active)
    if (epochBoundary.inWindow && prevEpochBoundary?.inWindow != true) {
      markerColor = const Color(0xFFAAAAAA); // Gray - suppression started
    }
    // White: Epoch boundary exited (suppression cleared)
    else if (!epochBoundary.inWindow && prevEpochBoundary?.inWindow == true) {
      markerColor = const Color(0xFFFFFFFF); // White - suppression ended
    }

    if (markerColor != null) {
      _drawMarker(canvas, center, angle, sweepAngle, radius, markerColor);
    }
  }

  void _drawMarker(
    Canvas canvas,
    Offset center,
    double angle,
    double sweepAngle,
    double radius,
    Color color,
  ) {
    // Calculate position at angle
    final markerX = center.dx + radius * math.cos(angle + sweepAngle / 2);
    final markerY = center.dy + radius * math.sin(angle + sweepAngle / 2);
    final markerCenter = Offset(markerX, markerY);

    // Draw glow effect for visibility
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

    canvas.drawCircle(markerCenter, ringThickness, glowPaint);

    // Draw solid dot on top
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(markerCenter, ringThickness / 2, dotPaint);
  }

  // Special marker for delinquency events (VALIDATOR DEAD - most critical)
  void _drawDelinquencyMarker(
    Canvas canvas,
    Offset center,
    double angle,
    double sweepAngle,
    double radius,
    Color color,
  ) {
    // Calculate position at angle
    final markerX = center.dx + radius * math.cos(angle + sweepAngle / 2);
    final markerY = center.dy + radius * math.sin(angle + sweepAngle / 2);
    final markerCenter = Offset(markerX, markerY);

    // Strong glow for delinquency
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    // Draw warning triangle pointing DOWN (danger symbol)
    final path = Path();
    final size = ringThickness * 1.2; // Larger than regular markers

    // Triangle vertices (pointing down - warning/danger symbol)
    path.moveTo(markerCenter.dx, markerCenter.dy + size); // Bottom point
    path.lineTo(markerCenter.dx - size * 0.866,
        markerCenter.dy - size * 0.5); // Top left
    path.lineTo(markerCenter.dx + size * 0.866,
        markerCenter.dy - size * 0.5); // Top right
    path.close();

    // Draw glow
    final glowPath = Path.from(path);
    canvas.drawPath(glowPath, glowPaint);

    // Draw solid triangle
    final trianglePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, trianglePaint);

    // Add exclamation mark inside triangle for RED (active) delinquency
    if (color == const Color(0xFFFF0000)) {
      final exclPaint = Paint()
        ..color = const Color(0xFF000000) // Black for contrast
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      // Exclamation line
      canvas.drawLine(
        Offset(markerCenter.dx, markerCenter.dy - size * 0.3),
        Offset(markerCenter.dx, markerCenter.dy + size * 0.1),
        exclPaint,
      );

      // Exclamation dot
      final dotPaint = Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(markerCenter.dx, markerCenter.dy + size * 0.35),
        0.6,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(EventMarkerPainter oldDelegate) {
    // Reference equality sufficient: Riverpod StateNotifier guarantees immutable updates
    // New list instance created on every state change
    return oldDelegate.snapshots != snapshots ||
        oldDelegate.innerRadius != innerRadius;
  }
}
