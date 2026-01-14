import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/models/validator_snapshot.dart';
import '../../../../core/themes/app_theme.dart';

/// Modern trend indicators for top100 and top200 gaps
/// Shows current value, direction, delta, and mini sparkline
class GapTrendIndicators extends StatelessWidget {
  final List<ValidatorSnapshot> snapshots;
  final int sparklinePoints;

  const GapTrendIndicators({
    super.key,
    required this.snapshots,
    this.sparklinePoints = 60, // Match buffer size for full trend context
  });

  @override
  Widget build(BuildContext context) {
    if (snapshots.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _buildTrendCard('TOP 100', _extractTop100Trend()),
        _buildTrendCard('TOP 200', _extractTop200Trend()),
      ],
    );
  }

  // Remove outlier spikes using statistical bounds (mean ± threshold*std)
  List<int> _removeOutliers(List<int> values, {double threshold = 2.0}) {
    if (values.length < 5) return values; // Need enough data for stats

    // Calculate mean and standard deviation
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    final std = variance < 0 ? 0 : sqrt(variance);

    final lowerBound = mean - threshold * std;
    final upperBound = mean + threshold * std;

    // Replace outliers with previous valid value (or mean if first value)
    final cleaned = <int>[];
    int lastValid = mean.round();

    for (final value in values) {
      if (value >= lowerBound && value <= upperBound) {
        cleaned.add(value);
        lastValid = value;
      } else {
        cleaned.add(lastValid); // Replace spike with previous valid
      }
    }

    return cleaned;
  }

  Widget _buildTrendCard(
      String label, ({int current, int delta, List<int> history}) trend) {
    // Gap NUMBER color: based on current position
    // Positive gap = inside top100/200 (more credits than cutoff) = GOOD = GREEN
    // Negative gap = outside top100/200 (fewer credits than cutoff) = BAD = RED
    final gapNumberColor = trend.current > 0
        ? AppTheme.healthyColor // Green - inside top100/200
        : AppTheme.rank100GapColor; // Red - outside top100/200

    // Card BORDER and SPARKLINE color: based on trend direction
    // For top performers (positive gap): INCREASING gap = pulling ahead = GOOD = GREEN
    // For bottom performers (negative gap): INCREASING gap toward 0 = catching up = GOOD = GREEN
    final Color trendColor;
    if (trend.delta == 0) {
      trendColor = AppTheme.gapNeutralColor; // Gray - no change
    } else if (trend.current > 0) {
      // Positive gap (inside top 100/200): delta > 0 = pulling further ahead = GOOD
      trendColor = trend.delta > 0
          ? AppTheme.healthyColor // Green - gap increasing (pulling ahead)
          : AppTheme.rank100GapColor; // Red - gap decreasing (being caught)
    } else {
      // Negative gap (outside top 100/200): delta > 0 = moving toward 0 = GOOD
      trendColor = trend.delta > 0
          ? AppTheme
              .healthyColor // Green - gap increasing toward 0 (catching up)
          : AppTheme
              .rank100GapColor; // Red - gap decreasing (falling further behind)
    }

    final deltaAbs = trend.delta.abs();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.cardBackgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: trendColor.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: trendColor.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: gapNumberColor, // Label matches gap number color
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),

          // Current value - colored by position
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: gapNumberColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${trend.current.abs()}', // Display absolute value
              style: TextStyle(
                color: gapNumberColor, // Gap number shows current position
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Delta with arrow - momentum indicator
          // Arrow direction: numerical change direction (delta > 0 = UP, delta < 0 = DOWN)
          // Arrow color: same as sparkline (trendColor) for consistency
          if (deltaAbs > 0) ...[
            Icon(
              trend.delta > 0 ? Icons.arrow_upward : Icons.arrow_downward,
              size: 10,
              color: trendColor,
            ),
            const SizedBox(width: 2),
            Text(
              '$deltaAbs',
              style: TextStyle(
                color: trendColor,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            const Icon(
              Icons.remove,
              size: 10,
              color: AppTheme.gapNeutralColor,
            ),
            const SizedBox(width: 2),
            const Text(
              '0',
              style: TextStyle(
                color: AppTheme.gapNeutralColor,
                fontSize: 9,
              ),
            ),
          ],

          const SizedBox(width: 8),

          // Mini sparkline - shows 1h trend
          SizedBox(
            width: 60,
            height: 20,
            child: _buildSparkline(
                trend.history, trendColor), // Sparkline uses trend color
          ),
        ],
      ),
    );
  }

  Widget _buildSparkline(List<int> values, Color color) {
    if (values.length < 2) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      painter: _SparklinePainter(values, color),
    );
  }

  ({int current, int delta, List<int> history}) _extractTop100Trend() {
    final current = snapshots.last.gapToTop100; // Keep sign!

    // Two-stage outlier filtering:
    // 1. Remove statistical outliers (spikes beyond mean±2*std)
    // 2. Calculate median on cleaned data for robust trend
    int delta = 0;
    if (snapshots.length > 20) {
      final rawValues = snapshots.map((s) => s.gapToTop100).toList();
      final cleaned = _removeOutliers(rawValues, threshold: 2.0);

      final midpoint = cleaned.length ~/ 2;
      final firstHalf = cleaned.take(midpoint).toList()..sort();
      final secondHalf = cleaned.skip(midpoint).toList()..sort();

      // Median is center value (or average of two center values)
      final firstMedian = firstHalf.length.isOdd
          ? firstHalf[firstHalf.length ~/ 2].toDouble()
          : (firstHalf[firstHalf.length ~/ 2 - 1] +
                  firstHalf[firstHalf.length ~/ 2]) /
              2.0;

      final secondMedian = secondHalf.length.isOdd
          ? secondHalf[secondHalf.length ~/ 2].toDouble()
          : (secondHalf[secondHalf.length ~/ 2 - 1] +
                  secondHalf[secondHalf.length ~/ 2]) /
              2.0;

      delta = (secondMedian - firstMedian).round(); // Median-based trend
    } else if (snapshots.length > 1) {
      // Fallback for small buffer: use first/last
      delta = current - snapshots.first.gapToTop100;
    }

    // Use filtered data for sparkline visualization (removes spikes)
    // Limit to sparklinePoints (default 60) for consistent 1-hour window
    final allValues = snapshots.map((s) => s.gapToTop100).toList();
    final recentValues = allValues.length > sparklinePoints
        ? allValues.sublist(allValues.length - sparklinePoints)
        : allValues;
    final history = _removeOutliers(recentValues, threshold: 2.0);

    return (current: current, delta: delta, history: history);
  }

  ({int current, int delta, List<int> history}) _extractTop200Trend() {
    final current = snapshots.last.gapToTop200; // Keep sign!

    // Two-stage outlier filtering:
    // 1. Remove statistical outliers (spikes beyond mean±2*std)
    // 2. Calculate median on cleaned data for robust trend
    int delta = 0;
    if (snapshots.length > 20) {
      final rawValues = snapshots.map((s) => s.gapToTop200).toList();
      final cleaned = _removeOutliers(rawValues, threshold: 2.0);

      final midpoint = cleaned.length ~/ 2;
      final firstHalf = cleaned.take(midpoint).toList()..sort();
      final secondHalf = cleaned.skip(midpoint).toList()..sort();

      // Median is center value (or average of two center values)
      final firstMedian = firstHalf.length.isOdd
          ? firstHalf[firstHalf.length ~/ 2].toDouble()
          : (firstHalf[firstHalf.length ~/ 2 - 1] +
                  firstHalf[firstHalf.length ~/ 2]) /
              2.0;

      final secondMedian = secondHalf.length.isOdd
          ? secondHalf[secondHalf.length ~/ 2].toDouble()
          : (secondHalf[secondHalf.length ~/ 2 - 1] +
                  secondHalf[secondHalf.length ~/ 2]) /
              2.0;

      delta = (secondMedian - firstMedian).round(); // Median-based trend
    } else if (snapshots.length > 1) {
      // Fallback for small buffer: use first/last
      delta = current - snapshots.first.gapToTop200;
    }

    // Use filtered data for sparkline visualization (removes spikes)
    // Limit to sparklinePoints (default 60) for consistent 1-hour window
    final allValues = snapshots.map((s) => s.gapToTop200).toList();
    final recentValues = allValues.length > sparklinePoints
        ? allValues.sublist(allValues.length - sparklinePoints)
        : allValues;
    final history = _removeOutliers(recentValues, threshold: 2.0);

    return (current: current, delta: delta, history: history);
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> values;
  final Color color;

  // Cache smoothed values computed once in constructor (performance optimization)
  late final List<double> _smoothedValues;
  late final double _minVal;
  late final double _maxVal;
  late final double _range;

  _SparklinePainter(this.values, this.color) {
    // Precompute smoothing and statistics once
    _smoothedValues = _smoothValues(values);
    if (_smoothedValues.isNotEmpty) {
      _minVal = _smoothedValues.reduce((a, b) => a < b ? a : b);
      _maxVal = _smoothedValues.reduce((a, b) => a > b ? a : b);
      _range = _maxVal - _minVal;
    } else {
      _minVal = 0;
      _maxVal = 0;
      _range = 0;
    }
  }

  // Apply 3-point moving average to smooth jitter
  List<double> _smoothValues(List<int> raw) {
    if (raw.length < 3) return raw.map((v) => v.toDouble()).toList();

    final smoothed = <double>[];
    smoothed.add(raw[0].toDouble()); // Keep first point unchanged

    for (int i = 1; i < raw.length - 1; i++) {
      final avg = (raw[i - 1] + raw[i] + raw[i + 1]) / 3.0;
      smoothed.add(avg);
    }

    smoothed.add(raw.last.toDouble()); // Keep last point unchanged
    return smoothed;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    // Use precomputed cached values directly
    if (_range == 0) {
      // Flat line with subtle glow
      final y = size.height / 2;
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.2)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      canvas.drawLine(Offset(0, y), Offset(size.width, y), glowPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      return;
    }

    // Build smooth Bézier curve path
    final path = Path();
    final stepX = size.width / (_smoothedValues.length - 1);
    final points = <Offset>[];

    for (int i = 0; i < _smoothedValues.length; i++) {
      final x = i * stepX;
      final normalized = (_smoothedValues[i] - _minVal) / _range;
      final y = size.height -
          (normalized *
              size.height); // INVERTED: Higher values = higher on canvas (lower y)
      points.add(Offset(x, y));
    }

    path.moveTo(points[0].dx, points[0].dy);

    // Smooth Bézier curves between points
    for (int i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final controlPointX = (current.dx + next.dx) / 2;

      path.quadraticBezierTo(
        controlPointX,
        current.dy,
        controlPointX,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(
        controlPointX,
        next.dy,
        next.dx,
        next.dy,
      );
    }

    // Glow effect (outer stroke)
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    canvas.drawPath(path, glowPaint);

    // Main line (inner stroke)
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
