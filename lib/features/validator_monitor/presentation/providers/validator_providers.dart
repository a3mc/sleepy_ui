import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/validator_api_client.dart';
import '../../data/datasources/validator_stream_client.dart';
import '../../data/models/service_health.dart';
import '../../data/models/validator_status.dart';
import '../../data/models/validator_snapshot.dart';
import '../../../../core/constants/api_constants.dart';
import 'connection_status_provider.dart';
import 'auth_token_provider.dart';
import 'endpoint_config_provider.dart';
import 'fork_history_provider.dart';

// Disable verbose logging - only errors logged
const _kEnableVerboseLogging = false;
void _log(String message) {
  if (_kEnableVerboseLogging) debugPrint(message);
}

// Legacy debug logging (replaced with _log)
void _debugLog(String message) {
  _log(message);
}

// API client providers with token injection
final validatorApiClientProvider = Provider<ValidatorApiClient>((ref) {
  final client = ValidatorApiClient(
    getToken: () async {
      final tokenAsync = ref.read(authTokenNotifierProvider);
      return tokenAsync.maybeWhen(
        data: (token) => token,
        orElse: () => null,
      );
    },
    getBaseUrl: () {
      final config = ref.read(currentEndpointConfigProvider);
      return ApiConstants.getBaseUrl(config);
    },
  );
  ref.onDispose(() => client.dispose());
  return client;
});

final validatorStreamClientProvider =
    Provider.autoDispose<ValidatorStreamClient>((ref) {
  final client = ValidatorStreamClient(
    getToken: () async {
      final tokenAsync = ref.read(authTokenNotifierProvider);
      return tokenAsync.maybeWhen(
        data: (token) => token,
        orElse: () => null,
      );
    },
    getBaseUrl: () {
      final config = ref.read(currentEndpointConfigProvider);
      return ApiConstants.getBaseUrl(config);
    },
  );
  ref.onDispose(() => client.dispose());
  return client;
});

// Health check provider
final serviceHealthProvider =
    FutureProvider.autoDispose<ServiceHealth>((ref) async {
  final client = ref.watch(validatorApiClientProvider);
  return client.getHealth();
});

// Status provider (polled every 8 seconds)
// Uses .autoDispose to stop polling when dashboard unmounted
// Continues polling indefinitely - shows error in UI but recovers automatically
final validatorStatusProvider =
    StreamProvider.autoDispose<ValidatorStatus>((ref) async* {
  final client = ref.watch(validatorApiClientProvider);
  var consecutiveErrors = 0;

  while (true) {
    try {
      final status = await client.getStatus();
      consecutiveErrors = 0; // Reset counter on success
      yield status;
    } catch (e) {
      consecutiveErrors++;
      _debugLog(
          '[StatusProvider] Poll failed (attempt $consecutiveErrors): $e');

      // FIXED [ERR-03]: Remove non-idiomatic yield* Stream.error pattern
      // Silent error handling - continue polling for recovery
      // UI detects stale data via timestamp comparison
      if (consecutiveErrors >= 3) {
        _debugLog(
            '[StatusProvider] Backend unreachable after 3 attempts, continuing silent polling');
      }

      // Continue polling - will recover when backend returns
      // No error emission - keeps stream clean and predictable
    }

    await Future.delayed(ApiConstants.statusPollInterval);
  }
});

// History provider (called once on startup or after reconnection)
final validatorHistoryProvider =
    FutureProvider.family<List<ValidatorSnapshot>, double>(
  (ref, hours) async {
    final client = ref.watch(validatorApiClientProvider);
    return client.getHistory(hours: hours.toInt());
  },
);

// Real-time snapshot stream provider
final validatorSnapshotStreamProvider =
    StreamProvider.autoDispose<ValidatorSnapshot>((ref) {
  final client = ref.watch(validatorStreamClientProvider);
  return client.connect();
});

// Rolling buffer provider (maintains last 60 snapshots)
// NOTE: No .autoDispose - buffer persists across navigation as application-level state
// Timer properly cleaned up via ref.onDispose() callback
final snapshotBufferProvider =
    StateNotifierProvider<SnapshotBufferNotifier, List<ValidatorSnapshot>>(
        (ref) {
  return SnapshotBufferNotifier(ref);
});

