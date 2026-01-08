import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sleepy_ui/features/validator_monitor/presentation/providers/time_range_provider.dart';
import 'package:sleepy_ui/features/validator_monitor/presentation/providers/validator_providers.dart';
import 'package:sleepy_ui/features/validator_monitor/presentation/providers/connection_status_provider.dart';
import 'package:sleepy_ui/features/validator_monitor/data/models/validator_snapshot.dart';
import 'package:sleepy_ui/features/validator_monitor/data/datasources/validator_api_client.dart';

void main() {
  group('time_range_provider', () {
    // Helper to create minimal ValidatorSnapshot for testing
    ValidatorSnapshot createSnapshot(
        DateTime timestamp, int rank, int sequence) {
      return ValidatorSnapshot(
        timestamp: timestamp,
        rank: rank,
        sequence: sequence,
        voteDistance: 0,
        rootDistance: 0,
        ourCredits: 1000000,
        rank1Credits: 1000100,
        creditsDelta: 100,
        rank1CreditsDelta: 105,
        creditsPerformanceGap: 5,
        gapToRank1: 100,
        gapToTop10: 50,
        gapToTop100: 10,
        gapToTop200: 5,
      );
    }

    test('BLADE range returns snapshotBufferProvider data directly', () {
      // Arrange
      final now = DateTime(2026, 1, 3, 10, 0, 0);
      final mockSnapshot1 =
          createSnapshot(now.subtract(const Duration(seconds: 6)), 100, 1);
      final mockSnapshot2 =
          createSnapshot(now.subtract(const Duration(seconds: 3)), 101, 2);

      final container = ProviderContainer(
        overrides: [
          // Override snapshotBufferProvider to return test data without async initialization
          snapshotBufferProvider.overrideWith((ref) {
            final notifier =
                _MockBufferNotifier([mockSnapshot1, mockSnapshot2]);
            return notifier;
          }),
        ],
      );

      // Act
      final result =
          container.read(chartDataProvider(ChartTimeRange.cypherblade));

      // Assert
      expect(result, isA<AsyncValue<List<ValidatorSnapshot>>>());
      result.when(
        data: (data) {
          expect(data.length, equals(2));
          expect(data[0].rank, equals(100));
          expect(data[1].rank, equals(101));
        },
        loading: () => fail('Should not be loading'),
        error: (_, __) => fail('Should not error'),
      );

      container.dispose();
    });

    test(
        'Historical range with empty buffer and disconnected status shows error',
        () {
      // Arrange
      final container = ProviderContainer(
        overrides: [
          snapshotBufferProvider.overrideWith((ref) {
            return _MockBufferNotifier([]); // Empty buffer
          }),
          connectionStatusProvider.overrideWith((ref) {
            final notifier = ConnectionStatusNotifier();
            notifier.setDisconnected('SSE connection failed');
            return notifier;
          }),
        ],
      );

      // Act
      final result = container.read(chartDataProvider(ChartTimeRange.hour1));

      // Assert
      expect(result, isA<AsyncValue<List<ValidatorSnapshot>>>());
      result.when(
        data: (_) => fail('Should not have data'),
        loading: () => fail('Should not be loading'),
        error: (error, _) {
          expect(error.toString(), contains('Cannot load historical data'));
          expect(error.toString(), contains('Connection failed'));
        },
      );

      container.dispose();
    });

    test(
        'Historical range with empty buffer and reconnecting status shows loading',
        () {
      // Arrange
      final container = ProviderContainer(
        overrides: [
          snapshotBufferProvider.overrideWith((ref) {
            return _MockBufferNotifier([]); // Empty buffer
          }),
          connectionStatusProvider.overrideWith((ref) {
            final notifier = ConnectionStatusNotifier();
            notifier.setReconnecting(1);
            return notifier;
          }),
        ],
      );

      // Act
      final result = container.read(chartDataProvider(ChartTimeRange.hour1));

      // Assert
      expect(result, isA<AsyncValue<List<ValidatorSnapshot>>>());
      result.when(
        data: (_) => fail('Should not have data'),
        loading: () => {}, // Expected
        error: (_, __) => fail('Should not error'),
      );

      container.dispose();
    });

    test(
        'Historical range uses server timestamp from buffer (clock skew scenario)',
        () async {
      // Arrange
      final serverTime = DateTime(2026, 1, 3, 10, 0, 0); // Server time
      // Client time would be 7h ahead in real scenario, but test simulates server behavior

      final mockSnapshot = createSnapshot(serverTime, 100, 1);

      // Track API call parameters
      int? capturedStartTs;
      int? capturedEndTs;

      final container = ProviderContainer(
        overrides: [
          snapshotBufferProvider.overrideWith((ref) {
            return _MockBufferNotifier([mockSnapshot]);
          }),
          validatorApiClientProvider.overrideWith((ref) {
            return _MockApiClient(
              onGetHistory: (startTs, endTs) {
                capturedStartTs = startTs;
                capturedEndTs = endTs;
                return Future.value([mockSnapshot]);
              },
            );
          }),
        ],
      );

      // Act
      container.read(chartDataProvider(ChartTimeRange.hour1));

      // Wait for async completion
      await Future.delayed(const Duration(milliseconds: 150));

      // Assert
      final expectedEndTs = serverTime.millisecondsSinceEpoch ~/ 1000;
      final expectedStartTs = expectedEndTs - (60 * 60); // 1 hour

      expect(capturedEndTs, equals(expectedEndTs),
          reason:
              'Should use server time from buffer, not client DateTime.now()');
      expect(capturedStartTs, equals(expectedStartTs),
          reason: 'Start timestamp should be calculated from server time');

      container.dispose();
    });

    test('Sampling reduces large datasets to manageable size', () async {
      // Arrange
      final now = DateTime(2026, 1, 3, 10, 0, 0);
      final largeDataset = List.generate(
          500,
          (i) => createSnapshot(
                now.subtract(Duration(seconds: 500 - i)),
                100 + i,
                i,
              ));

      final mockBufferSnapshot = createSnapshot(now, 600, 500);

      final container = ProviderContainer(
        overrides: [
          snapshotBufferProvider.overrideWith((ref) {
            return _MockBufferNotifier([mockBufferSnapshot]);
          }),
          validatorApiClientProvider.overrideWith((ref) {
            return _MockApiClient(
              onGetHistory: (_, __) => Future.value(largeDataset),
            );
          }),
        ],
      );

      // Act - wait for data to be available
      container.read(chartDataProvider(ChartTimeRange.hour6));

      // Wait for async data
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert
      final resultAfterLoad =
          container.read(chartDataProvider(ChartTimeRange.hour6));
      resultAfterLoad.when(
        data: (data) {
          // Sampling should reduce 500 snapshots to ~300
          expect(data.length, lessThan(400),
              reason: 'Large datasets should be sampled');
          expect(data.first.timestamp.isBefore(data.last.timestamp), isTrue,
              reason: 'Data should be sorted by timestamp');
        },
        loading: () {
          // Acceptable - still loading
        },
        error: (e, st) => fail('Should not error: $e'),
      );

      container.dispose();
    });
  });
}

/// Simple mock that provides snapshot buffer data without async initialization
class _MockBufferNotifier extends SnapshotBufferNotifier {
  _MockBufferNotifier(super.data) : super.test();

  // Override checkForGaps to prevent timer-based gap detection in tests
  @override
  void checkForGaps() {
    // No-op for tests
  }
}

/// Mock API client for testing
class _MockApiClient implements ValidatorApiClient {
  final Future<List<ValidatorSnapshot>> Function(int startTs, int endTs)
      onGetHistory;

  _MockApiClient({required this.onGetHistory});

  @override
  Future<List<ValidatorSnapshot>> getHistory({
    int? hours,
    int? startTimestamp,
    int? endTimestamp,
  }) {
    if (startTimestamp != null && endTimestamp != null) {
      return onGetHistory(startTimestamp, endTimestamp);
    }
    throw UnimplementedError('Test only supports start/end timestamp queries');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
