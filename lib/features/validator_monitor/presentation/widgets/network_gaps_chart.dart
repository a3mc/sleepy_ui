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

    return LayoutBuilder(
      builder: (context, constraints) {
        // Adapt padding for extreme layouts
        final availableHeight = constraints.maxHeight;
        final padding = availableHeight < 80 ? 4.0 : 12.0;

        return Container(
          constraints: const BoxConstraints(minHeight: 120),
          decoration: BoxDecoration(
            color: AppTheme.backgroundDarker,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: AppTheme.borderColor,
              width: 1,
            ),
          ),
          child: ClipRect(
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                if (availableHeight >= 80) _buildHeader(data, compactMode),
                if (availableHeight >= 80)
                  const Divider(height: 1, color: AppTheme.borderColor),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(padding),
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
          ),
        );
      },
    );
  }

  Widget _buildHeader(List<ValidatorSnapshot> data, bool compactMode) {
    final latestGap = data.isNotEmpty ? data.last.gapToRank1 : 0;
    final isRank1 = latestGap == 0;

    if (compactMode && data.isNotEmpty) {
      final latest = data.last;
      final rank1Gap = latest.gapToRank1.abs();
      final top100Gap = latest.gapToTop100;
      final top200Gap = latest.gapToTop200;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCompactStat(
                'R1', rank1Gap.toString(), AppTheme.rank1GapColor),
            _buildCompactStat(
                'R100', 
                top100Gap.abs().toString(), 
                top100Gap > 0 ? AppTheme.healthyColor : AppTheme.rank100GapColor),
            _buildCompactStat(
                'R200', 
                top200Gap.abs().toString(), 
                top200Gap > 0 ? AppTheme.healthyColor : AppTheme.rank200GapColor),
            _buildCompactDelta(data),
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
                Text(
                  'DISTANCE',
                  style: TextStyle(
                    color: isRank1
                        ? AppTheme.healthyColor
                        : AppTheme.rank1GapColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isRank1 
                        ? AppTheme.healthyColor 
                        : AppTheme.rank1GapColor).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${latestGap.abs()}',
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
          const SizedBox(width: 12),
          // Delta label (change from start to end)
          _buildDeltaLabel(data),
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

  Widget _buildCompactDelta(List<ValidatorSnapshot> dataPoints) {
    if (dataPoints.length < 2) return const SizedBox.shrink();

    final allValues = dataPoints.map((s) => s.gapToRank1.abs()).toList();
    final cleanedValues = _removeSpikeOutliers(allValues);

    if (cleanedValues.length < 2) return const SizedBox.shrink();

    final delta = cleanedValues.last - cleanedValues.first;
    const color = Color(0xFF00E5FF); // Neon cyan

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Δ',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${delta >= 0 ? '+' : ''}$delta',
          style: const TextStyle(
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

    // Determine line color based on current rank
    final currentRank = dataPoints.last.rank;
    Color lineColor;
    if (currentRank <= 100) {
      lineColor = AppTheme.rankTop100Color; // Green
    } else if (currentRank <= 200) {
      lineColor = AppTheme.rankTop200Color; // Dark blue
    } else {
      lineColor = AppTheme.rankOutsideColor; // Gray
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

    // Grafana-style proportional padding: 10% of data range (Mode 3)
    final delta = maxGap - minGap;

    // Handle flat data (all values identical)
    final effectiveDelta =
        delta == 0 ? (minGap == 0 ? 1.0 : minGap * 0.1) : delta;

    // Apply 10% proportional padding to delta
    final yMin = ((minGap - effectiveDelta * 0.1).clamp(0.0, double.infinity))
        .floorToDouble();
    final yMax = (maxGap + effectiveDelta * 0.1).ceilToDouble();

    // Calculate intervals based on actual data range, not padded range
    final dataRange = maxGap - minGap;
    final gridInterval =
        (_calculateGridInterval(dataRange > 0 ? dataRange : effectiveDelta))
            .clamp(1.0, double.infinity);
    // Adaptive label spacing: fewer labels for small ranges, more for large ranges
    final labelInterval = dataRange < 100 ? gridInterval * 2 : gridInterval * 3;

    return Semantics(
      label: _buildChartSemanticDescription(dataPoints),
      readOnly: true,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
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
                    isCurved: false,
                    color: lineColor,
                    barWidth: 1.2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        // Highlight the last point (current moment) with a larger, pulsing dot
                        final isLastPoint = index == rank1Spots.length - 1;

                        if (isLastPoint) {
                          return FlDotCirclePainter(
                            radius: 4.5,
                            color: lineColor,
                            strokeWidth: 2.0,
                            strokeColor: Colors.white.withValues(alpha: 0.9),
                          );
                        }

                        // Show dots for all points in cypherblade mode
                        if (selectedRange == ChartTimeRange.cypherblade) {
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
                            color: lineColor,
                            strokeWidth: 0,
                          );
                        }

                        // Hide intermediate dots in historical views (cleaner line view)
                        return FlDotCirclePainter(
                          radius: 0,
                          color: Colors.transparent,
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
                              strokeColor: lineColor,
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
            );
          },
        ), // Close LayoutBuilder
      ), // Close RepaintBoundary
    ); // Close Semantics
  }

  /// Build compact delta label for header
  Widget _buildDeltaLabel(List<ValidatorSnapshot> dataPoints) {
    if (dataPoints.length < 2) return const SizedBox(width: 80);

    // Extract gap values
    final allValues = dataPoints.map((s) => s.gapToRank1.abs()).toList();
    
    // Remove outliers using same logic as sparklines (mean ± 2*std)
    final cleanedValues = _removeSpikeOutliers(allValues);

    if (cleanedValues.length < 2) return const SizedBox(width: 80);

    // Calculate simple delta: last - first
    final startValue = cleanedValues.first;
    final endValue = cleanedValues.last;
    final delta = endValue - startValue;

    final Color trendColor = const Color(0xFF00E5FF); // Neon cyan

    return SizedBox(
      width: 80,
      child: Container(
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Δ',
              style: TextStyle(
                color: trendColor,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: trendColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${delta >= 0 ? '+' : ''}$delta',
                style: TextStyle(
                  color: trendColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows change from start to end of timeframe (with outliers removed)
  Widget _buildAverageSpikeOverlay(
    List<ValidatorSnapshot> dataPoints,
    BoxConstraints constraints,
  ) {
    if (dataPoints.length < 2) return const SizedBox.shrink();

    // Extract gap values
    final allValues = dataPoints.map((s) => s.gapToRank1.abs()).toList();
    
    // Remove outliers using same logic as sparklines (mean ± 2*std)
    final cleanedValues = _removeSpikeOutliers(allValues);

    if (cleanedValues.length < 2) return const SizedBox.shrink();

    // Calculate simple delta: last - first
    final startValue = cleanedValues.first;
    final endValue = cleanedValues.last;
    final delta = endValue - startValue; // Positive = worse, negative = better

    // Get last data point value for Y positioning
    final lastGapValue = dataPoints.last.gapToRank1.abs().toDouble();
    
    // Calculate Y position based on chart's coordinate system
    // The chart Y goes from minY to maxY, we need to map our value to pixel position
    final allGaps = dataPoints.map((s) => s.gapToRank1.abs()).toList();
    final minGap = allGaps.reduce((a, b) => a < b ? a : b).toDouble();
    final maxGap = allGaps.reduce((a, b) => a > b ? a : b).toDouble();
    final range = maxGap - minGap;
    final padding = range * 0.1;
    final chartMinY = minGap - padding;
    final chartMaxY = maxGap + padding;
    final chartRange = chartMaxY - chartMinY;
    
    // Invert Y: chart Y=0 is at bottom, pixel Y=0 is at top
    final normalizedY = (lastGapValue - chartMinY) / chartRange; // 0 to 1
    final pixelY = constraints.maxHeight * (1 - normalizedY); // Flip it
    
    // Position to the left of the last dot, above the line
    final pixelX = constraints.maxWidth - 140; // Left of the right edge

    return Positioned(
      left: pixelX,
      top: pixelY - 50, // Position well above the line
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: delta >= 0
                ? Colors.red.withValues(alpha: 0.6)
                : Colors.green.withValues(alpha: 0.6),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: (delta >= 0 ? Colors.red : Colors.green)
                  .withValues(alpha: 0.25),
              blurRadius: 12,
            ),
          ],
        ),
        child: Text(
          '${delta >= 0 ? '+' : ''}$delta',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            height: 1.0,
          ),
        ),
      ),
    );
  }

  /// Remove outlier spikes using statistical bounds (mean ± 2*std)
  /// Same logic as gap_trend_indicators.dart sparkline smoothing
  List<int> _removeSpikeOutliers(List<int> values) {
    if (values.length < 5) return values;

    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    final std = sqrt(variance);

    final lowerBound = mean - 2.0 * std;
    final upperBound = mean + 2.0 * std;

    final cleaned = <int>[];
    int lastValid = mean.round();

    for (final value in values) {
      if (value >= lowerBound && value <= upperBound) {
        cleaned.add(value);
        lastValid = value;
      } else {
        cleaned.add(lastValid); // Replace outlier with last valid
      }
    }

    return cleaned;
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

      // Real transition: event ID changes from one value to a DIFFERENT value
      // Not a transition: null → something (happens when viewing new time range with old lastAlert)
      final forkTransition = currentForkEventId != null &&
          prevForkEventId != null &&
          currentForkEventId != prevForkEventId;

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
              labelResolver: (line) => 'EPOCH',
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
