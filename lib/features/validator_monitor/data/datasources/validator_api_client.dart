import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants/api_constants.dart';
import '../models/service_health.dart';
import '../models/validator_status.dart';
import '../models/validator_snapshot.dart';

// Disable verbose logging - only errors logged
const _kEnableVerboseLogging = false;
void _log(String message) {
  if (_kEnableVerboseLogging) debugPrint(message);
}

// Static helper for isolate execution (must be top-level or static for compute())
// Parses JSON history response on background isolate to prevent UI thread blocking
List<ValidatorSnapshot> _parseHistoryInIsolate(String jsonBody) {
  // CRITICAL FIX [ERR-02]: Wrap top-level parse operations in defensive try-catch
  // Isolate errors must be caught here - compute() wrapper provides generic context

  final Map<String, dynamic> json;
  try {
    json = jsonDecode(jsonBody) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw Exception('Invalid JSON in history response: ${e.message}');
  } catch (e) {
    throw Exception('Failed to parse history response: $e');
  }

  // Validate 'data' field exists and is correct type
  if (!json.containsKey('data')) {
    throw Exception('History response missing required "data" field');
  }

  final Object? dataRaw = json['data'];
  if (dataRaw is! List) {
    throw Exception(
        'History response "data" field has wrong type: expected List, got ${dataRaw.runtimeType}');
  }

  final data = dataRaw;

  final results = <ValidatorSnapshot>[];

  for (var i = 0; i < data.length; i++) {
    try {
      final item = data[i];
      final snapshot = item as Map<String, dynamic>;

      // Check if 'validator' key exists and is not null
      if (!snapshot.containsKey('validator') || snapshot['validator'] == null) {
        continue;
      }

      final validatorRaw = snapshot['validator'];
      if (validatorRaw is! Map<String, dynamic>) {
        continue;
      }

      final validator = validatorRaw;
      final ourValidator = validator['our_validator'] as Map<String, dynamic>?;
      final rank1 = validator['rank1'] as Map<String, dynamic>?;

      final validSnapshot = ValidatorSnapshot.fromJson({
        'timestamp': DateTime.fromMillisecondsSinceEpoch(
          (snapshot['timestamp'] as int) * 1000,
        ).toIso8601String(),
        'validator': {
          'our_validator': {
            'rank': (ourValidator?['rank'] as int?) ?? 0,
            'vote_distance': (ourValidator?['vote_distance'] as int?) ?? 0,
            'root_distance': (ourValidator?['root_distance'] as int?) ?? 0,
            'credits': (ourValidator?['credits'] as int?) ?? 0,
            'credits_delta': (ourValidator?['credits_delta'] as int?) ?? 0,
            'gap_to_rank1': (ourValidator?['gap_to_rank1'] as int?) ?? 0,
            'gap_to_top10': (ourValidator?['gap_to_top10'] as int?) ?? 0,
            'gap_to_top100': (ourValidator?['gap_to_top100'] as int?) ?? 0,
            'gap_to_top200': (ourValidator?['gap_to_top200'] as int?) ?? 0,
          },
          'rank1': {
            'credits': (rank1?['credits'] as int?) ?? 0,
            'credits_delta': (rank1?['credits_delta'] as int?) ?? 0,
          },
          if (validator.containsKey('events')) 'events': validator['events'],
        },
        if (snapshot.containsKey('network')) 'network': snapshot['network'],
      });

      results.add(validSnapshot);
    } catch (e) {
      // Skip malformed snapshots silently in isolate
      continue;
    }
  }

  return results;
}

// API client for HTTP requests (non-streaming endpoints)
class ValidatorApiClient {
  final http.Client _httpClient;
  final Future<String?> Function() _getToken;
  final String Function() _getBaseUrl;

  // Token caching to reduce I/O overhead
  String? _cachedToken;
  DateTime? _tokenCacheTime;
  static const _tokenCacheDuration = Duration(seconds: 30);