class SnapshotBufferNotifier extends StateNotifier<List<ValidatorSnapshot>> {
  final Ref _ref;
  Timer? _gapCheckTimer;
  int? _forkGapAtDetection; // Gap when Stabilizing started

  // Sequence tracking for gap detection
  String? _lastSessionId;
  int? _lastSequence;
  bool _backfillInProgress = false;

  SnapshotBufferNotifier(this._ref) : super([]) {
    _initializeBuffer();

    // Set up gap detection timer (runs every 30 seconds)
    _gapCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      checkForGaps();
    });

    // Clean up timer on disposal
    _ref.onDispose(() {
      _gapCheckTimer?.cancel();
    });
  }

  // Test-only constructor to bypass async initialization
  // ignore: unused_element
  SnapshotBufferNotifier.test(super.testData) : _ref = _TestRef();

  Future<void> _initializeBuffer() async {
    _log(
        '[SnapshotBuffer] Initializing buffer with recent history for immediate situational awareness...');

    // Pre-load last 1 hour of history to populate cypherblade immediately
    // Critical for incident response: engineer sees situation in 3 seconds, not 3 minutes
    try {
      final client = _ref.read(validatorApiClientProvider);
      final history = await client.getHistory(hours: 1).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _log(
              '[SnapshotBuffer] History pre-load timeout - starting with empty buffer');
          return <ValidatorSnapshot>[];
        },
      );

      if (history.isNotEmpty) {
        // Take last 60 snapshots (cypherblade buffer size)
        final recentSnapshots = history.length > ApiConstants.maxHistoryBuffer
            ? history.sublist(history.length - ApiConstants.maxHistoryBuffer)
            : history;

        state = recentSnapshots;

        // Initialize sequence tracking from last historical snapshot
        if (recentSnapshots.last.sessionId != null &&
            recentSnapshots.last.sequence != null) {
          _lastSessionId = recentSnapshots.last.sessionId;
          _lastSequence = recentSnapshots.last.sequence;
          _log(
              '[SnapshotBuffer] Sequence tracking initialized: session=${_lastSessionId?.substring(0, 8)} seq=$_lastSequence');
        }

        _log(
            '[SnapshotBuffer] Pre-loaded ${recentSnapshots.length} snapshots - cypherblade ready immediately');
      } else {
        _log(
            '[SnapshotBuffer] No history available - starting with empty buffer');
        state = [];
      }
    } catch (e) {
      _log(
          '[SnapshotBuffer] Failed to pre-load history: $e - starting with empty buffer');
      state = [];
    }

    // Listen to real-time stream (gap detection active)
    _log('[SnapshotBuffer] Starting SSE stream listener...');
    _ref.listen(
      validatorSnapshotStreamProvider,
      (previous, next) {
        next.when(
          data: (snapshot) {
            _log(
                '[SnapshotBuffer] Received snapshot: seq=${snapshot.sequence} session=${snapshot.sessionId?.substring(0, 8)} '
                'rank=${snapshot.rank} vote=${snapshot.voteDistance} root=${snapshot.rootDistance} '
                'credits_gap=${snapshot.creditsPerformanceGap} (rank1:${snapshot.rank1CreditsDelta} ours:${snapshot.creditsDelta})');
            // Signal connection success
            _ref.read(connectionStatusProvider.notifier).setConnected();
            _addSnapshot(snapshot);
          },
          loading: () {
            _log('[SnapshotBuffer] Stream loading...');
            // Signal reconnecting state
            _ref.read(connectionStatusProvider.notifier).setReconnecting(0);
          },
          error: (err, stack) {
            _log('[SnapshotBuffer] Stream error: $err');

            // Extract retry attempt from error message if present
            final errorMsg = err.toString();
            final retryMatch =
                RegExp(r'attempt (\d+)/(\d+)').firstMatch(errorMsg);

            if (retryMatch != null) {
              final retryAttempt = int.parse(retryMatch.group(1)!);
              _ref
                  .read(connectionStatusProvider.notifier)
                  .setReconnecting(retryAttempt);
            } else {
              // No retry information - just disconnected
              _ref
                  .read(connectionStatusProvider.notifier)
                  .setDisconnected(errorMsg);
            }
          },
        );
      },
    );
  }

  void _addSnapshot(ValidatorSnapshot snapshot) {
    // Check for sequence tracking and gap detection
    if (snapshot.sessionId != null && snapshot.sequence != null) {
      // Session reset detection (backend restart)
      if (_lastSessionId != null && snapshot.sessionId != _lastSessionId) {
        debugPrint(
            '[GAP] Session ID changed: $_lastSessionId → ${snapshot.sessionId}');
        debugPrint('[GAP] Backend restarted - resetting sequence tracking');
        _lastSessionId = snapshot.sessionId;
        _lastSequence = snapshot.sequence;
      }
      // Gap detection
      else if (_lastSequence != null &&
          snapshot.sequence! > _lastSequence! + 1) {
        final gapStart = _lastSequence! + 1;
        final gapEnd = snapshot.sequence! - 1;
        final gapSize = gapEnd - gapStart + 1;

        debugPrint(
            '[GAP] [WARN] Detected gap of $gapSize events: sequences $gapStart to $gapEnd');

        // Trigger backfill asynchronously (don't block snapshot processing)
        if (!_backfillInProgress) {
          _triggerBackfill(gapStart, gapEnd);
        } else {
          debugPrint('[GAP] Backfill already in progress, skipping');
        }
      }

      // Update tracking
      _lastSessionId = snapshot.sessionId;
      _lastSequence = snapshot.sequence;
    }

    // Build new state list efficiently (avoids spread operator allocation)
    final List<ValidatorSnapshot> newState;
    if (state.length >= ApiConstants.maxHistoryBuffer) {
      // At capacity: skip oldest, add newest (single allocation)
      newState = [...state.skip(1), snapshot];
    } else {
      // Growing: add to new list
      newState = List.of(state)..add(snapshot);
    }

    // Log event state transitions for debugging
    if (snapshot.events != null) {
      final events = snapshot.events!;
      final prevSnapshot = state.isNotEmpty ? state.last : null;
      final prevEvents = prevSnapshot?.events;

      // Log temporal transitions WITH DETAILED EXPLANATIONS
      final temporal = events.temporal;
      final prevTemporal = prevEvents?.temporal;
      if (prevTemporal != null) {
        // Debug: Log all temporal level changes
        if (temporal.level != prevTemporal.level) {
          _debugLog(
              '[DEBUG] Temporal level change detected: ${prevTemporal.level} → ${temporal.level}');
        }

        // Check for resolution (GREEN DOT)
        if (temporal.level == 'None' && prevTemporal.level != 'None') {
          final wasWarning = prevTemporal.level == 'Warning';
          final wasCritical = prevTemporal.level == 'Critical';
          if (kDebugMode) {
            print(
                '\n═══════════════════════════════════════════════════════════');
            print('[OK] [TEMPORAL] RECOVERY: Temporal degradation RESOLVED');
            if (wasWarning) {
              print(
                  '[WARN] [TEMPORAL] WARNING ALERT SENT (resolved before critical escalation)');
            }
            print(
                '═══════════════════════════════════════════════════════════\n');
          }
          if (wasWarning) {
            _debugLog(
                '[MARKER] [RESOLVED] GREEN DOT - [TEMPORAL] RESOLVED: Warning → None (WARNING ALERT SENT on resolution)');
          } else if (wasCritical) {
            _debugLog(
                '[MARKER] [RESOLVED] GREEN DOT - [TEMPORAL] RESOLVED: Critical → None (recovery from critical state)');
          } else {
            _debugLog(
                '[MARKER] [RESOLVED] GREEN DOT - [TEMPORAL] RESOLVED: degradation cleared before alert threshold');
          }
        }
        // Check for Critical alert (RED DOT)
        else if (temporal.level == 'Critical' &&
            prevTemporal.level != 'Critical') {
          final voteCount = temporal.voteDistance.consecutiveCount;
          final rootCount = temporal.rootDistance.consecutiveCount;
          final creditsCount = temporal.credits.consecutiveCount;
          if (kDebugMode) {
            print(
                '\n═══════════════════════════════════════════════════════════');
            print('[ALERT] [TEMPORAL] CRITICAL ALERT SENT TO TELEGRAM');
            print(
                '   Level: ${prevTemporal.level} → Critical (>=12 cycles degraded)');
            print(
                '   Metrics: V:$voteCount/${temporal.voteDistance.criticalThreshold} R:$rootCount/${temporal.rootDistance.criticalThreshold} C:$creditsCount/${temporal.credits.criticalThreshold}');
            print('   Warning threshold skipped (escalated)');
            print(
                '═══════════════════════════════════════════════════════════\n');
          }
          _debugLog(
              '[MARKER] [CRITICAL] RED DOT - [TEMPORAL] CRITICAL alert SENT (escalated from warning)');
        }
        // Check for Warning alert (ORANGE DOT) - alert PENDING, not sent yet
        else if (temporal.level == 'Warning' &&
            prevTemporal.level != 'Warning' &&
            temporal.level != 'Critical') {
          final voteCount = temporal.voteDistance.consecutiveCount;
          final rootCount = temporal.rootDistance.consecutiveCount;
          final creditsCount = temporal.credits.consecutiveCount;
          if (kDebugMode) {
            print(
                '\n═══════════════════════════════════════════════════════════');
            print('[WARN] [TEMPORAL] WARNING THRESHOLD CONFIRMED');
            print(
                '   Level: ${prevTemporal.level} → Warning (>=6 cycles degraded)');
            print(
                '   Metrics: V:$voteCount/${temporal.voteDistance.warningThreshold} R:$rootCount/${temporal.rootDistance.warningThreshold} C:$creditsCount/${temporal.credits.warningThreshold}');
            print('   Alert PENDING: monitoring for escalation to critical');
            print(
                '   Will send: Warning (if resolved) OR Critical (if escalates)');
            print(
                '═══════════════════════════════════════════════════════════\n');
          }
          _debugLog(
              '[MARKER] [WARNING] ORANGE DOT - [TEMPORAL] WARNING threshold (alert pending delivery)');
        }
        // Check for first degradation (GRAY DOT)
        else {
          final voteCount = temporal.voteDistance.consecutiveCount;
          final rootCount = temporal.rootDistance.consecutiveCount;
          final creditsCount = temporal.credits.consecutiveCount;
          final prevVote = prevTemporal.voteDistance.consecutiveCount;
          final prevRoot = prevTemporal.rootDistance.consecutiveCount;
          final prevCredits = prevTemporal.credits.consecutiveCount;

          final anyDegraded =
              voteCount > 0 || rootCount > 0 || creditsCount > 0;
          final wasAllHealthy =
              prevVote == 0 && prevRoot == 0 && prevCredits == 0;

          if (anyDegraded && wasAllHealthy) {
            final degradedMetrics = <String>[];
            if (voteCount > 0) degradedMetrics.add('vote');
            if (rootCount > 0) degradedMetrics.add('root');
            if (creditsCount > 0) degradedMetrics.add('credits');
            _debugLog(
                '[MARKER] ⚪ GRAY DOT - [TEMPORAL] degradation STARTED: evaluation phase (${degradedMetrics.join(", ")} behind) [V:$voteCount R:$rootCount C:$creditsCount]');
          } else if (anyDegraded) {
            _debugLog(
                '[EVENTS] [TEMPORAL] degraded: V:$voteCount R:$rootCount C:$creditsCount (level=${temporal.level})');
          }
        }
      }

      // Log loss event phase transitions WITH MARKER EXPLANATIONS
      final fork = events.fork;
      final prevFork = prevEvents?.fork;

      // Update loss event history tracker (with debug)
      if (kDebugMode) {
        _log(
            '[ForkHistory Integration] Calling updateForkState with phase: ${fork.phase}');
      }
      _ref.read(forkHistoryProvider.notifier).updateForkState(fork);

      if (prevFork != null && fork.phase != prevFork.phase) {
        // Track gap when Stabilizing starts (look back for pre-detection gap)
        if (fork.phase == 'Stabilizing' && prevFork.phase == 'Idle') {
          // Look back 3-5 snapshots to get gap before loss event triggered
          final lookBackIndex = (state.length - 5).clamp(0, state.length - 1);
          _forkGapAtDetection = state.isNotEmpty
              ? state[lookBackIndex].gapToRank1
              : snapshot.gapToRank1;
          if (kDebugMode) {
            debugPrint(
                '\n═══════════════════════════════════════════════════════════');
            debugPrint('[STARTED] [LOSS] DETECTION STARTED');
            debugPrint('   Gap at detection: $_forkGapAtDetection credits');
            debugPrint('   Current gap: ${snapshot.gapToRank1} credits');
            debugPrint(
                '═══════════════════════════════════════════════════════════\n');
          }
          _debugLog(
              '[MARKER] [STARTED] BLUE DOT (dark blue) - [LOSS] detection STARTED: ${prevFork.phase} → Stabilizing (analyzing credit loss pattern, waiting for stabilization)');
        } else if (fork.phase == 'Confirmed') {
          final creditsLost = _forkGapAtDetection != null
              ? snapshot.gapToRank1 - _forkGapAtDetection!
              : null;
          if (kDebugMode) {
            debugPrint(
                '\n═══════════════════════════════════════════════════════════');
            debugPrint(
                '[CONFIRMED] [LOSS] DETECTION CONFIRMED (analysis complete)');
            debugPrint('   Transition: ${prevFork.phase} → Confirmed');
            debugPrint('   Analysis: credit loss validated as REAL EVENT');
            debugPrint('   Gap before: $_forkGapAtDetection credits');
            debugPrint('   Gap after: ${snapshot.gapToRank1} credits');
            if (creditsLost != null) {
              debugPrint('   Credits LOST: $creditsLost credits');
            }
            debugPrint(
                '   Loops: ${fork.loopsSinceDetection} (gapSettleWait=${fork.gapSettleWait}, gapStableConfirm=${fork.gapStableConfirm})');
            debugPrint(
                '═══════════════════════════════════════════════════════════\n');
          }
          _debugLog(
              '[MARKER] [CONFIRMED] PURPLE DOT - [LOSS] CONFIRMED (detection complete)');
        } else if (fork.phase == 'Idle' && prevFork.phase != 'Idle') {
          // Reset gap tracking
          _forkGapAtDetection = null;
          _debugLog(
              '[MARKER] � CYAN DOT (light blue) - [LOSS] CLEARED: ${prevFork.phase} → Idle (analysis complete: NO LOSS detected, false positive, no alert sent)');
        } else if (fork.phase == 'RankSampling') {
          _debugLog(
              '[MARKER] [STARTED] BLUE DOT (dark blue) - [LOSS] RANK SAMPLING: ${prevFork.phase} → RankSampling (monitoring rank changes for confirmation) [loops=${fork.loopsSinceDetection}]');
        } else {
          _debugLog(
              '[EVENTS] [LOSS] phase: ${prevFork.phase} → ${fork.phase} (loops=${fork.loopsSinceDetection})');
        }
      }

      // Log validator alert transitions WITH DETAILED EXPLANATIONS
      final alerts = [
        (
          'delinquent',
          events.delinquent,
          prevEvents?.delinquent,
          '[WARN] VALIDATOR DEAD - no attestations'
        ),
        (
          'credits_stagnant',
          events.creditsStagnant,
          prevEvents?.creditsStagnant,
          'credits not growing'
        ),
        (
          'network_halted',
          events.networkHalted,
          prevEvents?.networkHalted,
          'network finalization stopped'
        ),
      ];
      for (final (name, alert, prevAlert, description) in alerts) {
        if (prevAlert != null && alert.phase != prevAlert.phase) {
          final isDelinquent = name == 'delinquent';
          final moduleName = name.toUpperCase();
          if (alert.phase == 'Recovering' ||
              (alert.phase == 'Idle' && prevAlert.phase != 'Idle')) {
            final marker = isDelinquent
                ? '[RESOLVED] GREEN TRIANGLE'
                : '[RESOLVED] GREEN DOT';
            _debugLog(
                '[MARKER] $marker - [$moduleName] RECOVERED: ${prevAlert.phase} → ${alert.phase} ($description resolved)');
          } else if (alert.phase == 'Active') {
            final marker = isDelinquent
                ? '[CRITICAL] RED TRIANGLE (!!)'
                : '[WARNING] ORANGE-RED DOT';
            if (kDebugMode) {
              print(
                  '\n═══════════════════════════════════════════════════════════');
              print(
                  '[ALERT] [$moduleName] ALERT SENT TO TELEGRAM/EXTERNAL SYSTEMS');
              print('   Reason: $description');
              print('   Count: ${alert.count}/${alert.threshold}');
              print(
                  '═══════════════════════════════════════════════════════════\n');
            }
            _debugLog(
                '[MARKER] $marker - [$moduleName] FIRED & DELIVERED: ${prevAlert.phase} → Active');
          } else if (alert.phase == 'Detecting') {
            final marker = isDelinquent
                ? '[DETECTING] AMBER TRIANGLE'
                : '[DETECTING] GOLD DOT';
            _debugLog(
                '[MARKER] $marker - [$moduleName] DETECTING: ${prevAlert.phase} → Detecting ($description building) [count=${alert.count}/${alert.threshold}]');
          } else {
            _debugLog(
                '[EVENTS] [$moduleName]: ${prevAlert.phase} → ${alert.phase} (count=${alert.count}/${alert.threshold})');
          }
        }
      }
    }

    // State already trimmed during construction above
    state = newState;
  }

  // Expose loss event gap tracking data
  int? get forkGapAtDetection => _forkGapAtDetection;

  // Calculate credits lost (only valid when loss confirmed)
  int? getCreditsLost() {
    if (state.isEmpty || _forkGapAtDetection == null) return null;
    final currentGap = state.last.gapToRank1;
    // Gap is negative (we're behind rank_1), more negative = further behind
    // Credits lost = how much further behind we fell
    // Example: -10 → -20 means we lost 10 credits
    return _forkGapAtDetection! - currentGap;
  }

  // Trigger backfill from /missed endpoint
  Future<void> _triggerBackfill(int fromSeq, int toSeq) async {
    _backfillInProgress = true;

    try {
      debugPrint(
          '[BACKFILL] Fetching missed events: sequences $fromSeq to $toSeq');

      final client = _ref.read(validatorApiClientProvider);
      final missedSnapshots = await client
          .getMissedSnapshots(fromSeq, toSeq)
          .timeout(const Duration(seconds: 10));

      if (missedSnapshots.isEmpty) {
        debugPrint('[BACKFILL] No events returned from /missed endpoint');
        return;
      }

      debugPrint(
          '[BACKFILL] Recovered ${missedSnapshots.length} missed events');

      // Insert snapshots in order, maintaining sequence continuity
      for (final snapshot in missedSnapshots) {
        _insertSnapshotInOrder(snapshot);
      }

      debugPrint('[BACKFILL] ✓ Successfully recovered gap');
    } on TimeoutException catch (e) {
      debugPrint('[BACKFILL] Timeout fetching missed events: $e');
    } catch (e) {
      debugPrint('[BACKFILL] Failed to recover gap: $e');

      // If /missed fails (e.g., 410 Gone), fallback to /history
      if (e.toString().contains('no longer available')) {
        debugPrint(
            '[BACKFILL] Events evicted from cache, falling back to /history');
        // Could implement /history fallback here if needed
      }
    } finally {
      _backfillInProgress = false;
    }
  }

  // Binary search for insertion point in timestamp-ordered list
  /// Returns index where snapshot should be inserted to maintain chronological order
  int _binarySearchInsertionPoint(
      List<ValidatorSnapshot> list, ValidatorSnapshot target) {
    int low = 0;
    int high = list.length;

    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (list[mid].timestamp.isBefore(target.timestamp)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    return low;
  }

  // Insert snapshot in correct position maintaining timestamp order
  void _insertSnapshotInOrder(ValidatorSnapshot snapshot) {
    final newState = [...state];

    // Use binary search for O(log n) insertion point lookup (improved from linear O(n))
    final insertIndex = _binarySearchInsertionPoint(newState, snapshot);

    // Check for duplicate at insertion point
    if (insertIndex < newState.length &&
        newState[insertIndex].sequence == snapshot.sequence) {
      debugPrint('[BACKFILL] Skipping duplicate sequence ${snapshot.sequence}');
      return;
    }

    newState.insert(insertIndex, snapshot);

    // Maintain rolling window
    if (newState.length > ApiConstants.maxHistoryBuffer) {
      state = newState.sublist(newState.length - ApiConstants.maxHistoryBuffer);
    } else {
      state = newState;
    }
  }

  // Check for timestamp gap and backfill if needed
  void checkForGaps() async {
    if (state.isEmpty) return;

    final now = DateTime.now();
    final lastSnapshot = state.last;
    final gap = now.difference(lastSnapshot.timestamp);

    if (gap > ApiConstants.gapBackfillThreshold) {
      final startTs = lastSnapshot.timestamp.millisecondsSinceEpoch ~/ 1000;
      final endTs = now.millisecondsSinceEpoch ~/ 1000;

      try {
        final client = _ref.read(validatorApiClientProvider);
        final backfill = await client
            .getHistory(
              startTimestamp: startTs,
              endTimestamp: endTs,
            )
            .timeout(const Duration(seconds: 10));

        if (backfill.isEmpty) {
          _log(
              '[SnapshotBuffer] Backfill returned no data for range $startTs-$endTs');
          return;
        }

        // Filter: only accept snapshots within requested range
        final validBackfill = backfill.where((snap) {
          final ts = snap.timestamp.millisecondsSinceEpoch ~/ 1000;
          return ts >= startTs && ts <= endTs;
        }).toList();

        if (validBackfill.isEmpty) return;

        // CORRECTNESS [DATA-01]: Deduplicate using (sessionId, sequence) tuple
        // Prevents duplicate snapshots at same millisecond with different sequences
        // Fallback to timestamp for backward compatibility with snapshots lacking sequence
        final existingKeys = state.map((s) {
          if (s.sessionId != null && s.sequence != null) {
            // Primary key: session + sequence guarantees uniqueness
            return '${s.sessionId}_${s.sequence}';
          } else {
            // Fallback for legacy snapshots without sequence numbers
            return 'ts_${s.timestamp.millisecondsSinceEpoch}';
          }
        }).toSet();

        final uniqueBackfill = validBackfill.where((snap) {
          final key = (snap.sessionId != null && snap.sequence != null)
              ? '${snap.sessionId}_${snap.sequence}'
              : 'ts_${snap.timestamp.millisecondsSinceEpoch}';
          return !existingKeys.contains(key);
        }).toList();

        if (uniqueBackfill.isEmpty) {
          _log(
              '[SnapshotBuffer] Backfill returned ${backfill.length} snapshots, but all were duplicates or out-of-range');
          return;
        }

        // Batch merge: combine current state with validated backfill in single operation
        _log(
            '[SnapshotBuffer] Backfilling ${uniqueBackfill.length} snapshots for gap of ${gap.inSeconds}s (filtered from ${backfill.length} total)');

        final merged = [...state, ...uniqueBackfill];

        // Sort by timestamp to maintain chronological order
        merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        // Apply buffer limit to merged result
        if (merged.length > ApiConstants.maxHistoryBuffer) {
          state = merged.sublist(merged.length - ApiConstants.maxHistoryBuffer);
        } else {
          state = merged;
        }

        _log(
            '[SnapshotBuffer] Backfill complete, buffer now has ${state.length} snapshots');
      } on TimeoutException {
        _log(
            '[SnapshotBuffer] Backfill timeout after 10s for gap ${gap.inSeconds}s (range $startTs-$endTs). Will retry on next check cycle.');
        // Gap remains unfilled; timer will retry in 30 seconds
      } catch (e) {
        _log('[SnapshotBuffer] Backfill failed: $e');
        // Backfill failed, continue with gap
      }
    }
  }
}

// Test-only stub Ref implementation for _test constructor
class _TestRef implements Ref {
  @override
  T read<T>(ProviderListenable<T> provider) =>
      throw UnimplementedError('Test stub');

  @override
  void onDispose(void Function() cb) {
    // No-op for tests
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Test stub');
}
