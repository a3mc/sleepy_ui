import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/validator_snapshot.dart';
import 'validator_providers.dart';
import 'connection_status_provider.dart';

/// Wrapper for historical data
/// Keeps history fetch separate from filtering logic to prevent re-fetch on every SSE update
class _HistoricalDataWithTimestamp {
  final List<ValidatorSnapshot> snapshots;
  final DateTime
      referenceTime; // When history was fetched (for debugging/logging)

  const _HistoricalDataWithTimestamp({
    required this.snapshots,
    required this.referenceTime,
  });
}

/// Time range options for historical chart data
enum ChartTimeRange {
  cypherblade, // Live 60-snapshot buffer (default)
  min5, // 5 minutes
  min15, // 15 minutes
  min30, // 30 minutes
  hour1, // 1 hour
  hour3, // 3 hours
  hour6, // 6 hours
  hour12, // 12 hours
  hour24, // 24 hours
  epoch, // Full epoch (~50 hours, max RocksDB history)
}

extension ChartTimeRangeExt on ChartTimeRange {
  String get label {
    switch (this) {
      case ChartTimeRange.cypherblade:
        return 'BLADE';
      case ChartTimeRange.min5:
        return '5M';
      case ChartTimeRange.min15:
        return '15M';
      case ChartTimeRange.min30:
        return '30M';
      case ChartTimeRange.hour1:
        return '1H';
      case ChartTimeRange.hour3:
        return '3H';
      case ChartTimeRange.hour6:
        return '6H';
      case ChartTimeRange.hour12:
        return '12H';
      case ChartTimeRange.hour24:
        return '24H';
      case ChartTimeRange.epoch:
        return 'EPOCH';
    }
  }

  /// Duration in seconds for history fetch (null = use live buffer)
  int? get durationSeconds {
    switch (this) {
      case ChartTimeRange.cypherblade:
        return null; // Use live buffer
      case ChartTimeRange.min5:
        return 5 * 60;
      case ChartTimeRange.min15:
        return 15 * 60;
      case ChartTimeRange.min30:
        return 30 * 60;
      case ChartTimeRange.hour1:
        return 60 * 60;
      case ChartTimeRange.hour3:
        return 3 * 60 * 60;
      case ChartTimeRange.hour6:
        return 6 * 60 * 60;
      case ChartTimeRange.hour12:
        return 12 * 60 * 60;
      case ChartTimeRange.hour24:
        return 24 * 60 * 60;
      case ChartTimeRange.epoch:
        return 50 * 60 * 60; // Full epoch (~50h)
    }
  }
}

/// Selected time range state (shared between position charts)
final selectedTimeRangeProvider = StateProvider<ChartTimeRange>((ref) {
  return ChartTimeRange.cypherblade; // Default to live buffer
});

/// Provider that returns chart data for a specific time range
final chartDataProvider = Provider.autoDispose
    .family<AsyncValue<List<ValidatorSnapshot>>, ChartTimeRange>(
  (ref, timeRange) {
    // BLADE: Return live buffer directly (no history fetch, no server time logic)
    // This is the fast path for real-time monitoring - bypasses all clock skew concerns
    if (timeRange == ChartTimeRange.cypherblade) {
      return AsyncValue.data(ref.watch(snapshotBufferProvider));
    }

    // Historical: merge fetched history + live buffer updates
    final liveBuffer = ref.watch(snapshotBufferProvider);

    // If buffer empty, check connection status before showing indefinite loading
    if (liveBuffer.isEmpty) {
      final connectionState = ref.watch(connectionStatusProvider);

      // If connection failed/disconnected, show error immediately
      if (connectionState.status == ConnectionStatus.disconnected) {
        return AsyncValue.error(
          'Cannot load historical data: Connection failed. ${connectionState.errorMessage ?? "Check connection status in header."}',
          StackTrace.current,
        );
      }

      // Otherwise show loading (connection establishing or reconnecting)
      return AsyncValue.loading();
    }

    // Fetch historical data once (no timestamp parameter to avoid re-execution on every buffer update)
    final historicalAsync = ref.watch(_historicalDataProvider(timeRange));

    return historicalAsync.when(
      data: (historicalWithTimestamp) {
        final historical = historicalWithTimestamp.snapshots;

        // Use CURRENT buffer timestamp for ALL filtering (rolling window semantics)
        final currentTime = liveBuffer.last.timestamp;
        final windowStart =
            currentTime.subtract(Duration(seconds: timeRange.durationSeconds!));

        // Filter historical data with current window - old data naturally falls off
        final filteredHistorical =
            historical.where((s) => s.timestamp.isAfter(windowStart)).toList();

        // Get latest timestamp from filtered historical data
        final latestHistorical = filteredHistorical.isEmpty
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : filteredHistorical.last.timestamp;

        // Append new snapshots from live buffer that are within window and newer than historical
        final newSnapshots = liveBuffer
            .where((s) =>
                s.timestamp.isAfter(windowStart) &&
                s.timestamp.isAfter(latestHistorical))
            .toList();

        final combined = [...filteredHistorical, ...newSnapshots];

        return AsyncValue.data(combined);
      },
      loading: () => AsyncValue.loading(),
      error: (e, st) => AsyncValue.error(e, st),
    );
  },
);

/// Fetch historical data once with explicit server timestamp parameter
/// Accepts (ChartTimeRange, DateTime) tuple to ensure temporal consistency
/// between history fetch and time window filtering
final _historicalDataProvider = FutureProvider.autoDispose
    .family<_HistoricalDataWithTimestamp, ChartTimeRange>(
  (ref, timeRange) async {
    final client = ref.read(validatorApiClientProvider);
    final durationSeconds = timeRange.durationSeconds!;

    // Read buffer once at provider creation to get server timestamp
    // This timestamp is frozen for the lifetime of this provider instance
    final buffer = ref.read(snapshotBufferProvider);
    if (buffer.isEmpty) {
      // Return empty with cycle timestamp if no buffer data
      return _HistoricalDataWithTimestamp(
        snapshots: [],
        referenceTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }

    // Capture server timestamp at provider creation time
    final serverTimestamp = buffer.last.timestamp;
    final endTs = serverTimestamp.millisecondsSinceEpoch ~/ 1000;
    final startTs = endTs - durationSeconds;

    final history = await client
        .getHistory(
          startTimestamp: startTs,
          endTimestamp: endTs,
        )
        .timeout(const Duration(seconds: 30));

    if (history.length > 300) {
      final step = history.length ~/ 300;
      final sampled = <ValidatorSnapshot>[];
      final sampledTimestamps = <DateTime>{};

      // Sample regularly first
      for (int i = 0; i < history.length; i += step) {
        sampled.add(history[i]);
        sampledTimestamps.add(history[i].timestamp);
      }

      // Add alert snapshots that weren't in regular sampling
      for (int i = 0; i < history.length; i++) {
        final snapshot = history[i];
        if ((snapshot.events?.temporal.alertSentThisCycle == true ||
                snapshot.events?.fork.lastAlert != null) &&
            !sampledTimestamps.contains(snapshot.timestamp)) {
          sampled.add(snapshot);
        }
      }

      // Sort by timestamp
      sampled.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Return sampled data with reference timestamp
      return _HistoricalDataWithTimestamp(
        snapshots: sampled,
        referenceTime: serverTimestamp,
      );
    }

    // Return full history with reference timestamp
    return _HistoricalDataWithTimestamp(
      snapshots: history,
      referenceTime: serverTimestamp,
    );
  },
);
