import 'dart:ui' show ImageFilter;
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:window_manager/window_manager.dart';
import '../../../../core/themes/app_theme.dart';
import '../providers/validator_providers.dart';
import '../providers/compact_mode_provider.dart';
import '../providers/connection_status_provider.dart';
import '../providers/auth_token_provider.dart';
import '../providers/endpoint_config_provider.dart';
import '../providers/credits_feed_visibility_provider.dart';
import '../providers/fullscreen_provider.dart';
import '../providers/wake_lock_provider.dart';
import 'settings_screen.dart';
import 'token_gate_screen.dart';
import '../widgets/circular_blade_widget.dart';
import '../widgets/degradation_status_panel.dart';
import '../widgets/credits_monitoring_panel_v2.dart';
import '../widgets/network_gaps_chart.dart';
import '../widgets/rank_chart.dart';
import '../widgets/connection_status_banner.dart';
import '../../data/models/validator_snapshot.dart';
import '../providers/time_range_provider.dart';

// Always-on-top state provider
final _alwaysOnTopProvider = StateProvider<bool>((ref) => false);

// Loading screen timer provider - tracks when to show connection warnings
final _loadingTimerProvider = StateProvider<int>((ref) => 0);

// Main dashboard with circular blade visualization
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _loadingTimer;
  FocusNode? _keyboardFocusNode;

  @override
  void initState() {
    super.initState();

    // Initialize keyboard focus node for desktop platforms (F11 fullscreen support)
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      _keyboardFocusNode = FocusNode();
    }

    // Initialize wake lock provider on Android (triggers auto-enable on first app launch)
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(wakeLockEnabledProvider);
      });
    }

    // Verify credentials before starting operations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = ref.read(authTokenNotifierProvider).value;
      final endpoint = ref.read(endpointConfigNotifierProvider).value;

      if (token == null || token.isEmpty || endpoint == null) {
        // Credentials missing - cancel timer before navigation to prevent leak
        _loadingTimer?.cancel();
        // Credentials missing - return to token gate
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const TokenGateScreen()),
        );
        return;
      }

      // Credentials confirmed - operations will proceed normally
    });

    // Start timer that increments every second
    _loadingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        ref.read(_loadingTimerProvider.notifier).state = timer.tick;
      }
    });
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _keyboardFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshotBuffer = ref.watch(snapshotBufferProvider);
    final statusAsync = ref.watch(validatorStatusProvider);
    final healthAsync = ref.watch(serviceHealthProvider);
    final connectionState = ref.watch(connectionStatusProvider);
    final loadingSeconds = ref.watch(_loadingTimerProvider);

    // Check for authentication failures - redirect to token gate
    if (connectionState.errorMessage != null &&
        connectionState.errorMessage!.contains('Authentication failed')) {
      debugPrint(
          '[Dashboard] Auth failure detected, redirecting to token gate');
      debugPrint('[Dashboard] Error message: ${connectionState.errorMessage}');
      // Cancel timer before navigation to prevent timer leak
      _loadingTimer?.cancel();
      // Clear invalid token and return to token gate
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(authTokenNotifierProvider.notifier).deleteToken();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const TokenGateScreen()),
        );
      });
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 24),
              const Text(
                'Authentication Failed',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Returning to token entry...',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Wait for initial data before rendering UI
    // Cypherblade with 2+ snapshots is sufficient - indicates working SSE connection
    // Status/health endpoints can load in background (displayed when ready)
    final hasInitialData = snapshotBuffer.length >= 2;

    if (!hasInitialData) {
      // Check for authentication errors even before initial data loads
      final hasAuthError =
          connectionState.errorMessage?.contains('Authentication failed') ??
              false;

      // Only show connection status messages after 10 seconds
      final showConnectionWarnings = loadingSeconds >= 10;

      final String statusMessage;
      final Color statusColor;

      if (hasAuthError) {
        statusMessage =
            'Authentication Failed\n${connectionState.errorMessage ?? "Invalid bearer token"}';
        statusColor = Colors.red.shade300;
      } else if (showConnectionWarnings &&
          connectionState.status == ConnectionStatus.disconnected) {
        statusMessage =
            'Connecting to backend...\n${connectionState.errorMessage ?? "Checking network"}';
        statusColor = Colors.amber.shade300;
      } else if (showConnectionWarnings &&
          connectionState.status == ConnectionStatus.reconnecting) {
        final attempt = connectionState.retryAttempt;
        if (attempt <= 5) {
          statusMessage = 'Establishing connection...\nAttempt $attempt';
        } else {
          statusMessage = 'Still trying to connect...\nAttempt $attempt';
        }
        statusColor = Colors.amber.shade400;
      } else {
        // Clean startup - no warnings yet
        statusMessage = '';
        statusColor = const Color(0xFF00AAFF);
      }

      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.9 + (value * 0.1),
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF00AAFF).withValues(alpha: 0.2),
                        const Color(0xFF00AAFF).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  child: const Center(
                    child: SpinKitPulse(
                      color: Color(0xFF00AAFF),
                      size: 80.0,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  'SLEEPY UI',
                  style: TextStyle(
                    color: Color(0xFF00AAFF),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4.0,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'VALIDATOR MONITOR',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2.0,
                  ),
                ),
                if (statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Text(
                    statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                      height: 1.5,
                    ),
                  ),
                  // Show "Update Token" button if authentication failed
                  if (hasAuthError) ...[
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        ref
                            .read(authTokenNotifierProvider.notifier)
                            .deleteToken();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const TokenGateScreen()),
                        );
                      },
                      icon: const Icon(Icons.vpn_key),
                      label: const Text('UPDATE TOKEN'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                  // Show "Settings" button after 15 seconds for connection issues
                  if (!hasAuthError && loadingSeconds >= 15) ...[
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        );
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('OPEN SETTINGS'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00AAFF),
                        side: const BorderSide(color: Color(0xFF00AAFF)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) {
                      return LinearProgressIndicator(
                        value: value,
                        backgroundColor: const Color(0xFF1A1A1A),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          statusColor.withValues(alpha: 0.6),
                        ),
                        minHeight: 2,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Extract latest snapshot for delinquent status
    final latestSnapshot = snapshotBuffer.last;
    final isDelinquent = latestSnapshot.events?.delinquent.isActive ?? false;

    // Determine validator status based on ValidatorStatus.delinquent field
    // Only show ACTIVE/DEAD when we have actual status data from backend
    final statusLabel = statusAsync.when(
      data: (status) => status.delinquent ? 'DELINQUENT' : 'ACTIVE',
      loading: () => 'UNKNOWN',
      error: (error, stackTrace) => 'UNKNOWN',
    );

    final statusColor = statusAsync.when(
      data: (status) => status.delinquent ? Colors.red : Colors.green,
      loading: () => const Color(0xFFFF9800),
      error: (error, stackTrace) => const Color(0xFFFF9800),
    );

    final backendHealthy = statusAsync.hasValue;

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final compactMode = ref.watch(compactModeProvider);

    final scaffold = Scaffold(
      backgroundColor: AppTheme.backgroundDarkest,
      appBar: AppBar(
        title: isMobile
            ? _buildCompactEpochProgress(ref, backendHealthy && !isDelinquent)
            : compactMode
                ? Row(
                    children: [
                      // Desktop compact: simple text only (no progress bar)
                      Flexible(
                        flex: 0,
                        child: Consumer(
                          builder: (context, ref, _) {
                            final snapshots = ref.watch(snapshotBufferProvider);
                            final latestSnapshot =
                                snapshots.isNotEmpty ? snapshots.last : null;

                            if (latestSnapshot == null) {
                              return const SizedBox.shrink();
                            }

                            return Text(
                              '${latestSnapshot.progressPercent.toStringAsFixed(1)}% | ${latestSnapshot.estimatedTimeRemaining}',
                              style: const TextStyle(
                                color: Color(0xFFAAAAAA),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTimeRangeSelector(ref, compactMode: true),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'SLEEPY VALIDATOR MONITOR',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child:
                              _buildTimeRangeSelector(ref, compactMode: false),
                        ),
                      ),
                    ],
                  ),
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
              connectionState.status == ConnectionStatus.connected ? 0 : 32),
          child: const ConnectionStatusBanner(),
        ),
        actions: isMobile
            ? [
                if (!backendHealthy || isDelinquent)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      !backendHealthy ? 'BACKEND ISSUE' : 'DELINQUENT',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Semantics(
                  label: 'Open settings',
                  button: true,
                  child: IconButton(
                    icon: const Icon(Icons.settings, size: 20),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const SettingsScreen()),
                      );
                    },
                    tooltip: 'Settings',
                  ),
                ),
              ]
            : compactMode
                ? [
                    // Compact mode: only status indicator (no text, just colored dot)
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]
                : [
                    // Full mode: status indicator with text
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Fullscreen button (full mode only)
                    if (!kIsWeb &&
                        (Platform.isWindows ||
                            Platform.isLinux ||
                            Platform.isMacOS))
                      Consumer(
                        builder: (context, ref, child) {
                          final isFullscreen = ref.watch(fullscreenProvider);
                          return Semantics(
                            label: isFullscreen
                                ? 'Exit fullscreen'
                                : 'Enter fullscreen',
                            button: true,
                            child: IconButton(
                              icon: Icon(isFullscreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen),
                              onPressed: () {
                                ref.read(fullscreenProvider.notifier).toggle();
                              },
                              tooltip: isFullscreen
                                  ? 'Exit Fullscreen (F11)'
                                  : 'Fullscreen (F11)',
                            ),
                          );
                        },
                      ),
                    // Settings button (full mode only)
                    Semantics(
                      label: 'Open settings',
                      button: true,
                      child: IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const SettingsScreen()),
                          );
                        },
                        tooltip: 'Settings',
                      ),
                    ),
                  ],
      ),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compactMode = ref.watch(compactModeProvider);
              final isWideScreen = constraints.maxWidth > 1200 && !compactMode;

              return isWideScreen
                  ? _buildWideLayout(context, ref, snapshotBuffer, statusAsync)
                  : _buildCompactLayout(
                      context, ref, snapshotBuffer, statusAsync);
            },
          ),
          // Backend issue overlay - only show if we have no data
          // If SSE stream is working (we have snapshots), don't block UI with overlay
          if (snapshotBuffer.isEmpty)
            healthAsync.when(
              data: (health) {
                if (health.isHealthy) return const SizedBox.shrink();
                return _buildBackendIssueOverlay(
                    'Backend health check failed\nWaiting for data stream...');
              },
              loading: () => const SizedBox.shrink(),
              error: (_, stackTrace) => _buildBackendIssueOverlay(
                  'Connecting to backend...\nWaiting for data stream...'),
            ),
        ],
      ),
    );

    // Wrap scaffold with keyboard listener for F11 fullscreen toggle (desktop only)
    if (!isMobile && _keyboardFocusNode != null) {
      return KeyboardListener(
        focusNode: _keyboardFocusNode!,
        autofocus: true,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.f11) {
            ref.read(fullscreenProvider.notifier).toggle();
          }
        },
        child: scaffold,
      );
    }

    return scaffold;
  }

  Widget _buildWideLayout(
    BuildContext context,
    WidgetRef ref,
    List<ValidatorSnapshot> snapshotBuffer,
    AsyncValue statusAsync,
  ) {
    final latestSnapshot =
        snapshotBuffer.isNotEmpty ? snapshotBuffer.last : null;
    final bufferNotifier = ref.read(snapshotBufferProvider.notifier);
    final creditsLost = bufferNotifier.getCreditsLost();
    final gapAtDetection = bufferNotifier.forkGapAtDetection;

    return Column(
      children: [
        // Compact metrics bar at top
        _buildCompactMetrics(statusAsync),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top row: Chart + Cypherblade
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Chart with integrated flow and trend indicators in header
                      Expanded(
                        child: NetworkGapsChart(compactMode: false),
                      ),
                      const SizedBox(width: 4),
                      // Cypherblade - constrained max size
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 500,
                          maxHeight: 500,
                        ),
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final size = constraints.maxWidth;
                              final buttonSize =
                                  (size * 0.08).clamp(28.0, 40.0);
                              // Blade painted area is ~90% of radius, position button at edge of painted area
                              final buttonOffset = size *
                                  0.05; // 5% from container edge = at ~95% radius

                              return Stack(
                                children: [
                                  _buildCircularBlade(
                                      statusAsync, snapshotBuffer),
                                  // Compact mode button overlay
                                  Positioned(
                                    top: buttonOffset,
                                    right: buttonOffset,
                                    child: _buildCompactModeButton(
                                        ref, buttonSize),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Bottom row: Rank chart + Credits monitoring + Degradation panel
                SizedBox(
                  height: 300,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: RankChart(compactMode: false),
                      ),
                      const SizedBox(width: 4),
                      Consumer(
                        builder: (context, ref, _) {
                          final showCreditsFeed =
                              ref.watch(creditsFeedVisibilityProvider);
                          if (!showCreditsFeed) return const SizedBox.shrink();
                          return SizedBox(
                            width: 380,
                            height: double.infinity,
                            child: CreditsMonitoringPanelV2(
                              events: latestSnapshot?.events,
                              currentCreditsGap: latestSnapshot?.gapToRank1,
                              snapshot: latestSnapshot,
                            ),
                          );
                        },
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final showCreditsFeed =
                              ref.watch(creditsFeedVisibilityProvider);
                          return SizedBox(width: showCreditsFeed ? 4 : 0);
                        },
                      ),
                      SizedBox(
                        width: 380,
                        height: double.infinity,
                        child: DegradationStatusPanel(
                          events: latestSnapshot?.events,
                          currentCreditsGap: latestSnapshot?.gapToRank1,
                          creditsLost: creditsLost,
                          gapAtDetection: gapAtDetection,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Time range selector bar (desktop: full bar, mobile: compact)
  Widget _buildTimeRangeSelector(WidgetRef ref, {bool compactMode = false}) {
    final selectedRange = ref.watch(selectedTimeRangeProvider);

    // Compact mode: show only BLADE, 5M, 15M, 30M, 1H
    final allowedRanges = compactMode
        ? [
            ChartTimeRange.cypherblade,
            ChartTimeRange.min5,
            ChartTimeRange.min15,
            ChartTimeRange.min30,
            ChartTimeRange.hour1,
          ]
        : ChartTimeRange.values;

    return Wrap(
      spacing: compactMode ? 3 : 4,
      runSpacing: compactMode ? 3 : 4,
      children: allowedRanges.map((range) {
        final isSelected = range == selectedRange;
        return Semantics(
          label: 'Select time range: ${range.label}',
          button: true,
          selected: isSelected,
          child: InkWell(
            onTap: () {
              ref.read(selectedTimeRangeProvider.notifier).state = range;
            },
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compactMode ? 6 : 8,
                vertical: compactMode ? 2 : 3,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00AAFF)
                    : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF00CCFF)
                      : const Color(0xFF333333),
                  width: 1,
                ),
              ),
              child: Text(
                range.label,
                style: TextStyle(
                  color: isSelected ? Colors.black : const Color(0xFF888888),
                  fontSize: compactMode ? 9 : 9,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // Compact metrics bar
  Widget _buildCompactMetrics(AsyncValue statusAsync) {
    return Container(
      height: 48,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: statusAsync.when(
        data: (status) => Consumer(
          builder: (context, ref, _) {
            final snapshots = ref.watch(snapshotBufferProvider);
            final latestSnapshot = snapshots.isNotEmpty ? snapshots.last : null;

            return Row(
              children: [
                _buildMetric('EPOCH', status.epoch.toString()),
                const SizedBox(width: 48),
                _buildMetric('ACTIVE', status.activeValidators.toString()),
                const SizedBox(width: 48),
                _buildMetric(
                    'DELINQUENT', status.delinquentValidators.toString()),
                const SizedBox(width: 48),
                if (latestSnapshot != null &&
                    latestSnapshot.slotTimeMs > 0) ...[
                  _buildMetric(
                      'SLOT', '${latestSnapshot.slotTimeMs.round()}ms'),
                  const SizedBox(width: 48),
                ],
                if (latestSnapshot != null &&
                    latestSnapshot.cycleTimeSeconds > 0) ...[
                  _buildMetric('CYCLE',
                      '${latestSnapshot.cycleTimeSeconds.toStringAsFixed(1)}s'),
                  const SizedBox(width: 48),
                ],
                if (latestSnapshot != null)
                  Expanded(child: _buildEpochProgress(latestSnapshot)),
              ],
            );
          },
        ),
        loading: () => const SizedBox.shrink(),
        error: (_, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildEpochProgress(ValidatorSnapshot snapshot) {
    final percent = snapshot.progressPercent;
    final isComplete = percent >= 99.0;

    return Row(
      children: [
        const Text(
          'EPOCH PROGRESS',
          style: TextStyle(
            color: Color(0xFFAAAAAA),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: (percent / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isComplete
                              ? [
                                  const Color(0xFF4CAF50),
                                  const Color(0xFF81C784)
                                ]
                              : [
                                  const Color(0xFF00AAFF),
                                  const Color(0xFF0088CC)
                                ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${percent.toStringAsFixed(1)}%',
          style: const TextStyle(
            color: Color(0xFFE0E0E0),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            snapshot.estimatedTimeRemaining,
            style: const TextStyle(
              color: Color(0xFFAAAAAA),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetric(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFAAAAAA),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFE0E0E0),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(
    BuildContext context,
    WidgetRef ref,
    List<ValidatorSnapshot> snapshotBuffer,
    AsyncValue statusAsync,
  ) {
    final latestSnapshot =
        snapshotBuffer.isNotEmpty ? snapshotBuffer.last : null;
    final bufferNotifier = ref.read(snapshotBufferProvider.notifier);
    final creditsLost = bufferNotifier.getCreditsLost();
    final gapAtDetection = bufferNotifier.forkGapAtDetection;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Cypherblade: square based on screen width
        // Gap chart: remaining height (should be ~40-50% of screen)
        final screenWidth = constraints.maxWidth;
        final cyberbladeSize = screenWidth - 8; // Account for padding

        return SingleChildScrollView(
          padding: const EdgeInsets.all(4.0),
          child: Column(
            children: [
              // MODULE: Cypherblade (circular blade visualization)
              SizedBox(
                width: cyberbladeSize,
                height: cyberbladeSize * 0.85,
                child: Stack(
                  children: [
                    // Cypherblade with buttons
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.maxWidth;
                        final buttonSize = (size * 0.08).clamp(28.0, 40.0);
                        final buttonOffset = size * 0.05;

                        final isMobile =
                            !kIsWeb && (Platform.isAndroid || Platform.isIOS);

                        return Stack(
                          children: [
                            _buildCircularBlade(statusAsync, snapshotBuffer),
                            if (!isMobile)
                              Positioned(
                                top: buttonOffset,
                                right: buttonOffset,
                                child: _buildCompactModeButton(ref, buttonSize),
                              ),
                            if (isMobile)
                              Positioned(
                                top: buttonOffset,
                                right: buttonOffset,
                                child: _buildTimeRangeMobileButton(
                                    ref, buttonSize),
                              ),
                            if (isMobile)
                              Positioned(
                                top: buttonOffset,
                                left: buttonOffset,
                                child: _buildCreditsFeedToggleButton(
                                    ref, buttonSize),
                              ),
                            // Legend positioned at container edge with widget spacing
                            Positioned(
                              left: 4,
                              bottom: 4,
                              child: _buildCypherbladeInfoLegend(
                                  statusAsync, latestSnapshot, size),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              // MODULE: Network gaps chart - fill remaining viewport
              SizedBox(
                height: math.max(
                    200.0,
                    constraints.maxHeight -
                        (cyberbladeSize * 0.85) -
                        8), // Ensure minimum height
                child: NetworkGapsChart(compactMode: true),
              ),

              const SizedBox(height: 4),

              // MODULE: Rank chart
              SizedBox(
                height: 350,
                child: RankChart(compactMode: true),
              ),

              const SizedBox(height: 4),

              // MODULE: System monitoring panel (expanded)
              DegradationStatusPanel(
                events: latestSnapshot?.events,
                currentCreditsGap: latestSnapshot?.gapToRank1,
                creditsLost: creditsLost,
                gapAtDetection: gapAtDetection,
              ),

              const SizedBox(height: 4),

              // MODULE: Credits loss monitoring panel (expanded)
              CreditsMonitoringPanelV2(
                events: latestSnapshot?.events,
                currentCreditsGap: latestSnapshot?.gapToRank1,
                snapshot: latestSnapshot,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCircularBlade(
      AsyncValue statusAsync, List<ValidatorSnapshot> snapshotBuffer) {
    return statusAsync.when(
      data: (status) {
        // Cypherblade displays ONLY rank number in center
        // Alert states are shown via colored event markers on outer rings
        // No redundant status badges in center

        return CircularBladeWidget(
          snapshots: snapshotBuffer,
          rank: snapshotBuffer.isNotEmpty
              ? snapshotBuffer.last.rank.toString()
              : status.rank.toString(),
          alertStatus: null, // Removed - alerts shown on marker rings only
          alertColor: null,
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (err, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A1A1A),
                border: Border.all(
                  color: const Color(0xFFFF6B6B),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: Color(0xFFFF6B6B),
                size: 56,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Backend Unavailable',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Retrying connection...',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            const SpinKitThreeBounce(
              color: Color(0xFF00AAFF),
              size: 24.0,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactEpochProgress(WidgetRef ref, bool isHealthy) {
    final snapshots = ref.watch(snapshotBufferProvider);
    final latestSnapshot = snapshots.isNotEmpty ? snapshots.last : null;

    if (latestSnapshot == null) {
      return const SizedBox(height: 4);
    }

    final percent = latestSnapshot.progressPercent;
    final color = isHealthy ? const Color(0xFF4CAF50) : const Color(0xFFFF6B6B);

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (percent / 100).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color,
                        color.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${percent.toStringAsFixed(1)}%',
          style: const TextStyle(
            color: Color(0xFFAAAAAA),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          latestSnapshot.estimatedTimeRemaining,
          style: const TextStyle(
            color: Color(0xFF666666),
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactModeButton(WidgetRef ref, double size) {
    final compactMode = ref.watch(compactModeProvider);
    final iconSize = (size * 0.55).clamp(16.0, 24.0);
    final borderRadius = (size * 0.12).clamp(3.0, 6.0);

    return Tooltip(
      message: compactMode ? 'Disable compact mode' : 'Enable compact mode',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color:
                compactMode ? const Color(0xFF4CAF50) : const Color(0xFF404040),
            width: 1.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              final notifier = ref.read(compactModeProvider.notifier);
              notifier.toggle();

              if (!compactMode) {
                // Entering compact mode - break KDE tiling with position offset

                // Exit fullscreen if active
                final isFullScreen = await windowManager.isFullScreen();
                if (isFullScreen) {
                  await windowManager.setFullScreen(false);
                }

                // Unmaximize if maximized
                final isMaximized = await windowManager.isMaximized();
                if (isMaximized) {
                  await windowManager.unmaximize();
                }

                // Move window by small offset to break KDE tiling constraints
                final position = await windowManager.getPosition();
                await windowManager
                    .setPosition(Offset(position.dx + 10, position.dy + 10));

                // Small delay for window manager to process
                await Future.delayed(const Duration(milliseconds: 50));

                // Window height: AppBar(68) + padding(4) + blade(412) + gap(4) + chart(350) + bottom(12)
                const compactHeight = 68.0 + 4.0 + 412.0 + 4.0 + 350.0 + 3.0;
                await windowManager.setSize(const Size(420, compactHeight));

                // Enable always on top
                await windowManager.setAlwaysOnTop(true);
                ref.read(_alwaysOnTopProvider.notifier).state = true;
              } else {
                // Exiting compact mode - restore window size and disable always on top
                await windowManager.setSize(const Size(1400, 900));
                await windowManager.setAlwaysOnTop(false);
                ref.read(_alwaysOnTopProvider.notifier).state = false;
              }
            },
            borderRadius: BorderRadius.circular(borderRadius),
            child: Center(
              child: Icon(
                compactMode ? Icons.open_in_full : Icons.picture_in_picture_alt,
                size: iconSize,
                color: compactMode
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFAAAAAA),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackendIssueOverlay(String message) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
        child: Container(
          color: AppTheme.backgroundDarkest.withValues(alpha: 0.75),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 24,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 64,
                    color: const Color(0xFFFF9800).withValues(alpha: 0.8),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF9800),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Mobile-only: Time range selector button positioned on cypherblade
  Widget _buildTimeRangeMobileButton(WidgetRef ref, double size) {
    final iconSize = (size * 0.5).clamp(14.0, 20.0);
    final borderRadius = (size * 0.12).clamp(3.0, 6.0);

    return Tooltip(
      message: 'Select time range',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: const Color(0xFF00AAFF),
            width: 1.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _showTimeRangeMenu(context, ref);
            },
            borderRadius: BorderRadius.circular(borderRadius),
            child: Center(
              child: Icon(
                Icons.schedule,
                size: iconSize,
                color: const Color(0xFF00AAFF),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showTimeRangeMenu(BuildContext context, WidgetRef ref) {
    final selectedRange = ref.watch(selectedTimeRangeProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Select Time Range',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ChartTimeRange.values.map((range) {
            final isSelected = range == selectedRange;
            return ListTile(
              dense: true,
              title: Text(
                range.label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF00AAFF) : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check, color: Color(0xFF00AAFF))
                  : null,
              onTap: () {
                ref.read(selectedTimeRangeProvider.notifier).state = range;
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  // Info legend positioned on cypherblade bottom left
  Widget _buildCypherbladeInfoLegend(AsyncValue statusAsync,
      ValidatorSnapshot? snapshot, double cypherbladeSize) {
    // Scale legend size based on cypherblade size
    final padding = (cypherbladeSize * 0.012).clamp(4.0, 8.0);
    final borderRadius = (cypherbladeSize * 0.006).clamp(2.0, 4.0);
    final fontSize = (cypherbladeSize * 0.018).clamp(8.0, 10.0);
    final labelFontSize = (cypherbladeSize * 0.016).clamp(7.0, 9.0);
    final spacing = (cypherbladeSize * 0.006).clamp(3.0, 5.0);

    return statusAsync.when(
      data: (status) => Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: const Color(0xFF404040), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLegendRow('EPOCH', status.epoch.toString(),
                const Color(0xFF00AAFF), labelFontSize, fontSize, spacing),
            SizedBox(height: spacing * 0.6),
            if (snapshot != null)
              _buildLegendRow(
                  'SLOT',
                  '${snapshot.slotTimeMs.toStringAsFixed(0)}ms',
                  const Color(0xFFAAAAAA),
                  labelFontSize,
                  fontSize,
                  spacing),
            if (snapshot != null) SizedBox(height: spacing * 0.6),
            _buildLegendRow('ACTIVE', status.activeValidators.toString(),
                const Color(0xFF4CAF50), labelFontSize, fontSize, spacing),
            SizedBox(height: spacing * 0.6),
            _buildLegendRow('DELINQ', status.delinquentValidators.toString(),
                const Color(0xFFFF6B6B), labelFontSize, fontSize, spacing),
          ],
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }

  Widget _buildLegendRow(String label, String value, Color valueColor,
      double labelFontSize, double valueFontSize, double spacing) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF888888),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(width: spacing),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: valueFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // Mobile-only: Credits feed toggle button positioned on cypherblade left side
  Widget _buildCreditsFeedToggleButton(WidgetRef ref, double size) {
    final isVisible = ref.watch(creditsFeedVisibilityProvider);
    final iconSize = (size * 0.5).clamp(14.0, 20.0);
    final borderRadius = (size * 0.12).clamp(3.0, 6.0);

    return Tooltip(
      message: isVisible ? 'Hide credits feed' : 'Show credits feed',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color:
                isVisible ? const Color(0xFF4CAF50) : const Color(0xFF404040),
            width: 1.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              ref.read(creditsFeedVisibilityProvider.notifier).state =
                  !ref.read(creditsFeedVisibilityProvider);
            },
            borderRadius: BorderRadius.circular(borderRadius),
            child: Center(
              child: Icon(
                isVisible ? Icons.visibility : Icons.visibility_off,
                size: iconSize,
                color: isVisible
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF888888),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
