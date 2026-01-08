import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/themes/app_theme.dart';
import '../../data/models/event_metadata.dart';

class CreditsMonitoringPanel extends ConsumerStatefulWidget {
  final EventMetadata? events;
  final int? currentCreditsGap;
  final int? creditsLost;
  final int? gapAtDetection;

  const CreditsMonitoringPanel({
    super.key,
    required this.events,
    this.currentCreditsGap,
    this.creditsLost,
    this.gapAtDetection,
  });

  @override
  ConsumerState<CreditsMonitoringPanel> createState() =>
      _CreditsMonitoringPanelState();
}

class _CreditsMonitoringPanelState extends ConsumerState<CreditsMonitoringPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Extract events to avoid force unwrap
    final events = widget.events;
    if (events == null) return const SizedBox.shrink();

    // DEBUG: Print all fork detection fields
    final fork = events.fork;
    if (fork.phase != 'Idle') {
      debugPrint('\n═══ FORK DETECTION DATA ═══');
      debugPrint('Phase: ${fork.phase}');
      debugPrint('Alert sent this cycle: ${fork.alertSentThisCycle}');
      debugPrint('Event ID: ${fork.eventId}');
      debugPrint('Detected at: ${fork.detectedAt}');
      debugPrint('Loops since detection: ${fork.loopsSinceDetection}');
      debugPrint('Gap settle wait (config): ${fork.gapSettleWait}');
      debugPrint('Gap stable confirm (config): ${fork.gapStableConfirm}');
      debugPrint('Fork cooldown cycles (config): ${fork.forkCooldownCycles}');
      debugPrint('Cooldown remaining: ${fork.cooldownCyclesRemaining}');
      debugPrint('Credits lost (immediate): ${fork.creditsLost}');
      debugPrint('Stabilized credits lost: ${fork.stabilizedCreditsLost}');
      debugPrint('Baseline gap: ${fork.baselineGap}');
      debugPrint('Current gap: ${fork.currentGap}');
      debugPrint('Stabilized gap: ${fork.stabilizedGap}');
      if (fork.lastAlert != null) {
        final alert = fork.lastAlert!;
        debugPrint('Last Alert Event ID: ${alert.eventId}');
        debugPrint('Last Alert Detected at: ${alert.detectedAt}');
        debugPrint('Last Alert Credits lost: ${alert.creditsLost}');
        debugPrint('Last Alert Stabilized: ${alert.stabilizedCreditsLost}');
        debugPrint('Last Alert Baseline gap: ${alert.baselineGap}');
        debugPrint('Last Alert Stabilized gap: ${alert.stabilizedGap}');
        debugPrint('Last Alert Rank averaged: ${alert.rankAveraged}');
        debugPrint('Last Alert Loops to stabilize: ${alert.loopsToStabilize}');
        debugPrint('Last Alert Recovered to tip: ${alert.recoveredToTip}');
      }
      debugPrint('═══════════════════════════\n');
    }

    final hasForkActivity = !events.fork.isIdle;
    final hasEpochBoundary = events.epochBoundary.inWindow;

    // Check for post-incident cooldown using proper field
    final inCooldown =
        events.fork.isIdle && events.fork.cooldownCyclesRemaining != null;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.backgroundDarker,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppTheme.purpleAccent,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(events.fork),
              const SizedBox(height: 8),
              if (hasEpochBoundary)
                _buildEpochBoundary()
              else if (hasForkActivity)
                _buildLossDetection()
              else if (inCooldown)
                _buildCooldownState()
              else
                _buildIdleState(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ForkInfo fork) {
    return Row(
      children: [
        Icon(Icons.analytics_outlined, color: AppTheme.purpleAccent, size: 16),
        const SizedBox(width: 8),
        const Text(
          'RESOURCE LOSS MONITORING',
          style: TextStyle(
            color: AppTheme.purpleAccent,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildEpochBoundary() {
    final epochBoundary = widget.events!.epochBoundary;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.royalBlueAccent,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined,
                  color: AppTheme.royalBlueAccent, size: 14),
              const SizedBox(width: 6),
              const Text(
                'Epoch Boundary',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Detection paused (${epochBoundary.loopsRemaining} cycles)',
            style: const TextStyle(
              color: AppTheme.textQuaternary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          _buildCountdownBar(
            progress: 1.0 - (epochBoundary.loopsRemaining / 30),
            color: AppTheme.royalBlueAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildLossDetection() {
    final fork = widget.events!.fork;
    final loopsSinceDetection = fork.loopsSinceDetection ?? 0;

    // Calculate phase-specific progress
    String phaseLabel;
    String phaseDescription;
    Color phaseColor;
    String counterDisplay;
    double progress;

    switch (fork.phase) {
      case 'Stabilizing':
        phaseLabel = 'Gap Stabilization';
        phaseDescription =
            'Waiting for gap to stabilize (expected ${fork.gapSettleWait} cycles)';
        phaseColor = AppTheme.forkStabilizingColor;
        counterDisplay = '$loopsSinceDetection cycles';
        progress = (loopsSinceDetection / fork.gapSettleWait).clamp(0.0, 1.0);
        break;
      case 'RankSampling':
        phaseLabel = 'Rank Analysis';
        phaseDescription =
            'Sampling rank data (expected ${fork.gapStableConfirm} cycles)';
        phaseColor = AppTheme.forkRankSamplingColor;
        counterDisplay = '$loopsSinceDetection cycles';
        progress =
            (loopsSinceDetection / (fork.gapSettleWait + fork.gapStableConfirm))
                .clamp(0.0, 1.0);
        break;
      case 'Confirmed':
        phaseLabel = 'Sending Alert';
        phaseDescription = 'Delivering alert notification';
        phaseColor = AppTheme.forkCreditsLossColor;
        counterDisplay = 'Validated';
        progress = 1.0;
        break;
      default:
        phaseLabel = 'Idle';
        phaseDescription = 'No loss detected';
        phaseColor = AppTheme.textSecondaryAlt;
        counterDisplay = '0/0';
        progress = 0.0;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: phaseColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: phaseColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: phaseColor.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    phaseLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                counterDisplay,
                style: TextStyle(
                  color: phaseColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildCountdownBar(progress: progress, color: phaseColor),
          const SizedBox(height: 6),
          Text(
            phaseDescription,
            style: const TextStyle(
              color: AppTheme.textQuaternary,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleState() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final pulseValue =
            0.5 + (0.5 * (1 - (_pulseAnimation.value - 0.5).abs() * 2));
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.backgroundElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Color.lerp(
                AppTheme.borderSubtle,
                AppTheme.purpleAccent,
                pulseValue * 0.3,
              )!,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        AppTheme.textTertiary,
                        AppTheme.purpleAccent,
                        pulseValue,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.purpleAccent
                              .withValues(alpha: pulseValue * 0.4),
                          blurRadius: 6 * pulseValue,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Monitoring Active',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'No loss events detected',
                style: TextStyle(
                  color: AppTheme.textQuaternary,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCooldownState() {
    final fork = widget.events!.fork;
    final remaining = fork.cooldownCyclesRemaining;
    final total = fork.forkCooldownCycles;

    // This function only called when cooldownCyclesRemaining != null (cooldown active)
    // Two scenarios why cooldown is active:
    // 1. alert_sent_this_cycle = true → Alert sent successfully → spam prevention cooldown
    // 2. alert_sent_this_cycle = false → Detection timed out (unstable) → retry cooldown
    // Note: Normal healthy state has cooldownCyclesRemaining = null (shows Idle widget instead)
    final alertSent = fork.alertSentThisCycle;
    final stabilizedLoss = fork.stabilizedCreditsLost;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.getAlertColor(alertSent),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppTheme.getAlertColor(alertSent),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.getAlertColor(alertSent)
                              .withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    alertSent ? 'Alert Sent' : 'Detection Timeout',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (remaining != null && total != null)
                Text(
                  '$remaining/$total',
                  style: TextStyle(
                    color: AppTheme.getAlertColor(alertSent),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            alertSent
                ? 'Loss: ${stabilizedLoss ?? 0} credits. Cooldown active to prevent duplicate alerts.'
                : 'System unstable, could not confirm loss within tracking limit. Waiting before retry.',
            style: const TextStyle(
              color: AppTheme.textQuaternary,
              fontSize: 9,
            ),
          ),
          if (remaining != null && total != null) ...[
            const SizedBox(height: 10),
            _buildCooldownProgressBar(
              remaining: remaining,
              total: total,
              isAlertSent: alertSent,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCooldownProgressBar({
    required int remaining,
    required int total,
    required bool isAlertSent,
  }) {
    final progress = (total - remaining) / total;
    final percentComplete = (progress * 100).toInt();
    final barColor = AppTheme.getAlertColor(isAlertSent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isAlertSent ? 'Cooldown progress' : 'Retry countdown',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$percentComplete%',
              style: TextStyle(
                color: barColor,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: AppTheme.backgroundDarker,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: AppTheme.borderSubtle,
                  width: 1,
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                return TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 400),
                  tween: Tween(begin: 0.0, end: progress),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return Container(
                      height: 6,
                      width: constraints.maxWidth * value,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            barColor,
                            barColor.withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$remaining cycles until ${isAlertSent ? "cooldown expires" : "next detection attempt"}',
          style: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownBar({required double progress, required Color color}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.backgroundDarker,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 400),
              tween: Tween(begin: 0.0, end: progress),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return Container(
                  height: 4,
                  width: constraints.maxWidth * value,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.6),
                        color,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
