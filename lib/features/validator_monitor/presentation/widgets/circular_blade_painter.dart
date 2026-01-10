import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/themes/app_theme.dart';
import '../../data/models/validator_snapshot.dart';

// Custom painter for circular blade visualization
// 3 concentric rings showing vote distance, root distance, and credits delta
// 60 segments representing last 60 seconds of data
class CircularBladePainter extends CustomPainter {
  final List<ValidatorSnapshot> snapshots;
  final Animation<double> animation;
  final String? rank;

  CircularBladePainter({
    required this.snapshots,
    required this.animation,
    this.rank,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    // Ring dimensions - balanced proportions for visual harmony
    // Layout: rings end at 90% → gap → dots at 96% → gap → border at 100%

    // Gap between rings
    final ringGap = radius * 0.02;

    // Balanced proportions: 22% center + 13% vote + 2% gap + 13% root + 2% gap + 38% credits = 90%
    final voteRootThickness = radius * 0.13; // Square rings (equal thickness)
    final creditsThickness = radius * 0.38; // Larger but not dominant

    // Larger center circle for rank visibility
    final innerRingStart = radius * 0.22;

    // Calculate ring radii with consistent gaps
    // Ring 1: Vote Distance
    final ring1Inner = innerRingStart;
    final ring1Outer = ring1Inner + voteRootThickness;

    // Ring 2: Root Distance
    final ring2Inner = ring1Outer + ringGap;
    final ring2Outer = ring2Inner + voteRootThickness;

    // Ring 3: Credits Delta
    final ring3Inner = ring2Outer + ringGap;
    final ring3Outer = ring3Inner + creditsThickness;

    // Draw background circles
    _drawBackgroundCircles(canvas, center, ring1Inner, ring1Outer, ring2Inner,
        ring2Outer, ring3Inner, ring3Outer);

    // Draw data segments if we have snapshots
    if (snapshots.isNotEmpty) {
      _drawDataSegments(
        canvas,
        center,
        ring1Inner,
        ring1Outer,
        ring2Inner,
        ring2Outer,
        ring3Inner,
        ring3Outer,
        animation.value,
      );
    }

    // Center circle removed to show rotating moon image clearly
    // Color centerColor = AppTheme.rankOutsideColor;
    // if (rank case final rankStr?) {
    //   // Defensive: strip formatting characters (#, whitespace) before parsing
    //   final cleanRank = rankStr.replaceAll(RegExp(r'[^\d]'), '');
    //   final rankNum = int.tryParse(cleanRank);
    //   if (rankNum != null) {
    //     if (rankNum <= 100) {
    //       centerColor = AppTheme.rankTop100Color;
    //     } else if (rankNum <= 200) {
    //       centerColor = AppTheme.rankTop200Color;
    //     }
    //   }
    // }
    //
    // final centerPaint = Paint()
    //   ..color = centerColor
    //   ..style = PaintingStyle.fill;
    // // Center circle with same gap as between rings
    // canvas.drawCircle(center, ring1Inner - ringGap, centerPaint);

    // Draw ring separators
    _drawRingSeparators(canvas, center, ring1Inner, ring1Outer, ring2Inner,
        ring2Outer, ring3Inner, ring3Outer);

    // NOW indicator removed per user request
    // if (snapshots.isNotEmpty) {
    //   _drawNowIndicator(canvas, center, ring3Outer + 10);
    // }
  }

  void _drawBackgroundCircles(
    Canvas canvas,
    Offset center,
    double ring1Inner,
    double ring1Outer,
    double ring2Inner,
    double ring2Outer,
    double ring3Inner,
    double ring3Outer,
  ) {
    final bgPaint = Paint()
      ..color = AppTheme.backgroundElevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw inner edges of each ring
    canvas.drawCircle(center, ring1Inner, bgPaint);
    canvas.drawCircle(center, ring1Outer, bgPaint);
    canvas.drawCircle(center, ring2Inner, bgPaint);
    canvas.drawCircle(center, ring2Outer, bgPaint);
    canvas.drawCircle(center, ring3Inner, bgPaint);
    canvas.drawCircle(center, ring3Outer, bgPaint);
  }

  void _drawDataSegments(
    Canvas canvas,
    Offset center,
    double ring1Inner,
    double ring1Outer,
    double ring2Inner,
    double ring2Outer,
    double ring3Inner,
    double ring3Outer,
    double animationValue,
  ) {
    const segmentCount = 60;
    final sweepAngle = (2 * math.pi) / segmentCount;
    const gapAngle =
        0.015; // Consistent gap between segments (matches ring gaps)

    final snapshotCount = snapshots.length;
    if (snapshotCount == 0) return;

    // Draw newest snapshot at 12 o'clock, going counter-clockwise into past
    // This prevents visual "backward rotation" when buffer fills up
    const newestAngle = -math.pi / 2; // -90 degrees (12 o'clock)

    // Always use most recent snapshots
    final startIndex =
        snapshotCount > segmentCount ? snapshotCount - segmentCount : 0;
    final itemsToDraw =
        snapshotCount > segmentCount ? segmentCount : snapshotCount;

    for (int i = 0; i < itemsToDraw; i++) {
      // Draw from newest (buffer end) backward in time
      final snapshotIndex = startIndex + (itemsToDraw - 1 - i);
      final snapshot = snapshots[snapshotIndex];

      // Calculate angle: newest at 12 o'clock, going clockwise
      final segmentAngle = newestAngle + (i * sweepAngle);

      // Age-based opacity with smooth quadratic fade
      // Creates smooth shadow gradient: bright near NOW, gentle fade
      final ageFactor = i / itemsToDraw;
      final ageOpacity =
          1.0 - (ageFactor * ageFactor) * 0.88; // Quadratic ease-out

      // Ring 1 (innermost): Vote Distance
      _drawSegment(
        canvas,
        center,
        ring1Inner,
        ring1Outer,
        segmentAngle,
        sweepAngle - gapAngle,
        _getVoteDistanceColor(snapshot.voteDistance),
        animationValue,
        ageOpacity,
        isRecentSegment: i < 5, // Glow only on newest 5 segments
      );

      // Ring 2 (middle): Root Distance
      _drawSegment(
        canvas,
        center,
        ring2Inner,
        ring2Outer,
        segmentAngle,
        sweepAngle - gapAngle,
        _getRootDistanceColor(snapshot.rootDistance),
        animationValue,
        ageOpacity,
        isRecentSegment: i < 5,
      );

      // Ring 3 (outermost): Credits Performance Gap (rank1_delta - our_delta)
      // Negative = we earn MORE than rank1 (GOOD)
      // Positive = we earn LESS than rank1 (BAD - degradation)

      _drawSegment(
        canvas,
        center,
        ring3Inner,
        ring3Outer,
        segmentAngle,
        sweepAngle - gapAngle,
        _getCreditsPerformanceColor(snapshot.creditsPerformanceGap),
        animationValue,
        ageOpacity,
        isRecentSegment: i < 5,
      );

      // Alert marker: Amber dot on blade segment when alert is triggered
      // Detect when alert is sent (Confirmed phase transition or alert_sent flag transition)
      final events = snapshot.events;
      if (events != null && i < itemsToDraw - 1) {
        // Compare with previous segment in VISUAL ring (older in time)
        // Visual ring: i=0 is newest, i=1 is older, etc.
        final olderSnapshotIndex = startIndex + (itemsToDraw - 1 - (i + 1));
        final olderSnapshot = snapshots[olderSnapshotIndex];
        final olderEvents = olderSnapshot.events;

        final temporalAlertSent = events.temporal.alertSentThisCycle;
        final prevTemporalAlert =
            olderEvents?.temporal.alertSentThisCycle ?? false;

        // Fork alert detection: Use last_alert.event_id changes (reliable across missed cycles)
        final currentForkEventId = events.fork.lastAlert?.eventId;
        final prevForkEventId = olderEvents?.fork.lastAlert?.eventId;
        final forkTransition =
            currentForkEventId != null && currentForkEventId != prevForkEventId;

        // Temporal alert: only mark when alert_sent transitions to true
        final temporalTransition = temporalAlertSent && !prevTemporalAlert;

        if (temporalTransition) {
          _drawAlertMarker(
              canvas, center, ring3Inner, ring3Outer, segmentAngle, sweepAngle);
        }

        if (forkTransition) {
          _drawAlertMarker(
              canvas, center, ring3Inner, ring3Outer, segmentAngle, sweepAngle);
        }
      }
    }
  }

  void _drawSegment(
    Canvas canvas,
    Offset center,
    double innerRadius,
    double outerRadius,
    double startAngle,
    double sweepAngle,
    Color color,
    double animationValue,
    double ageOpacity, {
    bool isRecentSegment = false,
  }) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85 * animationValue * ageOpacity)
      ..style = PaintingStyle.fill;

