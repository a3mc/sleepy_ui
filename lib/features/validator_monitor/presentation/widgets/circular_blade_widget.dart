import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/themes/app_theme.dart';
import '../../data/models/validator_snapshot.dart';
import 'circular_blade_painter.dart';
import 'event_marker_painter.dart';

class CircularBladeWidget extends StatefulWidget {
  final List<ValidatorSnapshot> snapshots;
  final String? rank;
  final String? alertStatus;
  final Color? alertColor;

  const CircularBladeWidget({
    super.key,
    required this.snapshots,
    this.rank,
    this.alertStatus,
    this.alertColor = Colors.green,
  });

  @override
  State<CircularBladeWidget> createState() => _CircularBladeWidgetState();
}

class _CircularBladeWidgetState extends State<CircularBladeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  DateTime? _lastSnapshotTime;
  final ValueNotifier<double> _secondsSinceUpdate = ValueNotifier(0.0);
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _controller.forward();

    // Update timer every 100ms - smooth for user, 2x better than original 50ms
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_lastSnapshotTime != null) {
        _secondsSinceUpdate.value =
            DateTime.now().difference(_lastSnapshotTime!).inMilliseconds /
                1000.0;
      }
    });
  }

  @override
  void didUpdateWidget(CircularBladeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.snapshots.length != oldWidget.snapshots.length) {
      _controller.forward(from: 0.7);
    }

    // Check if we have a new snapshot by comparing timestamps
    if (widget.snapshots.isNotEmpty) {
      final currentTime = widget.snapshots.last.timestamp;
      if (_lastSnapshotTime != currentTime) {
        _lastSnapshotTime = currentTime;
        _secondsSinceUpdate.value = 0; // Reset counter
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _updateTimer?.cancel();
    _secondsSinceUpdate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundDarker,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          // CRITICAL: Must match CircularBladePainter's radius calculation
          // Blade painter uses min(width, height) to fit in available space
          final radius = math.min(size.width, size.height) / 2;

          // Platform detection
          final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

          // Ring spacing and thickness proportional to radius
          // Make rings very compact on mobile
          final ringSpacing = isMobile
              ? radius * 0.003
              : radius * 0.008; // 0.3% mobile, 0.8% desktop
          final ringThickness =
              radius * 0.016; // 1.6% of radius (dot diameter, ~4px)
          final dotRadius = ringThickness / 2; // 0.8% of radius

          // Blade rings end at exactly 90% of radius
          // Want tiny gap (0.5%) then dots start
          // With 4 rings at mobile spacing: 91.1%, 91.7%, 92.3%, 92.9% (total span ~2%)
          final bladeEndRadius = radius * 0.90;
          final gapSize = radius * 0.005; // 0.5% gap
          final eventMarkerStartRadius = bladeEndRadius + gapSize + dotRadius;

          return Semantics(
            label: _buildSemanticDescription(),
            readOnly: true,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RepaintBoundary(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: size,
                        painter: CircularBladePainter(
                          snapshots: widget.snapshots,
                          animation: _animation,
                          rank: widget.rank,
                        ),
                      ),
                      CustomPaint(
                        size: size,
                        painter: EventMarkerPainter(
                          snapshots: widget.snapshots,
                          innerRadius: eventMarkerStartRadius,
                          ringSpacing: ringSpacing,
                          ringThickness: ringThickness,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildCenterInfo(context, radius),
                // Timer widget at bottom-right corner
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _buildTimerWidget(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _buildSemanticDescription() {
    if (widget.snapshots.isEmpty) {
      return 'Entity performance: No data available';
    }

    final latest = widget.snapshots.last;
    final voteDistance = latest.voteDistance;
    final rootDistance = latest.rootDistance;

    String voteStatus;
    if (voteDistance == 0) {
      voteStatus = 'on par with position 1';
    } else if (voteDistance < 0) {
      voteStatus = 'ahead of position 1 by ${voteDistance.abs()} units';
    } else {
      voteStatus = '$voteDistance units behind position 1';
    }

    String rootStatus = 'root distance $rootDistance';

    final rankInfo =
        widget.rank != null ? ', current position ${widget.rank}' : '';

    return 'Entity performance: $voteStatus, $rootStatus$rankInfo';
  }

  Widget _buildCenterInfo(BuildContext context, double radius) {
    final theme = Theme.of(context);
    // ignore: unused_local_variable
    final latestSnapshot =
        widget.snapshots.isNotEmpty ? widget.snapshots.last : null;

    // Calculate font sizes proportional to circle radius (golden ratio)
    final rankFontSize = (radius * 0.19).clamp(24.0, 60.0); // 19% of radius
    final statusFontSize = (radius * 0.04).clamp(6.0, 12.0); // 4% of radius
    final verticalSpacing = (radius * 0.025).clamp(3.0, 8.0); // 2.5% of radius

    // Determine text color based on rank tier
    Color rankTextColor = Colors.white;
    if (widget.rank != null) {
      final cleanRank = widget.rank!.replaceAll(RegExp(r'[^\d]'), '');
      final rankNum = int.tryParse(cleanRank);
      if (rankNum != null) {
        if (rankNum <= 100) {
          rankTextColor = AppTheme.rankTop100Color; // Green
        } else if (rankNum <= 200) {
          rankTextColor = AppTheme.rankTop200Color; // Dark blue
        } else {
          rankTextColor = AppTheme.rankOutsideColor; // Gray
        }
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.rank != null)
          Stack(
            children: [
              // Subtle dark stroke matching app theme
              Text(
                widget.rank!,
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: rankFontSize,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3.0
                    ..color = AppTheme
                        .backgroundDarker, // Use app's dark background color
                ),
              ),
              // Fill layer (color-coded rank)
              Text(
                widget.rank!,
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: rankTextColor,
                  fontSize: rankFontSize,
                ),
              ),
            ],
          ),
        SizedBox(height: verticalSpacing),
        if (widget.alertStatus != null && widget.alertColor != null)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: radius * 0.04,
              vertical: radius * 0.01,
            ),
            decoration: BoxDecoration(
              color: widget.alertColor!.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(radius * 0.04),
              border: Border.all(
                color: widget.alertColor!,
                width: (radius * 0.008).clamp(1.0, 2.0),
              ),
            ),
            child: Text(
              widget.alertStatus!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: widget.alertColor,
                fontWeight: FontWeight.bold,
                fontSize: statusFontSize,
              ),
            ),
          ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildMetricRow(String label, int value, ThemeData theme) {
    Color color;
    if (label == 'V') {
      // Vote distance: 0=excellent, 1=good, 2=warning, >2=critical
      if (value == 0) {
        color = AppTheme.ringExcellentColor;
      } else if (value == 1) {
        color = AppTheme.ringGoodColor;
      } else if (value == 2) {
        color = AppTheme.ringWarningColor;
      } else {
        color = AppTheme.ringCriticalColor;
      }
    } else if (label == 'R') {
      // Root distance: 0=excellent, 1=good, 2=warning, >2=critical
      if (value == 0) {
        color = AppTheme.ringExcellentColor;
      } else if (value == 1) {
        color = AppTheme.ringGoodColor;
      } else if (value == 2) {
        color = AppTheme.ringWarningColor;
      } else {
        color = AppTheme.ringCriticalColor;
      }
    } else {
      // Gap to rank1 (negative = behind, closer to 0 = better)
      color = value >= -5000
          ? Colors.green
          : (value >= -50000 ? Colors.orange : Colors.red);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color, width: 1),
          ),
          child: Text(
            value.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimerWidget() {
    final theme = Theme.of(context);

    return ValueListenableBuilder<double>(
      valueListenable: _secondsSinceUpdate,
      builder: (context, seconds, child) {
        // Format: "0.0s" with 1 decimal precision
        final timeText = seconds.toStringAsFixed(1);

        // Color based on freshness: green < 3s, blue < 5s, red >= 5s
        Color timeColor;
        if (seconds < 3.0) {
          timeColor = AppTheme.rankTop100Color; // Green - fresh
        } else if (seconds < 5.0) {
          timeColor = AppTheme.rankTop200Color; // Blue - ok
        } else {
          timeColor = AppTheme.ringCriticalColor; // Red - stale
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.backgroundDarker,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: timeColor.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: timeColor,
                  boxShadow: [
                    BoxShadow(
                      color: timeColor.withValues(alpha: 0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${timeText}s',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: timeColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
