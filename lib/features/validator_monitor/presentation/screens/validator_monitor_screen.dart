import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/validator_providers.dart';
import '../../data/models/validator_status.dart';
import '../../data/models/validator_snapshot.dart';

// Simple test screen to verify data flow
class ValidatorMonitorScreen extends ConsumerWidget {
  const ValidatorMonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotBuffer = ref.watch(snapshotBufferProvider);
    final statusAsync = ref.watch(validatorStatusProvider);
    final healthAsync = ref.watch(serviceHealthProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Validator Monitor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Health status
            healthAsync.when(
              data: (health) =>
                  _buildHealthCard(health.isHealthy, health.uptimeSeconds),
              loading: () => const CircularProgressIndicator(),
              error: (err, stack) => Text('Health check failed: $err'),
            ),

            const SizedBox(height: 16),

            // Validator status
            statusAsync.when(
              data: (status) => _buildStatusCard(status),
              loading: () => const CircularProgressIndicator(),
              error: (err, stack) => Text('Status failed: $err'),
            ),

            const SizedBox(height: 16),

            // Snapshot buffer info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Real-time Stream',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Buffer size: ${snapshotBuffer.length} snapshots'),
                    if (snapshotBuffer.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Latest snapshot:'),
                      Text(
                          '  Vote distance: ${snapshotBuffer.last.voteDistance}'),
                      Text(
                          '  Root distance: ${snapshotBuffer.last.rootDistance}'),
                      Text(
                          '  Credits delta: ${snapshotBuffer.last.creditsDelta}'),
                      Text(
                          '  Timestamp: ${snapshotBuffer.last.timestamp.toLocal()}'),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Last 10 snapshots visualization
            if (snapshotBuffer.length >= 10)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last 10 Cycles',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child: _buildSnapshotTable(snapshotBuffer
                                .sublist(snapshotBuffer.length - 10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCard(bool isHealthy, int uptimeSeconds) {
    return Card(
      color: isHealthy ? Colors.green.shade900 : Colors.red.shade900,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              isHealthy ? Icons.check_circle : Icons.error,
              color: Colors.white,
            ),
            const SizedBox(width: 16),
            Text(
              isHealthy ? 'Service Healthy' : 'Service Degraded',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const Spacer(),
            Text(
              'Uptime: ${Duration(seconds: uptimeSeconds).inHours}h',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(ValidatorStatus status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Epoch: ${status.epoch}'),
            Text('Rank: ${status.rank}'),
            Text('Active validators: ${status.activeValidators}'),
            Text(
                'Degraded: ${status.inDegradedState} (${status.degradedDurationSecs}s)'),
            Text(
                'Fork phase: ${status.forkTrackingPhase} (${status.forkAlertColor})'),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotTable(List<ValidatorSnapshot> snapshots) {
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(60),
        1: FixedColumnWidth(60),
        2: FixedColumnWidth(80),
      },
      children: [
        TableRow(
          children: [
            Text('Vote', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Root', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Δ Credits', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        ...snapshots.map((s) => TableRow(
              children: [
                Text(s.voteDistance.toString()),
                Text(s.rootDistance.toString()),
                Text(s.creditsDelta.toString()),
              ],
            )),
      ],
    );
  }
}
