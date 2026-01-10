import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../../../../core/themes/app_theme.dart';
import '../../data/models/event_metadata.dart';
import '../../data/models/validator_snapshot.dart';

class CreditsMonitoringPanelV2 extends ConsumerStatefulWidget {
  final EventMetadata? events;
  final int? currentCreditsGap;
  final ValidatorSnapshot? snapshot;

  const CreditsMonitoringPanelV2({
    super.key,
    required this.events,
    this.currentCreditsGap,
    this.snapshot,
  });

  @override
  ConsumerState<CreditsMonitoringPanelV2> createState() =>
      _CreditsMonitoringPanelV2State();
}

class _CreditsMonitoringPanelV2State
    extends ConsumerState<CreditsMonitoringPanelV2>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scanlineController;
  late AnimationController _glitchController;
  late AnimationController _matrixController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scanlineAnimation;

  final math.Random _random = math.Random();
  String _matrixChars = '';
  bool _matrixAnimationActive = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _scanlineController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();

    _glitchController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    // Matrix controller initialized but NOT started - only runs during fork activity
    _matrixController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..addListener(_updateMatrixChars);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scanlineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanlineController, curve: Curves.linear),
    );

    _generateMatrixChars();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanlineController.dispose();
    _glitchController.dispose();
    _matrixController.dispose();
    super.dispose();
  }

  void _updateMatrixChars() {
    if (_random.nextDouble() > 0.7) {
      setState(() {
        _generateMatrixChars();
      });
    }
  }

  void _generateMatrixChars() {
    const chars = 'ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜｦﾝ01';
    _matrixChars =
        List.generate(400, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  void _triggerGlitch() {
    if (!_glitchController.isAnimating) {
      _glitchController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = widget.events;

    if (events == null) {
      return const SizedBox.shrink();
    }

    final fork = events.fork;

    final hasForkActivity = !fork.isIdle && !events.epochBoundary.inWindow;
    final hasEpochBoundary = events.epochBoundary.inWindow;
    final inCooldown = fork.cooldownCyclesRemaining != null &&
        fork.cooldownCyclesRemaining! > 0 &&
        !hasForkActivity &&
        !hasEpochBoundary;

    // Start/stop matrix animation based on fork activity (performance optimization)
    if (hasForkActivity && !_matrixAnimationActive) {
      _matrixAnimationActive = true;
      _matrixController.repeat();
    } else if (!hasForkActivity && _matrixAnimationActive) {
      _matrixAnimationActive = false;
      _matrixController.stop();
    }

    if (hasForkActivity && _random.nextDouble() > 0.95) {
      _triggerGlitch();
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge(
            [_pulseAnimation, _scanlineAnimation, _glitchController]),
        builder: (context, child) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: _getBorderColor(fork.phase, _pulseAnimation.value),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _getBorderColor(fork.phase, _pulseAnimation.value)
                          .withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Stack(
                    children: [
                      CustomPaint(
                        painter: HexGridPainter(
                          animation: _scanlineAnimation.value,
                          color: _getBorderColor(
                              fork.phase, _pulseAnimation.value),
                        ),
                        child: Container(),
                      ),
                      Positioned(
                        top: _scanlineAnimation.value * 250,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.transparent,
                                _getBorderColor(fork.phase, 1.0)
                                    .withValues(alpha: 0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (hasForkActivity)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 0.15,
                              child: Text(
                                _matrixChars,
                                style: TextStyle(
                                  color: _getBorderColor(fork.phase, 1.0),
                                  fontSize: 8,
                                  fontFamily: 'monospace',
                                  height: 1.2,
                                ),
                                maxLines: 20,
                                overflow: TextOverflow.clip,
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHolographicHeader(
                                fork, _pulseAnimation.value),
                            const SizedBox(height: 16),
                            if (hasEpochBoundary)
                              _buildEpochBoundary(events.epochBoundary)
                            else if (hasForkActivity)
                              _buildActiveDetection(
                                  fork, _scanlineAnimation.value)
                            else if (inCooldown)
                              _buildCooldownState(fork, _pulseAnimation.value)
                            else
                              _buildHolographicIdle(
                                  fork, _pulseAnimation.value),
                          ],
                        ),
                      ),
                      if (_glitchController.isAnimating)
                        Positioned.fill(
                          child: Opacity(
                            opacity: (1.0 - _glitchController.value) * 0.8,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _getBorderColor(fork.phase, 1.0)
                                        .withValues(alpha: 0.3),
                                    Colors.transparent,
                                    _getBorderColor(fork.phase, 1.0)
                                        .withValues(alpha: 0.3),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ..._buildCornerAccents(
                          _getBorderColor(fork.phase, _pulseAnimation.value)),
                    ],
                  ),
                ),
              ),
            ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildCornerAccents(Color color) {
    return [
      Positioned(
        top: 0,
        left: 0,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: 2),
              left: BorderSide(color: color, width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: 2),
              right: BorderSide(color: color, width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: color, width: 2),
              left: BorderSide(color: color, width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        right: 0,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: color, width: 2),
              right: BorderSide(color: color, width: 2),
            ),
          ),
        ),
      ),
    ];
  }

  Color _getBorderColor(String phase, double pulse) {
    switch (phase) {
      case 'Stabilizing':
        return Color.lerp(
          AppTheme.forkStabilizingColor,
          AppTheme.forkStabilizingColor,
          pulse,
        )!;
      case 'RankSampling':
        return Color.lerp(
          AppTheme.forkRankSamplingColor,
          AppTheme.forkRankSamplingColor,
          pulse,
        )!;
      case 'Confirmed':
        return Color.lerp(
          AppTheme.forkCreditsLossColor,
          AppTheme.forkCreditsLossColor,
          pulse,
        )!;
      default:
        return AppTheme.alertSentColor.withValues(alpha: 0.6 + (pulse * 0.4));
    }
  }

  Color _getPhaseColor(String phase) {
    switch (phase) {
      case 'Stabilizing':
        return AppTheme.forkStabilizingColor;
      case 'RankSampling':
        return AppTheme.forkRankSamplingColor;
      case 'Confirmed':
        return AppTheme.forkCreditsLossColor;
      default:
        return AppTheme.alertSentColor;
    }
  }

  Widget _buildHolographicHeader(ForkInfo fork, double pulse) {
    final phaseColor = _getPhaseColor(fork.phase);
    final statusText = fork.isIdle ? 'STANDBY' : fork.phase.toUpperCase();
    final isIdle = fork.isIdle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color.lerp(phaseColor, Colors.white, pulse * 0.5)!,
                    phaseColor,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: phaseColor.withValues(alpha: 0.8),
                    blurRadius: 8 + (pulse * 4),
                    spreadRadius: 2 + (pulse * 2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show branding in STANDBY, detector label in active states
                  Text(
                    isIdle ? 'MADE BY ART3MIS.CLOUD' : '▸ DETECTION ACTIVE',
                    style: TextStyle(
                      color: phaseColor.withValues(alpha: 0.6),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.0,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        Color.lerp(phaseColor, Colors.white, pulse * 0.3)!,
                        phaseColor,
                      ],
                    ).createShader(bounds),
                    child: const Text(
                      'CREDITS MONITOR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    phaseColor.withValues(alpha: 0.0),
                    phaseColor.withValues(alpha: 0.2),
                  ],
                ),
                border: Border.all(color: phaseColor, width: 1),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: phaseColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveDetection(ForkInfo fork, double scanline) {
    final phaseColor = _getPhaseColor(fork.phase);
    final loopsSinceDetection = fork.loopsSinceDetection ?? 0;
    final expectedCycles = fork.gapSettleWait + fork.gapStableConfirm;
    final progress = (loopsSinceDetection / expectedCycles).clamp(0.0, 1.0);

    // Calculate real-time metrics
    final baselineGap = fork.baselineGap ?? 0;
    final currentGap = fork.currentGap ?? 0;
    final gapDelta = (currentGap - baselineGap).abs();
    final creditsLost = fork.creditsLost ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                phaseColor.withValues(alpha: 0.3),
                phaseColor.withValues(alpha: 0.1),
              ],
            ),
            border: Border.all(
              color: phaseColor.withValues(alpha: 0.5),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: phaseColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: phaseColor.withValues(alpha: 0.8),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ACTIVE DETECTION',
                style: TextStyle(
                  color: phaseColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                fork.phase.toUpperCase(),
                style: TextStyle(
                  color: phaseColor.withValues(alpha: 0.7),
                  fontSize: 9,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Real-time metrics grid
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            border: Border.all(
              color: phaseColor.withValues(alpha: 0.2),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            children: [
              // Cycles tracker
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.rotate_right,
                        size: 10,
                        color: phaseColor.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'CYCLES',
                        style: TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 8,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        '$loopsSinceDetection',
                        style: TextStyle(
                          color: phaseColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        ' / $expectedCycles',
                        style: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Progress bar
              Stack(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundDarker,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            phaseColor.withValues(alpha: 0.5),
                            phaseColor,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: phaseColor.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Credits metrics
              Row(
                children: [
                  Expanded(
                    child: _buildMetricColumn(
                      'LOSS',
                      '$creditsLost',
                      AppTheme.lossBackgroundColor,
                      Icons.arrow_downward,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: AppTheme.borderSubtle,
                  ),
                  Expanded(
                    child: _buildMetricColumn(
                      'DELTA',
                      '$gapDelta',
                      AppTheme.alertPendingColor,
                      Icons.show_chart,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: AppTheme.borderSubtle,
                  ),
                  Expanded(
                    child: _buildMetricColumn(
                      'GAP',
                      '${currentGap.abs()}',
                      AppTheme.forkStabilizingColor,
                      Icons.trending_down,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Data stream indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.backgroundDarkest.withValues(alpha: 0.5),
            border: Border.all(
              color: phaseColor.withValues(alpha: 0.2),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: phaseColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '▸ MONITORING STABILIZATION',
                style: TextStyle(
                  color: phaseColor.withValues(alpha: 0.6),
                  fontSize: 8,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Animated scanline position indicator
              SizedBox(
                width: 40,
                height: 8,
                child: CustomPaint(
                  painter: _WaveformPainter(
                    progress: scanline,
                    color: phaseColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricColumn(
      String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          size: 10,
          color: color.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 7,
            fontFamily: 'monospace',
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildHolographicIdle(ForkInfo fork, double pulse) {
    final idleColor = AppTheme.forkIdleColor;
    final snapshot = widget.snapshot;
    final voteDistance = snapshot?.voteDistance ?? 0;
    final rootDistance = snapshot?.rootDistance ?? 0;
    final creditsDelta = snapshot?.creditsPerformanceGap ?? 0;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.12,
              child: Text(
                _matrixChars,
                style: TextStyle(
                  color: idleColor,
                  fontSize: 8,
                  fontFamily: 'monospace',
                  height: 1.2,
                ),
                maxLines: 20,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 4),
            Center(
              child: Column(
                children: [
                  Transform.rotate(
                    angle: pulse * math.pi * 2,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            idleColor.withValues(alpha: 0.0),
                            idleColor.withValues(alpha: 0.3),
                            idleColor,
                          ],
                          stops: const [0.0, 0.7, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: idleColor.withValues(alpha: 0.6),
                            blurRadius: 20 + (pulse * 10),
                            spreadRadius: 5 + (pulse * 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: idleColor,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.check,
                            color: idleColor,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        idleColor,
                        idleColor.withValues(alpha: 0.3),
                      ],
                    ).createShader(bounds),
                    child: const Text(
                      'SYSTEM NOMINAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '[ NO ANOMALIES DETECTED ]',
                    style: TextStyle(
                      color: idleColor.withValues(alpha: 0.5),
                      fontSize: 8,
                      letterSpacing: 1.0,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLiveMetric(
                          'VOTE',
                          voteDistance,
                          voteDistance == 0
                              ? idleColor
                              : const Color(0xFF00AAFF),
                          pulse),
                      Container(
                          width: 1,
                          height: 25,
                          color: idleColor.withValues(alpha: 0.2)),
                      _buildLiveMetric(
                          'ROOT',
                          rootDistance,
                          rootDistance == 0
                              ? idleColor
                              : const Color(0xFFFF6B6B),
                          pulse * 0.7),
                      Container(
                          width: 1,
                          height: 25,
                          color: idleColor.withValues(alpha: 0.2)),
                      _buildLiveMetric(
                          'Δ',
                          creditsDelta,
                          creditsDelta <= 0
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFF9800),
                          pulse * 0.5),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildMetricDot('SYNC', idleColor, pulse),
                      _buildMetricDot('SCAN', idleColor, pulse * 0.7),
                      _buildMetricDot('TRACK', idleColor, pulse * 0.5),
                      _buildMetricDot('EVAL', idleColor, pulse * 0.3),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ],
    );
  }

  Widget _buildLiveMetric(String label, int value, Color color, double pulse) {
    return TweenAnimationBuilder<int>(
      duration: const Duration(milliseconds: 800),
      tween: IntTween(begin: value, end: value),
      curve: Curves.easeOut,
      builder: (context, animatedValue, child) {
        return Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 7,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 3),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  color,
                  color.withValues(alpha: 0.6 + (pulse * 0.4)),
                ],
              ).createShader(bounds),
              child: Text(
                animatedValue.abs().toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricDot(String label, Color color, double pulse) {
    return Column(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: pulse * 0.8),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.6),
            fontSize: 7,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildCooldownState(ForkInfo fork, double pulse) {
    final cooldownRemaining = fork.cooldownCyclesRemaining ?? 0;
    final cooldownDuration = fork.forkCooldownCycles ?? 32;
    final progress = cooldownRemaining > 0
        ? 1.0 - (cooldownRemaining / cooldownDuration)
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDarkest,
        border: Border.all(
          color:
              AppTheme.alertPendingColor.withValues(alpha: 0.8 + (pulse * 0.2)),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '[COOLDOWN ACTIVE]',
                style: TextStyle(
                  color: AppTheme.alertPendingColor,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$cooldownRemaining / $cooldownDuration cycles',
                style: const TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor:
                    AppTheme.alertPendingColor.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.alertPendingColor
                      .withValues(alpha: 0.8 + (pulse * 0.2)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpochBoundary(EpochBoundaryInfo? epoch) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDarkest,
        border: Border.all(
          color: AppTheme.royalBlueAccent,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '[EPOCH BOUNDARY - ${epoch?.loopsRemaining ?? 0} cycles remaining]',
        style: const TextStyle(
          color: AppTheme.royalBlueAccent,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class HexGridPainter extends CustomPainter {
  final double animation;
  final Color color;

  HexGridPainter({required this.animation, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Use fixed alpha for consistent appearance - animation variance imperceptible at 0.03
    final paint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const hexSize = 20.0;
    final cols = (size.width / (hexSize * 1.5)).ceil() + 1;
    final rows = (size.height / (hexSize * math.sqrt(3))).ceil() + 1;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final x = col * hexSize * 1.5;
        final y = row * hexSize * math.sqrt(3) +
            (col.isOdd ? hexSize * math.sqrt(3) / 2 : 0);

        _drawHexagon(canvas, paint, Offset(x, y), hexSize);
      }
    }
  }

  void _drawHexagon(Canvas canvas, Paint paint, Offset center, double size) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i;
      final x = center.dx + size * math.cos(angle);
      final y = center.dy + size * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(HexGridPainter oldDelegate) =>
      oldDelegate.color != color; // Only repaint on color (phase) change
}

/// Waveform painter for real-time data visualization
class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    final points = 8;

    for (int i = 0; i < points; i++) {
      final x = (size.width / (points - 1)) * i;
      final phase = (progress * math.pi * 4) + (i * 0.5);
      final y = size.height / 2 + math.sin(phase) * (size.height / 3);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
