import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../../data/models/validator_snapshot.dart';
import '../providers/time_range_provider.dart';
import '../providers/credits_feed_visibility_provider.dart';
import '../providers/credits_feed_provider.dart';
import '../providers/validator_providers.dart';
import 'gap_trend_indicators.dart';
import '../../../../core/themes/app_theme.dart';

class NetworkGapsChart extends ConsumerWidget {
  final bool compactMode;

  const NetworkGapsChart({super.key, this.compactMode = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch selected time range and fetch corresponding chart data
    final selectedRange = ref.watch(selectedTimeRangeProvider);
    final chartDataAsync = ref.watch(chartDataProvider(selectedRange));

    return chartDataAsync.when(
      data: (data) =>
          _buildChart(context, ref, data, selectedRange, compactMode),
      loading: () => _buildLoadingState(),
      error: (error, stack) => _buildErrorState(error),
    );
  }

  Widget _buildChart(
      BuildContext context,
      WidgetRef ref,
      List<ValidatorSnapshot> data,
      ChartTimeRange selectedRange,
      bool compactMode) {
    if (data.isEmpty) {
      return _buildEmptyState();
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundDarker,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppTheme.borderColor,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildHeader(data, compactMode),
          const Divider(height: 1, color: AppTheme.borderColor),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Consumer(
                builder: (context, ref, _) {
                  final showCreditsFeed =
                      ref.watch(creditsFeedVisibilityProvider);
                  return Row(
                    children: [
                      Expanded(
                        child: _buildChartContent(
                            data, selectedRange, ref, compactMode),
                      ),
                      if (showCreditsFeed) const SizedBox(width: 12),
                      if (showCreditsFeed) _buildCreditsFlow(ref),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(List<ValidatorSnapshot> data, bool compactMode) {
    final latestGap = data.isNotEmpty ? data.last.gapToRank1 : 0;
    final isRank1 = latestGap == 0;

    if (compactMode && data.isNotEmpty) {
      final latest = data.last;
      final rank1Gap = latest.gapToRank1.abs();
      final top100Gap = latest.gapToTop100.abs();
      final top200Gap = latest.gapToTop200.abs();

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCompactStat(
                'R1', rank1Gap.toString(), AppTheme.rank1GapColor),
            _buildCompactStat(
                'R100', top100Gap.toString(), AppTheme.rank100GapColor),
            _buildCompactStat(
                'R200', top200Gap.toString(), AppTheme.rank200GapColor),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.cardBackgroundColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color:
                    (isRank1 ? AppTheme.healthyColor : AppTheme.rank1GapColor)
                        .withValues(alpha: 0.15),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (isRank1 ? AppTheme.healthyColor : AppTheme.rank1GapColor)
                          .withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRank1 ? Icons.emoji_events : Icons.trending_up,
                  size: 14,
                  color: isRank1 ? AppTheme.goldColor : AppTheme.rank1GapColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'CREDITS TO RANK_1',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isRank1
                        ? AppTheme.healthyColor.withValues(alpha: 0.15)
                        : AppTheme.rank1GapColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    latestGap.abs().toString(),
                    style: TextStyle(
                      color: isRank1
                          ? AppTheme.healthyColor
                          : AppTheme.rank1GapColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Full trend indicators with sparklines (using buffer for longer trend context)
          Expanded(
            child: Consumer(
              builder: (context, ref, _) {
                final bufferData = ref.watch(snapshotBufferProvider);
                return GapTrendIndicators(
                  snapshots: bufferData.isEmpty ? data : bufferData,
                );
              },
            ),
          ),
          // Time window indicator for historical data (hidden in compact mode)
          if (!compactMode && data.length >= 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.cardBackgroundColor,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AppTheme.borderColor, width: 1),
              ),
              child: Text(
                _formatTimeRange(data.first.timestamp, data.last.timestamp),
                style: const TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondaryAlt,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildChartContent(List<ValidatorSnapshot> dataPoints,
      ChartTimeRange selectedRange, WidgetRef ref, bool compactMode) {
    if (dataPoints.isEmpty) {
      return _buildEmptyState();
    }

    final rank1Spots = <FlSpot>[];
    final baseTimestamp =
        dataPoints.first.timestamp.millisecondsSinceEpoch / 1000;

    for (int i = 0; i < dataPoints.length; i++) {
      final snapshot = dataPoints[i];
      final gapValue = snapshot.gapToRank1.abs().toDouble();
      final xValue =
          (snapshot.timestamp.millisecondsSinceEpoch / 1000) - baseTimestamp;
      rank1Spots.add(FlSpot(xValue, gapValue));
    }

    // Calculate Y axis bounds
    final allGaps = dataPoints.map((s) => s.gapToRank1.abs()).toList();

    if (allGaps.every((g) => g == 0)) {
      return _buildEmptyState();
    }

    final minGap = allGaps.reduce((a, b) => a < b ? a : b).toDouble();
    final maxGap = allGaps.reduce((a, b) => a > b ? a : b).toDouble();

    final dataRange = maxGap - minGap;
    final paddingFactor = 0.12;
    final verticalPadding = dataRange > 0 ? dataRange * paddingFactor : 15.0;

    final yMin = (minGap - verticalPadding).clamp(0.0, double.infinity);
    final yMax = maxGap + verticalPadding;

    // Dynamic grid intervals based on range
    final range = yMax - yMin;
    final gridInterval = _calculateGridInterval(range);
    // Adaptive label spacing: fewer labels for small ranges, more for large ranges
    final labelInterval = range < 100 ? gridInterval * 2 : gridInterval * 3;

    return Semantics(
      label: _buildChartSemanticDescription(dataPoints),
      readOnly: true,
      child: RepaintBoundary(
        child: Stack(
          children: [
            LineChart(
              LineChartData(
                clipData: const FlClipData.all(),
                extraLinesData: ExtraLinesData(
                  verticalLines: _buildAlertMarkers(dataPoints),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: gridInterval, // 100 unit grid spacing
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: AppTheme.backgroundElevated,
                      strokeWidth: 1,
                    );
                  },
                  getDrawingVerticalLine: (value) {
                    return FlLine(
                      color: AppTheme.backgroundElevated,
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      interval:
                          labelInterval, // 200 unit label spacing to prevent overlap
                      getTitlesWidget: (value, meta) {
                        // Display positive gap values
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            value.toInt().toString(),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppTheme.textQuaternary,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      // Adaptive label count: fewer labels in compact mode to prevent overlap
                      interval:
                          (rank1Spots.last.x - 0) / (compactMode ? 6 : 16),
                      getTitlesWidget: (value, meta) {
                        // value is already timestamp offset in seconds from baseTimestamp
                        final xSeconds = value +
                            (dataPoints.first.timestamp.millisecondsSinceEpoch /
                                1000);
                        final timestamp = DateTime.fromMillisecondsSinceEpoch(
                            (xSeconds * 1000).toInt());

                        // Edge collision prevention: skip labels too close to time borders
                        final totalDuration = rank1Spots.last.x;
                        final edgeThreshold = totalDuration * 0.05;
                        if (value < edgeThreshold ||
                            value > totalDuration - edgeThreshold) {
                          return const SizedBox.shrink();
                        }

                        final label = _formatTimeAxisLabel(
                            timestamp,
                            dataPoints.first.timestamp,
                            dataPoints.last.timestamp);

                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: AppTheme.textQuaternary,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: AppTheme.borderSubtle,
                    width: 1,
                  ),
                ),
                minX: 0,
                maxX: rank1Spots.isNotEmpty ? rank1Spots.last.x : 0,
                minY: yMin, // Lower gap values at bottom
                maxY: yMax, // Higher gap values at top
                lineBarsData: [
                  LineChartBarData(
                    spots: rank1Spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    preventCurveOverShooting: true,
                    color: AppTheme.ourValidatorColor,
                    barWidth: 1.2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: selectedRange == ChartTimeRange.cypherblade,
                      getDotPainter: (spot, percent, barData, index) {
                        if (spot.y == 0) {
                          return FlDotCirclePainter(
                            radius: 2.5,
                            color: AppTheme.goldColor,
                            strokeWidth: 1.2,
                            strokeColor:
                                AppTheme.goldColor.withValues(alpha: 0.5),
                          );
                        }
                        return FlDotCirclePainter(
                          radius: 1.5,
                          color: AppTheme.ourValidatorColor,
                          strokeWidth: 0,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show:
                          false, // Disabled for line-only view (Grafana-style)
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.ourValidatorColor.withValues(alpha: 0.3),
                          AppTheme.ourValidatorColor.withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  getTouchedSpotIndicator: (barData, spotIndexes) {
                    return spotIndexes.map((index) {
                      return TouchedSpotIndicatorData(
                        FlLine(
                          color: Colors.white.withValues(alpha: 0.3),
                          strokeWidth: 1,
                        ),
                        FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) {
                            return FlDotCirclePainter(
                              radius: 4,
                              color: Colors.white,
                              strokeWidth: 1,
                              strokeColor: AppTheme.ourValidatorColor,
                            );
                          },
                        ),
                      );
                    }).toList();
                  },
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) =>
                        AppTheme.backgroundElevated,
                    tooltipPadding: const EdgeInsets.all(8),
                    tooltipBorder: const BorderSide(color: Colors.transparent),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        // Find the datapoint closest to the x-value (timestamp-based)
                        final baseTime =
                            dataPoints.first.timestamp.millisecondsSinceEpoch /
                                1000;
                        int closestIndex = 0;
                        double minDiff = double.infinity;
                        for (int i = 0; i < dataPoints.length; i++) {
                          final pointTime =
                              dataPoints[i].timestamp.millisecondsSinceEpoch /
                                  1000;
                          final diff = (pointTime - baseTime - spot.x).abs();
                          if (diff < minDiff) {
                            minDiff = diff;
                            closestIndex = i;
                          }
                        }

                        if (closestIndex < 0 ||
                            closestIndex >= dataPoints.length) {
                          return null;
                        }

                        final snapshot = dataPoints[closestIndex];
                        final gap = snapshot.gapToRank1;
                        final time =
                            '${snapshot.timestamp.hour.toString().padLeft(2, '0')}:${snapshot.timestamp.minute.toString().padLeft(2, '0')}:${snapshot.timestamp.second.toString().padLeft(2, '0')}';

                        return LineTooltipItem(
                          'Gap: $gap\nPosition #${snapshot.rank}\n$time',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ), // Close LineChart
            if (!compactMode)
              Positioned(
                top: 8,
                left: 70,
                child: _buildAlertLegend(),
              ),
          ],
        ), // Close Stack
      ), // Close RepaintBoundary
    ); // Close Semantics
  }

  Widget _buildEmptyState() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 800),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDarker,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.show_chart,
            size: 48,
            color: Colors.grey.shade700,
          ),
          const SizedBox(height: 16),
          Text(
            'Building chart...',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditsFlow(WidgetRef ref) {
    final events = ref.watch(creditsFeedProvider);

    if (events.isEmpty) {
      return const SizedBox(width: 80);
    }

    return SizedBox(
      width: 80,
      child: ListView(
        children: events
            .map((event) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildCreditsIndicator(event),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildCreditsIndicator(({int change, bool isWin}) event) {
    final isWin = event.isWin;
    final change = event.change.abs();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color:
            isWin ? AppTheme.winBackgroundColor : AppTheme.lossBackgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isWin ? AppTheme.winBorderColor : AppTheme.lossBorderColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWin ? Icons.arrow_upward : Icons.arrow_downward,
            size: 11,
            color: isWin ? AppTheme.healthyColor : AppTheme.lossColor,
          ),
          const SizedBox(width: 4),
          Text(
            change.toString(),
            style: TextStyle(
              color: isWin ? AppTheme.healthyColor : AppTheme.lossColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 800),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDarker,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: const Center(
        child: SpinKitWaveSpinner(
          color: AppTheme.ourValidatorColor,
          size: 50.0,
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Consumer(
      builder: (context, ref, child) {
        return Container(
          constraints: const BoxConstraints(maxWidth: 800),
          decoration: BoxDecoration(
            color: AppTheme.backgroundDarker,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: AppTheme.borderSubtle,
              width: 1,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load historical data',
                  style: TextStyle(color: AppTheme.textQuaternary),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: const TextStyle(
                      color: AppTheme.textTertiary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    final selectedRange = ref.read(selectedTimeRangeProvider);
                    ref.invalidate(chartDataProvider(selectedRange));
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.ourValidatorColor,
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Format time range for display in chart header
  /// Shows duration for ranges < 1 hour, date+time for longer ranges
  String _formatTimeRange(DateTime start, DateTime end) {
    final duration = end.difference(start);

    // For short durations (< 1 hour), show duration
    if (duration.inHours < 1) {
      if (duration.inMinutes < 1) {
        return '${duration.inSeconds}s';
      }
      return '${duration.inMinutes}m';
    }

    // For longer durations, show start-end timestamps
    final startTime =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final endTime =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';

    // If same day, show only times
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return '$startTime - $endTime';
    }

    // Different days: show date for start
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${monthNames[start.month - 1]} ${start.day}, $startTime - $endTime';
  }

  /// Calculate appropriate grid interval based on y-axis range
  /// Returns intervals that provide 4-8 grid lines for readability
  double _calculateGridInterval(double range) {
    if (range <= 0) return 10.0;

    // Target: 5-6 grid lines across the range
    final rawInterval = range / 5.5;

    // Round to nearest "nice" number (1, 2, 5, 10, 20, 50, 100, etc.)
    final magnitude = pow(10, (log(rawInterval) / ln10).floor()).toDouble();
    final normalized = rawInterval / magnitude;

    double niceInterval;
    if (normalized < 1.5) {
      niceInterval = 1.0;
    } else if (normalized < 3.5) {
      niceInterval = 2.0;
    } else if (normalized < 7.5) {
      niceInterval = 5.0;
    } else {
      niceInterval = 10.0;
    }

    return niceInterval * magnitude;
  }

  /// Format time axis label based on total range duration
  /// Uses absolute time (HH:mm) for longer ranges, relative time for short ranges
  String _formatTimeAxisLabel(
      DateTime timestamp, DateTime firstTimestamp, DateTime lastTimestamp) {
    final totalDuration = lastTimestamp.difference(firstTimestamp);

    // For ranges > 1 hour: show absolute time (HH:mm)
    if (totalDuration.inMinutes > 60) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }

    // For ranges < 1 hour: show minutes relative to start
    final elapsed = timestamp.difference(firstTimestamp);
    if (totalDuration.inMinutes > 5) {
      return '${elapsed.inMinutes}m';
    }

    // For very short ranges: show seconds
    return '${elapsed.inSeconds}s';
  }

  /// Build legend showing alert marker color coding
  Widget _buildAlertLegend() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDarker.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AppTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLegendItem(_temporalWarningColor, 'Warning'),
          const SizedBox(height: 4),
          _buildLegendItem(_temporalCriticalColor, 'Critical'),
          const SizedBox(height: 4),
          _buildLegendItem(_recoveryColor, 'Recovery'),
          const SizedBox(height: 4),
          _buildLegendItem(_forkColor, 'Loss'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 2,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textQuaternary,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // Alert marker colors by type
  static const _temporalWarningColor = AppTheme.alertPendingColor;
  static const _temporalCriticalColor =
      Color(0xFFFF6B6B); // Bright red (visible on dark background)
  static const _recoveryColor = AppTheme.healthyColor;
  static const _forkColor = AppTheme.forkStabilizingColor;

  /// Marks alert states and transitions with colored vertical lines
  /// - Temporal alerts: dashed lines for Warning (amber) and Critical (red) states
  /// - Detection alerts: labeled with resource loss (cyan)
  /// - Recovery: green dashed line when Critical recovers to None
  List<VerticalLine> _buildAlertMarkers(List<ValidatorSnapshot> dataPoints) {
    final markers = <VerticalLine>[];
    final baseTimestamp =
        dataPoints.first.timestamp.millisecondsSinceEpoch / 1000;

    for (int i = 0; i < dataPoints.length; i++) {
      final snapshot = dataPoints[i];
      final events = snapshot.events;

      if (events == null) continue;

      // Calculate timestamp-based x-coordinate
      final xValue =
          (snapshot.timestamp.millisecondsSinceEpoch / 1000) - baseTimestamp;

      // Get previous snapshot to detect transitions
      final prevSnapshot = i > 0 ? dataPoints[i - 1] : null;
      final prevEvents = prevSnapshot?.events;

      // Temporal alert: mark only when alert fires (alertSentThisCycle transition)
      final temporalAlertSent = events.temporal.alertSentThisCycle;
      final prevTemporalAlert =
          prevEvents?.temporal.alertSentThisCycle ?? false;
      final temporalTransition = temporalAlertSent && !prevTemporalAlert;

      if (temporalTransition) {
        final isCritical = events.temporal.isCritical;
        final markerColor =
            isCritical ? _temporalCriticalColor : _temporalWarningColor;

        markers.add(
          VerticalLine(
            x: xValue,
            color: markerColor,
            strokeWidth: 1.2,
            dashArray: [4, 4],
            label: isCritical
                ? VerticalLineLabel(
                    show: true,
                    alignment: Alignment.topCenter,
                    padding: const EdgeInsets.only(bottom: 4),
                    style: TextStyle(
                      color: markerColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      backgroundColor: AppTheme.backgroundDarker,
                    ),
                    labelResolver: (line) => 'CRIT',
                  )
                : VerticalLineLabel(show: false),
          ),
        );
      }

      final currentForkEventId = events.fork.lastAlert?.eventId;
      final prevForkEventId = prevEvents?.fork.lastAlert?.eventId;
      final forkTransition =
          currentForkEventId != null && currentForkEventId != prevForkEventId;

      final criticalRecovery = prevEvents != null &&
          prevEvents.temporal.isCritical &&
          events.temporal.isNone;

      if (forkTransition && events.fork.lastAlert != null) {
        final alert = events.fork.lastAlert!;
        final creditsLost = alert.stabilizedCreditsLost;
        final markerColor = _forkColor;

        markers.add(
          VerticalLine(
            x: xValue,
            color: markerColor.withValues(alpha: 0.3),
            strokeWidth: 1.5,
            dashArray: [4, 4],
            label: VerticalLineLabel(
              show: true,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(bottom: 4),
              style: TextStyle(
                color: markerColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                backgroundColor: AppTheme.backgroundDarker,
              ),
              labelResolver: (line) => '$creditsLost',
            ),
          ),
        );
      }

      // Recovery marker (green) - CRITICAL recovery only (alert sent)
      if (criticalRecovery) {
        markers.add(
          VerticalLine(
            x: xValue,
            color: _recoveryColor.withValues(alpha: 0.3),
            strokeWidth: 1.5,
            dashArray: [4, 4],
            label: VerticalLineLabel(show: false),
          ),
        );
      }

      final epochInWindow = events.epochBoundary.inWindow;
      final prevEpochInWindow = prevEvents?.epochBoundary.inWindow ?? false;
      final epochTransition = epochInWindow && !prevEpochInWindow;

      if (epochTransition) {
        markers.add(
          VerticalLine(
            x: xValue,
            color: const Color(0xFFFF00FF),
            strokeWidth: 2.5,
            dashArray: null,
            label: VerticalLineLabel(
              show: true,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(bottom: 4),
              style: const TextStyle(
                color: Color(0xFFFF00FF),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                backgroundColor: AppTheme.backgroundDarker,
              ),
              labelResolver: (line) => 'CYCLE',
            ),
          ),
        );
      }
    }

    return markers;
  }

  String _buildChartSemanticDescription(List<ValidatorSnapshot> dataPoints) {
    if (dataPoints.isEmpty) {
      return 'Gap to rank_1 chart: No data available';
    }

    final latestGap = dataPoints.last.gapToRank1.abs();

    String trend = '';
    if (dataPoints.length >= 2) {
      final previousGap = dataPoints[dataPoints.length - 2].gapToRank1.abs();
      if (latestGap < previousGap) {
        trend = ', improving';
      } else if (latestGap > previousGap) {
        trend = ', declining';
      } else {
        trend = ', stable';
      }
    }

    return 'Gap to rank_1 chart: Currently $latestGap units behind rank_1$trend';
  }
}
