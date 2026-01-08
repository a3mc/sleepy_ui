import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../../../../core/themes/app_theme.dart';
import '../../data/models/validator_snapshot.dart';
import '../providers/time_range_provider.dart';

class RankChart extends ConsumerWidget {
  final bool compactMode;

  const RankChart({super.key, this.compactMode = false});

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
    bool compactMode,
  ) {
    if (data.isEmpty) {
      return _buildEmptyState();
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 800),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDarker,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppTheme.borderSubtle, width: 1),
      ),
      child: Column(
        children: [
          _buildHeader(data, compactMode),
          const Divider(height: 1, color: AppTheme.borderSubtle),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: _buildChartContent(data, selectedRange, ref),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(List<ValidatorSnapshot> data, bool compactMode) {
    final latestRank = data.isNotEmpty ? data.last.rank : 0;
    final color = _getRankColor(latestRank);

    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.backgroundElevated,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.leaderboard, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          const Text(
            'ENTITY POSITION',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '#$latestRank',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          // Time window indicator for historical data (hidden in compact mode)
          if (!compactMode && data.length >= 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.backgroundElevated,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AppTheme.borderSubtle, width: 1),
              ),
              child: Text(
                _formatTimeRange(data.first.timestamp, data.last.timestamp),
                style: const TextStyle(
                  color: AppTheme.textQuaternary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChartContent(
    List<ValidatorSnapshot> dataPoints,
    ChartTimeRange selectedRange,
    WidgetRef ref,
  ) {
    if (dataPoints.isEmpty || dataPoints.every((s) => s.rank == 0)) {
      return _buildEmptyState();
    }

    // Use timestamp-based x-coordinates for proper time-series display
    final rankSpots = <FlSpot>[];
    final baseTimestamp =
        dataPoints.first.timestamp.millisecondsSinceEpoch / 1000;

    for (int i = 0; i < dataPoints.length; i++) {
      final snapshot = dataPoints[i];
      if (snapshot.rank > 0) {
        final xValue =
            (snapshot.timestamp.millisecondsSinceEpoch / 1000) - baseTimestamp;
        rankSpots.add(FlSpot(xValue, snapshot.rank.toDouble()));
      }
    }

    if (rankSpots.isEmpty) {
      return _buildEmptyState();
    }

    final allRanks = rankSpots.map((s) => s.y).toList();
    final minRank = allRanks.reduce((a, b) => a < b ? a : b);
    final maxRank = allRanks.reduce((a, b) => a > b ? a : b);

    final rawPadding = (maxRank - minRank) * 0.3;
    final padding = rawPadding < 2.0 ? 2.0 : rawPadding;
    final yMin = (minRank - padding).clamp(1.0, double.infinity);
    final yMax = maxRank + padding;

    final range = yMax - yMin;
    double interval;
    if (range <= 10) {
      interval = 2.0;
    } else if (range <= 20) {
      interval = 5.0;
    } else if (range <= 50) {
      interval = 10.0;
    } else if (range <= 100) {
      interval = 20.0;
    } else if (range <= 200) {
      interval = 50.0;
    } else {
      interval = 100.0;
    }

    return Semantics(
      label: _buildChartSemanticDescription(dataPoints),
      readOnly: true,
      child: RepaintBoundary(
        child: LineChart(
          LineChartData(
            minY: yMin,
            maxY: yMax,
            lineBarsData: [
              LineChartBarData(
                spots: rankSpots,
                isCurved: true,
                curveSmoothness: 0.25,
                preventCurveOverShooting: true,
                isStrokeCapRound: true,
                isStrokeJoinRound: true,
                color: _getRankColor(rankSpots.last.y.toInt()),
                barWidth: 1.2,
                dotData: FlDotData(
                  show: selectedRange == ChartTimeRange.cypherblade,
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 1.5,
                      color: _getRankColor(spot.y.toInt()),
                      strokeWidth: 0,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: false, // Disabled for line-only view (Grafana-style)
                  gradient: LinearGradient(
                    colors: [
                      _getRankColor(
                        rankSpots.last.y.toInt(),
                      ).withValues(alpha: 0.2),
                      _getRankColor(
                        rankSpots.last.y.toInt(),
                      ).withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 50,
                  interval: interval,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      '#${value.round()}',
                      style: const TextStyle(
                        color: AppTheme.textSecondaryAlt,
                        fontSize: 10,
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
                  reservedSize: 22,
                  interval: ((rankSpots.last.x - rankSpots.first.x) / 12).clamp(
                    1.0,
                    double.infinity,
                  ),
                  getTitlesWidget: (value, meta) {
                    // Find closest snapshot to this x value (time offset)
                    final targetTime = value;
                    int closestIndex = 0;
                    double minDiff = double.infinity;

                    for (int i = 0; i < rankSpots.length; i++) {
                      final diff = (rankSpots[i].x - targetTime).abs();
                      if (diff < minDiff) {
                        minDiff = diff;
                        closestIndex = i;
                      }
                    }

                    if (closestIndex >= dataPoints.length) {
                      return const Text('');
                    }

                    final timestamp = dataPoints[closestIndex].timestamp;
                    final label = _formatTimeAxisLabel(
                      timestamp,
                      dataPoints.first.timestamp,
                      dataPoints.last.timestamp,
                    );

                    return Text(
                      label,
                      style: const TextStyle(
                        color: AppTheme.textSecondaryAlt,
                        fontSize: 9,
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (value) {
                return FlLine(color: AppTheme.borderSubtle, strokeWidth: 1);
              },
              getDrawingVerticalLine: (value) {
                return FlLine(color: AppTheme.borderSubtle, strokeWidth: 1);
              },
            ),
            borderData: FlBorderData(show: false),
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
                getTooltipColor: (touchedSpot) => AppTheme.backgroundElevated,
                tooltipPadding: const EdgeInsets.all(8),
                tooltipBorder: const BorderSide(color: Colors.transparent),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    // Find snapshot by matching timestamp x-coordinate
                    final targetTime = spot.x + baseTimestamp;

                    // Find closest snapshot to this timestamp
                    int closestIndex = 0;
                    double minDiff = double.infinity;
                    for (int i = 0; i < dataPoints.length; i++) {
                      final snapTime =
                          dataPoints[i].timestamp.millisecondsSinceEpoch / 1000;
                      final diff = (snapTime - targetTime).abs();
                      if (diff < minDiff) {
                        minDiff = diff;
                        closestIndex = i;
                      }
                    }

                    final snapshot = dataPoints[closestIndex];
                    final rank = snapshot.rank;
                    final time =
                        '${snapshot.timestamp.hour.toString().padLeft(2, '0')}:${snapshot.timestamp.minute.toString().padLeft(2, '0')}:${snapshot.timestamp.second.toString().padLeft(2, '0')}';
                    return LineTooltipItem(
                      '#$rank\n$time',
                      TextStyle(
                        color: _getRankColor(rank),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
          ),
        ), // Close RepaintBoundary
      ), // Close Semantics
    );
  }

  String _buildChartSemanticDescription(List<ValidatorSnapshot> dataPoints) {
    if (dataPoints.isEmpty) {
      return 'Entity position chart: No data available';
    }

    final latestRank = dataPoints.last.rank;
    String tier;
    if (latestRank <= 100) {
      tier = 'top 100';
    } else if (latestRank <= 200) {
      tier = 'top 200';
    } else {
      tier = 'outside top 200';
    }

    String trend = '';
    if (dataPoints.length >= 2) {
      final previousRank = dataPoints[dataPoints.length - 2].rank;
      if (latestRank < previousRank) {
        trend = ', improving';
      } else if (latestRank > previousRank) {
        trend = ', declining';
      } else {
        trend = ', stable';
      }
    }

    return 'Entity position chart: Currently position $latestRank, $tier$trend';
  }

  Widget _buildLoadingState() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 800),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDarker,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppTheme.borderSubtle, width: 1),
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
            border: Border.all(color: AppTheme.borderSubtle, width: 1),
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
                    color: AppTheme.textTertiary,
                    fontSize: 12,
                  ),
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

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'No position data available',
        style: TextStyle(color: AppTheme.textSecondaryAlt, fontSize: 12),
      ),
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
      'Dec',
    ];
    return '${monthNames[start.month - 1]} ${start.day}, $startTime - $endTime';
  }

  Color _getRankColor(int rank) {
    if (rank <= 100) {
      return AppTheme.rankTop100Color;
    } else if (rank <= 200) {
      return AppTheme.rankTop200Color;
    } else {
      return AppTheme.rankOutsideColor;
    }
  }

  /// Format time axis label based on total range duration
  /// Uses absolute time (HH:mm) for longer ranges, relative time for short ranges
  String _formatTimeAxisLabel(
    DateTime timestamp,
    DateTime firstTimestamp,
    DateTime lastTimestamp,
  ) {
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
}
