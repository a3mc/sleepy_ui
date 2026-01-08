import 'event_metadata.dart';

// Minimal data model for stream snapshots
// Only includes fields needed for circular blade visualization
class ValidatorSnapshot {
  final String? sessionId; // Backend session UUID - changes on restart
  final int? sequence; // Monotonic sequence counter for gap detection
  final DateTime timestamp;
  final int rank; // Validator rank per cycle
  final int voteDistance;
  final int rootDistance;
  final int ourCredits;
  final int rank1Credits;
  final int creditsDelta; // Per-cycle credits earned by our validator
  final int rank1CreditsDelta; // Per-cycle credits earned by rank1
  final int
      creditsPerformanceGap; // rank1_delta - our_delta (negative=we're ahead, positive=we're behind)
  final int gapToRank1; // Gap to rank #1 (minimize = better)
  final int gapToTop10; // Gap to top 10 median (maximize = better)
  final int gapToTop100; // Gap to top 100 median (maximize = better)
  final int gapToTop200; // Gap to top 200 median (maximize = better)
  final EventMetadata? events; // Alert state metadata
  final double progressPercent; // Epoch progress percentage
  final String estimatedTimeRemaining; // Estimated time until epoch end
  final double slotTimeMs; // Network slot time in milliseconds
  final double cycleTimeSeconds; // Vote cycle time in seconds

  const ValidatorSnapshot({
    this.sessionId,
    this.sequence,
    required this.timestamp,
    required this.rank,
    required this.voteDistance,
    required this.rootDistance,
    required this.ourCredits,
    required this.rank1Credits,
    required this.creditsDelta,
    required this.rank1CreditsDelta,
    required this.creditsPerformanceGap,
    required this.gapToRank1,
    required this.gapToTop10,
    required this.gapToTop100,
    required this.gapToTop200,
    this.events,
    this.progressPercent = 0.0,
    this.estimatedTimeRemaining = 'N/A',
    this.slotTimeMs = 0.0,
    this.cycleTimeSeconds = 0.0,
  });