  ValidatorApiClient({
    http.Client? httpClient,
    required Future<String?> Function() getToken,
    required String Function() getBaseUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _getToken = getToken,
        _getBaseUrl = getBaseUrl;

  // Clear token cache (called on 401/403 or token change)
  void clearTokenCache() {
    _cachedToken = null;
    _tokenCacheTime = null;
  }

  // Get token with TTL-based caching
  Future<String?> _getCachedToken() async {
    final now = DateTime.now();

    // Return cached token if still valid
    if (_cachedToken != null &&
        _tokenCacheTime != null &&
        now.difference(_tokenCacheTime!) < _tokenCacheDuration) {
      return _cachedToken;
    }

    // Fetch fresh token and cache it
    _cachedToken = await _getToken();
    _tokenCacheTime = now;
    return _cachedToken;
  }

  // ASYNC-03: Execute async operation with timeout covering entire flow
  Future<T> _executeWithTimeout<T>(Future<T> Function() operation) {
    return operation().timeout(
      ApiConstants.httpTimeout,
      onTimeout: () => throw TimeoutException(
        'Operation exceeded ${ApiConstants.httpTimeout.inSeconds}s timeout',
      ),
    );
  }

  // Build headers with Authorization if token available
  Future<Map<String, String>> _buildHeaders() async {
    final token = await _getCachedToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  // GET /health - Service health check
  Future<ServiceHealth> getHealth() async {
    return _executeWithTimeout(() async {
      final uri = Uri.parse('${_getBaseUrl()}${ApiConstants.healthPath}');
      _log('[API] Fetching health from $uri');

      try {
        final headers = await _buildHeaders();
        final response = await _httpClient.get(uri, headers: headers);
        _log('[API] Health status ${response.statusCode}');

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          _log('[API] Health parsed successfully');
          return ServiceHealth.fromJson(json);
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          clearTokenCache(); // Clear stale token
          throw Exception('Authentication failed - check bearer token');
        } else {
          throw Exception('Health check failed: ${response.statusCode}');
        }
      } catch (e) {
        _log('[API] Health error: $e');
        throw Exception('Failed to fetch health: $e');
      }
    });
  }

  // GET /status - Validator status snapshot
  Future<ValidatorStatus> getStatus() async {
    return _executeWithTimeout(() async {
      final uri = Uri.parse('${_getBaseUrl()}${ApiConstants.statusPath}');
      _log('[API] Fetching status from $uri');

      try {
        final headers = await _buildHeaders();
        final response = await _httpClient.get(uri, headers: headers);
        _log('[API] Status response: ${response.statusCode}');

        if (response.statusCode == 200) {
          try {
            final json = jsonDecode(response.body) as Map<String, dynamic>;
            _log('[API] Status JSON keys: ${json.keys.toList()}');
            final status = ValidatorStatus.fromJson(json);
            _log('[API] Status parsed successfully');
            return status;
          } catch (e) {
            _log('[API] Status parse error: $e');
            _log('[API] Status response body: ${response.body}');
            rethrow;
          }
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          clearTokenCache(); // Clear stale token
          throw Exception('Authentication failed - check bearer token');
        } else {
          throw Exception('Status request failed: ${response.statusCode}');
        }
      } catch (e) {
        _log('[API] Status error: $e');
        throw Exception('Failed to fetch status: $e');
      }
    });
  }

  // GET /history?hours=N - Historical snapshots
  Future<List<ValidatorSnapshot>> getHistory({
    int? hours,
    int? startTimestamp,
    int? endTimestamp,
  }) async {
    return _executeWithTimeout(() async {
      final queryParams = <String, String>{};

      if (hours != null) {
        queryParams['hours'] = hours.toString();
      } else if (startTimestamp != null && endTimestamp != null) {
        queryParams['start'] = startTimestamp.toString();
        queryParams['end'] = endTimestamp.toString();
      } else {
        throw ArgumentError(
            'Must provide either hours or start/end timestamps');
      }

      final uri = Uri.parse('${_getBaseUrl()}${ApiConstants.historyPath}')
          .replace(queryParameters: queryParams);

      _log('[API] Fetching history from $uri');
      _log('[API] Query params: $queryParams');

      try {
        final headers = await _buildHeaders();
        final response = await _httpClient.get(uri, headers: headers);

        _log('[API] History status ${response.statusCode}');
        if (response.statusCode != 200) {
          _log('[API] History error body: ${response.body}');
        }

        if (response.statusCode == 200) {
          // Use adaptive parsing strategy based on payload size:
          // - Small payloads (<50KB): parse synchronously (faster, avoids isolate overhead)
          // - Large payloads (≥50KB): parse in isolate (prevents UI freeze)
          // Threshold chosen because isolate spawn (10-50ms) exceeds parse time below 50KB
          final bodyLength = response.body.length;
          const isolateThresholdBytes = 50000; // 50KB

          final List<ValidatorSnapshot> results;

          if (bodyLength < isolateThresholdBytes) {
            // Small payload: parse synchronously
            _log('[API] Parsing history synchronously ($bodyLength bytes)...');
            results = _parseHistoryInIsolate(response.body);
          } else {
            // Large payload: parse in background isolate to prevent UI freeze
            _log('[API] Parsing history in isolate ($bodyLength bytes)...');
            results = await compute(_parseHistoryInIsolate, response.body);
          }

          _log('[API] History parsed: ${results.length} snapshots');
          return results;
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          clearTokenCache(); // Clear stale token
          throw Exception('Authentication failed - check bearer token');
        } else {
          throw Exception('History request failed: ${response.statusCode}');
        }
      } catch (e) {
        _log('[API] History error: $e');
        throw Exception('Failed to fetch history: $e');
      }
    });
  }

  // GET /missed?from={seq}&to={seq} - Recover missed stream events
  Future<List<ValidatorSnapshot>> getMissedSnapshots(
      int fromSeq, int toSeq) async {
    return _executeWithTimeout(() async {
      final uri =
          Uri.parse('${_getBaseUrl()}/missed').replace(queryParameters: {
        'from': fromSeq.toString(),
        'to': toSeq.toString(),
      });

      _log('[API] Fetching missed snapshots from $uri');

      try {
        final headers = await _buildHeaders();
        final response = await _httpClient.get(uri, headers: headers);

        _log('[API] Missed snapshots status ${response.statusCode}');

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final sessionId = json['session_id'] as String?;
          final events = json['events'] as List<dynamic>;

          _log(
              '[API] Missed snapshots: session=$sessionId, count=${events.length}');

          final results = <ValidatorSnapshot>[];
          Exception? firstParseError; // [ERR-04] Track first error for context

          for (var i = 0; i < events.length; i++) {
            try {
              final snapshot =
                  ValidatorSnapshot.fromJson(events[i] as Map<String, dynamic>);
              results.add(snapshot);
            } catch (e) {
              // Capture first error for final exception context
              firstParseError ??= Exception(e.toString());

              _log('[API] Failed to parse missed snapshot $i: $e');
              // Continue parsing remaining events
            }
          }

          if (results.isEmpty && events.isNotEmpty) {
            // Improved error message with context [ERR-04]
            final errorContext = firstParseError != null
                ? '. First error: ${firstParseError.toString()}'
                : '';

            throw Exception(
                'Failed to parse any missed snapshots from ${events.length} events$errorContext');
          }

          return results;
        } else if (response.statusCode == 410) {
          // Events no longer in cache
          _log('[API] Missed snapshots gone (410) - events evicted from cache');
          throw Exception('Events no longer available in cache');
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          clearTokenCache();
          throw Exception('Authentication failed - check bearer token');
        } else {
          throw Exception(
              'Missed snapshots request failed: ${response.statusCode}');
        }
      } catch (e) {
        _log('[API] Missed snapshots error: $e');
        rethrow;
      }
    });
  }

  void dispose() {
    _httpClient.close();
  }
}