    final path = Path();

    // Create arc segment
    final rect = Rect.fromCircle(center: center, radius: outerRadius);
    path.arcTo(rect, startAngle, sweepAngle, false);

    // Line to inner radius
    final endAngle = startAngle + sweepAngle;
    final innerEndX = center.dx + innerRadius * math.cos(endAngle);
    final innerEndY = center.dy + innerRadius * math.sin(endAngle);
    path.lineTo(innerEndX, innerEndY);

    // Arc back along inner radius
    final innerRect = Rect.fromCircle(center: center, radius: innerRadius);
    path.arcTo(innerRect, endAngle, -sweepAngle, false);

    path.close();
    canvas.drawPath(path, paint);

    // Add subtle glow for recent segments only (P7 optimization: limit blur to newest 5)
    if (isRecentSegment && animationValue > 0.5) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3 * (animationValue - 0.5) * 2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
      canvas.drawPath(path, glowPaint);
    }
  }

  void _drawRingSeparators(
    Canvas canvas,
    Offset center,
    double ring1Inner,
    double ring1Outer,
    double ring2Inner,
    double ring2Outer,
    double ring3Inner,
    double ring3Outer,
  ) {
    final separatorPaint = Paint()
      ..color = AppTheme.borderDefault
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw radial lines at 12, 3, 6, 9 o'clock positions
    for (int i = 0; i < 4; i++) {
      final angle = (i * math.pi / 2) - (math.pi / 2); // Start from top
      final cos = math.cos(angle);
      final sin = math.sin(angle);

      final startX = center.dx + ring1Inner * cos;
      final startY = center.dy + ring1Inner * sin;
      final endX = center.dx + ring3Outer * cos;
      final endY = center.dy + ring3Outer * sin;

      canvas.drawLine(
          Offset(startX, startY), Offset(endX, endY), separatorPaint);
    }
  }

  Color _getVoteDistanceColor(int voteDistance) {
    // 0=green, 1=blue, 2=orange, >2=red
    if (voteDistance == 0) return AppTheme.ringExcellentColor; // Green
    if (voteDistance == 1) return AppTheme.ringGoodColor; // Blue
    if (voteDistance == 2) return AppTheme.ringWarningColor; // Orange
    return AppTheme.ringCriticalColor; // Red
  }

  Color _getRootDistanceColor(int rootDistance) {
    // 0=green, 1=blue, 2=orange, >2=red
    if (rootDistance == 0) return AppTheme.ringExcellentColor; // Green
    if (rootDistance == 1) return AppTheme.ringGoodColor; // Blue
    if (rootDistance == 2) return AppTheme.ringWarningColor; // Orange
    return AppTheme.ringCriticalColor; // Red
  }

  Color _getCreditsPerformanceColor(int creditsPerformanceGap) {
    // creditsPerformanceGap = rank1_credits_delta - our_credits_delta
    // NEGATIVE values (e.g., -16) = we earn MORE than rank1 → EXCELLENT (green)
    // ZERO = we earn SAME as rank1 → OK (blue)
    // POSITIVE values (e.g., +10) = we earn LESS than rank1 → BAD (orange/red)

    // Critical thresholds for performance degradation
    if (creditsPerformanceGap < 0) {
      // We're earning ANY amount more credits than rank1 per cycle → EXCELLENT (highlight with acidic green)
      return AppTheme.ringOverperformColor; // Acidic green - overperformance
    } else if (creditsPerformanceGap == 0) {
      // We're earning exactly same as rank1 → GOOD
      return AppTheme.ringExcellentColor; // Professional green
    } else if (creditsPerformanceGap < 10) {
      // We're earning 1-9 fewer credits than rank1 → CAUTION (blue)
      return AppTheme.ringGoodColor; // Blue
    } else if (creditsPerformanceGap == 10) {
      // We're earning exactly 10 fewer credits than rank1 → WARNING (orange)
      return AppTheme.ringWarningColor; // Orange
    } else {
      // We're earning 11+ fewer credits than rank1 → CRITICAL (red)
      return AppTheme.ringCriticalColor; // Red
    }
  }

  void _drawAlertMarker(
    Canvas canvas,
    Offset center,
    double innerRadius,
    double outerRadius,
    double angle,
    double sweepAngle,
  ) {
    // Triangular marker fully internal with even gap from edge
    final midAngle = angle + sweepAngle / 2;

    // Triangle size and positioning - fully inside blade with 2px gap
    final markerSize = 7.0; // Slightly larger for visibility
    final tipRadius = outerRadius - 2.0; // 2px gap from outer edge
    final baseRadius = tipRadius - markerSize; // Triangle extends inward

    final tipX = center.dx + tipRadius * math.cos(midAngle);
    final tipY = center.dy + tipRadius * math.sin(midAngle);

    // Calculate triangle vertices - narrow to fit segment width
    final baseAngle1 = midAngle - 0.025; // Very narrow triangle
    final baseAngle2 = midAngle + 0.025;

    final base1X = center.dx + baseRadius * math.cos(baseAngle1);
    final base1Y = center.dy + baseRadius * math.sin(baseAngle1);
    final base2X = center.dx + baseRadius * math.cos(baseAngle2);
    final base2Y = center.dy + baseRadius * math.sin(baseAngle2);

    // Draw filled triangle
    final path = Path()
      ..moveTo(tipX, tipY)
      ..lineTo(base1X, base1Y)
      ..lineTo(base2X, base2Y)
      ..close();

    // Black fill with white border for visibility on all colors
    final fillPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(CircularBladePainter oldDelegate) {
    // Reference equality is correct for immutable snapshot list from Riverpod StateNotifier
    // Animation changes are handled by super(repaint: animation) in constructor
    return oldDelegate.snapshots != snapshots || oldDelegate.rank != rank;
  }
}