  factory ValidatorSnapshot.fromJson(Map<String, dynamic> json) {
    // Handle both /status format and /stream (history) format
    Map<String, dynamic> ourValidator;
    int rank1Credits;
    int rank1CreditsDelta;

    if (json.containsKey('validator')) {
      // History/stream format: {"timestamp":..., "validator":{"our_validator":{...}, "rank1":{...}}}
      final validator = json['validator'] as Map<String, dynamic>;

      // Handle null nested objects in history data
      final ourValidatorRaw = validator['our_validator'];
      final rank1Raw = validator['rank1'];

      if (ourValidatorRaw == null || rank1Raw == null) {
        throw FormatException(
            'Invalid history data: missing our_validator or rank1');
      }

      ourValidator = ourValidatorRaw as Map<String, dynamic>;
      final rank1 = rank1Raw as Map<String, dynamic>;
      rank1Credits = rank1['credits'] as int;
      rank1CreditsDelta = (rank1['credits_delta'] as int?) ?? 0;
    } else {
      // Status format: {"our_validator":{...}, "rank1_benchmark":{...}}
      ourValidator = json['our_validator'] as Map<String, dynamic>;
      final rank1Benchmark = json['rank1_benchmark'] as Map<String, dynamic>;
      rank1Credits = rank1Benchmark['credits_total'] as int;
      rank1CreditsDelta = 0; // Not available in status format
    }

    // Extract vote and root distance (different fields in history vs status)
    int rank;
    int voteDistance;
    int rootDistance;
    int ourCredits;
    int creditsDelta;
    int gapToRank1;

    int gapToTop10;
    int gapToTop100;
    int gapToTop200;

    if (ourValidator.containsKey('vote_distance')) {
      // History/stream format - handle null values from historical data
      rank = ourValidator['rank'] as int;
      voteDistance = ourValidator['vote_distance'] as int;
      rootDistance = ourValidator['root_distance'] as int;
      ourCredits = ourValidator['credits'] as int;
      creditsDelta = (ourValidator['credits_delta'] as int?) ?? 0;
      gapToRank1 = ourValidator['gap_to_rank1'] as int;
      gapToTop10 = ourValidator['gap_to_top10'] as int;
      gapToTop100 = ourValidator['gap_to_top100'] as int;
      gapToTop200 = ourValidator['gap_to_top200'] as int;
    } else {
      // Status format
      rank = 0; // Not available in status format
      voteDistance = (ourValidator['vote']
          as Map<String, dynamic>)['distance_from_max'] as int;
      rootDistance = (ourValidator['root']
          as Map<String, dynamic>)['distance_from_max'] as int;
      ourCredits =
          (ourValidator['credits'] as Map<String, dynamic>)['total'] as int;
      creditsDelta = 0;
      gapToRank1 = ourCredits - rank1Credits;
      gapToTop10 = 0; // Not available in status format
      gapToTop100 = 0;
      gapToTop200 = 0;
    }

    // Parse session_id and sequence (optional for backward compatibility with old data)
    final String? sessionId = json['session_id'] as String?;
    final int? sequence = json['sequence'] as int?;

    // Parse timestamp (int for history, string for status)
    DateTime timestamp;
    final tsValue = json['timestamp'];
    if (tsValue is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(tsValue * 1000);
    } else if (tsValue is String) {
      try {
        timestamp = DateTime.parse(tsValue);
      } on FormatException catch (e) {
        throw FormatException(
            'Invalid timestamp format: $e. Value: "$tsValue"');
      }
    } else {
      throw FormatException(
          'Invalid timestamp type: expected int or String, got ${tsValue.runtimeType}. Value: $tsValue');
    }

    // Parse events metadata (only present in stream/history format)
    EventMetadata? events;
    if (json.containsKey('validator')) {
      final validator = json['validator'] as Map<String, dynamic>;
      if (validator.containsKey('events')) {
        events =
            EventMetadata.fromJson(validator['events'] as Map<String, dynamic>);
      }
    }

    // Parse epoch progress from network section (stream format only)
    // Use null-aware chaining to safely access nested optional fields
    final network = json['network'] as Map<String, dynamic>?;
    final epochProgress = network?['epoch_progress'] as Map<String, dynamic>?;
    final progressPercent =
        (epochProgress?['progress_percent'] as num?)?.toDouble() ?? 0.0;
    final estimatedTimeRemaining =
        (epochProgress?['estimated_time_remaining'] as String?) ?? 'N/A';
    final slotTimeMs = (network?['slot_time_ms'] as num?)?.toDouble() ?? 0.0;
    final cycleTimeSeconds =
        (network?['cycle_time_seconds'] as num?)?.toDouble() ?? 0.0;

    return ValidatorSnapshot(
      sessionId: sessionId,
      sequence: sequence,
      timestamp: timestamp,
      rank: rank,
      voteDistance: voteDistance,
      rootDistance: rootDistance,
      ourCredits: ourCredits,
      rank1Credits: rank1Credits,
      creditsDelta: creditsDelta,
      rank1CreditsDelta: rank1CreditsDelta,
      creditsPerformanceGap: rank1CreditsDelta - creditsDelta,
      gapToRank1: gapToRank1,
      gapToTop10: gapToTop10,
      gapToTop100: gapToTop100,
      gapToTop200: gapToTop200,
      events: events,
      progressPercent: progressPercent,
      estimatedTimeRemaining: estimatedTimeRemaining,
      slotTimeMs: slotTimeMs,
      cycleTimeSeconds: cycleTimeSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'sequence': sequence,
        'timestamp': timestamp.toIso8601String(),
        'rank': rank,
        'voteDistance': voteDistance,
        'rootDistance': rootDistance,
        'ourCredits': ourCredits,
        'rank1Credits': rank1Credits,
        'creditsDelta': creditsDelta,
        'rank1CreditsDelta': rank1CreditsDelta,
        'creditsPerformanceGap': creditsPerformanceGap,
        'gapToRank1': gapToRank1,
        'gapToTop10': gapToTop10,
        'gapToTop100': gapToTop100,
        'gapToTop200': gapToTop200,
      };
}
