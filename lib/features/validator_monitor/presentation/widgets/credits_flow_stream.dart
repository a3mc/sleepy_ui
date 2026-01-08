import 'package:flutter/material.dart';
import '../../data/models/validator_snapshot.dart';

/// Credits Flow Indicators - Compact visual stream showing wins/losses
class CreditsFlowStream extends StatelessWidget {
  final List<ValidatorSnapshot> snapshots;
  final int maxIndicators;

  const CreditsFlowStream({
    super.key,
    required this.snapshots,
    this.maxIndicators = 100,
  });

  @override
  Widget build(BuildContext context) {
    final events = _extractEvents();

    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: 100, // Fixed width to prevent unbounded constraints
      height: 250, // Match chart height
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF333333),
            width: 1,
          ),
        ),
        child: ListView(
          children: events
              .map((event) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _buildIndicator(event),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildIndicator(({int change, bool isWin}) event) {
    final isWin = event.isWin;
    final change = event.change.abs();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isWin
            ? const Color(0xFF00AA00).withValues(alpha: 0.2)
            : const Color(0xFFFF4444).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isWin ? const Color(0xFF00AA00) : const Color(0xFFFF4444),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWin ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: isWin ? const Color(0xFF4CAF50) : const Color(0xFFFF6666),
          ),
          const SizedBox(width: 4),
          Text(
            '${isWin ? '+' : '-'}$change',
            style: TextStyle(
              color: isWin ? const Color(0xFF4CAF50) : const Color(0xFFFF6666),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  List<({int change, bool isWin})> _extractEvents() {
    if (snapshots.length < 2) return [];

    final events = <({int change, bool isWin})>[];

    for (int i = 1;
        i < snapshots.length && events.length < maxIndicators;
        i++) {
      final current = snapshots[i];
      final previous = snapshots[i - 1];

      final gapChange = previous.gapToRank1 - current.gapToRank1;

      if (gapChange > 0) {
        // Positive change = closing gap to rank #1 = win
        events.add((change: gapChange, isWin: true));
      } else if (gapChange < -50) {
        // Large loss = show immediately
        events.add((change: gapChange, isWin: false));
      }
    }

    return events.reversed.take(maxIndicators).toList();
  }
}
