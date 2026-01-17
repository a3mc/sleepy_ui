import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, HttpException;
import 'dart:math' show min;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../../../../core/constants/api_constants.dart';
import '../models/validator_snapshot.dart';

// Disable verbose logging - only errors logged
const _kEnableVerboseLogging = false;

/// Classification of stream errors for user-friendly messaging
enum StreamErrorType {
  /// Network connectivity issues (DNS, connection refused, timeouts)
  network,

  /// Malformed data from server (invalid UTF-8, JSON errors)
  malformedData,

  /// Server returned error status (5xx codes)
  serverError,

  /// Unknown/unexpected errors
  unknown,
}

void _log(String message) {
  if (_kEnableVerboseLogging) debugPrint(message);
}

// SSE stream client for real-time performance updates
class ValidatorStreamClient {
  final http.Client _httpClient;
  final Future<String?> Function() _getToken;
  final String Function() _getBaseUrl;
  StreamController<ValidatorSnapshot>? _controller;
  http.StreamedResponse? _response;
  StreamSubscription<String>? _subscription;

  int _retryCount = 0;
  static const int _exponentialPhaseRetries =
      5; // Exponential backoff for first 5 attempts
  static const int _steadyStateDelaySeconds =
      8; // Fixed delay after exponential phase
  // No max retry limit for emergency monitoring - must reconnect indefinitely
  // Only authentication errors cause terminal failure (handled separately)
  bool _isDisposed = false;

  // SSE frame buffer size limit - protects against malformed streams
  static const int _maxSseFrameSize = 100 * 1024; // 100KB limit

  ValidatorStreamClient({
    http.Client? httpClient,
    required Future<String?> Function() getToken,
    required String Function() getBaseUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _getToken = getToken,
        _getBaseUrl = getBaseUrl;

  // Connect to /stream endpoint and return stream of snapshots
  Stream<ValidatorSnapshot> connect() {
    if (_controller != null && !_controller!.isClosed) {
      throw StateError('Stream already connected');
    }

    _controller = StreamController<ValidatorSnapshot>(
      onListen: _startStream,
      onCancel: _stopStream,
    );

    return _controller!.stream;
  }

  /// Classify stream errors for user-friendly error messaging
  StreamErrorType _classifyStreamError(Object error) {
    // Network connectivity issues
    if (error is SocketException || error is TimeoutException) {
      return StreamErrorType.network;
    }

    // HTTP protocol errors (rare - usually handled in _attemptConnection)
    if (error is HttpException) {
      return StreamErrorType.serverError;
    }

    // UTF-8 decode errors from utf8.decoder transformer
    // FormatException occurs when invalid UTF-8 bytes encountered
    if (error is FormatException && error.toString().contains('UTF-8')) {
      return StreamErrorType.malformedData;
    }

    // JSON parse errors (though these are caught in data handler)
    if (error is FormatException) {
      return StreamErrorType.malformedData;
    }

    // Unknown error type
    return StreamErrorType.unknown;
  }

  Future<void> _startStream() async {
    while (!_isDisposed) {
      try {
        await _attemptConnection();
        // Successful connection - reset retry counter
        _retryCount = 0;
        return;
      } catch (e) {
        if (_isDisposed) {
          return; // Exit early if disposed during connection attempt
        }

        // Check if this is an authentication error - stop retrying
        final errorMsg = e.toString();
        if (errorMsg.contains('Authentication failed')) {
          _log('[SSE] Auth error detected - stopping retries');
          _controller?.addError(
              Exception('Authentication failed - check bearer token'));
          return; // Stop retry loop - require user intervention
        }

        _retryCount++;

        // Calculate delay: exponential backoff for first N attempts, then fixed delay
        final int delaySeconds;
        if (_retryCount <= _exponentialPhaseRetries) {
          // Exponential backoff: 1s, 2s, 4s, 8s, 16s (capped at 16s)
          delaySeconds = (1 << (_retryCount - 1)).clamp(1, 16);
          _log(
              '[SSE] Exponential backoff: retry $_retryCount in ${delaySeconds}s');
        } else {
          // Steady state: retry every 8 seconds indefinitely
          // Emergency monitoring must not give up during prolonged outages
          delaySeconds = _steadyStateDelaySeconds;
          _log('[SSE] Steady retry: attempt $_retryCount in ${delaySeconds}s');
        }

        _controller?.addError('Reconnecting (attempt $_retryCount)');

        await Future.delayed(Duration(seconds: delaySeconds));
        // Guard against disposal during backoff delay
        if (_isDisposed) return;
      }
    }
  }

  Future<void> _attemptConnection() async {
    if (_isDisposed) {
      throw StateError('Cannot connect after disposal');
    }

    final uri = Uri.parse('${_getBaseUrl()}${ApiConstants.streamPath}');
    _log('[SSE] Connecting to $uri');

    try {
      final request = http.Request('GET', uri);
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      // Inject bearer token if available - fetched fresh on each attempt
      final token = await _getToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
        _log('[SSE] Authorization header added');
      } else {
        _log('[SSE] No token available for authorization');
      }

      _response = await _httpClient.send(request).timeout(
        ApiConstants.httpTimeout,
        onTimeout: () {
          _log(
              '[SSE] Connection timeout after ${ApiConstants.httpTimeout.inSeconds}s');
          throw TimeoutException(
              'SSE connection timeout', ApiConstants.httpTimeout);
        },
      );

      // Check disposal after async boundary to abort mid-flight connections
      if (_isDisposed) {
        await _response!.stream.drain().catchError((_) {});
        _response = null;
        throw StateError('Connection aborted: disposed during HTTP request');
      }

      _log('[SSE] Status ${_response!.statusCode}');

      if (_response!.statusCode == 401 || _response!.statusCode == 403) {
        final error = Exception('Authentication failed - check bearer token');
        _log('[SSE] Auth failed: ${_response!.statusCode}');
        _controller?.addError(error);
        await _response!.stream.drain();
        _response = null;
        // Throw auth error to stop retry loop
        throw error;
      }

      if (_response!.statusCode != 200) {
        final error =
            Exception('Stream connection failed: ${_response!.statusCode}');
        _log('[SSE] Connection failed: ${_response!.statusCode}');
        _controller?.addError(error);
        // Drain and close response to prevent resource leak
        await _response!.stream.drain();
        _response = null;
        throw error; // Rethrow to trigger retry logic
      }

      _log('[SSE] Connected, listening for events');

      // Buffer for incomplete SSE messages
      final buffer = StringBuffer();

      _subscription = _response!.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            // Extract JSON payload after "data: " prefix
            final jsonStr = line.substring(6);

            // SECURITY [NULL-01]: Check buffer size before appending
            // Protects against DoS from malformed SSE streams without empty line separators
            final potentialSize = buffer.length + jsonStr.length;
            if (potentialSize > _maxSseFrameSize) {
              final preview =
                  buffer.toString().substring(0, min(buffer.length, 200));
              final bufferLimitKb = _maxSseFrameSize ~/ 1024;
              _log(
                  '[SSE] [ERROR] Frame buffer exceeded $_maxSseFrameSize bytes - malformed stream detected');
              _log('[SSE] Buffer preview (first 200 chars): $preview...');
              _controller?.addError(Exception(
                  'SSE frame too large (>${bufferLimitKb}KB) - possible malformed stream or backend issue'));

              // Clear buffer and skip this frame - prevents OOM
              buffer.clear();
              return;
            }

            buffer.write(jsonStr);
          } else if (line.isEmpty && buffer.isNotEmpty) {
            // Empty line marks end of SSE event - parse and clear buffer
            try {
              // Step 1: Decode JSON (can throw FormatException)
              final Map<String, dynamic> json;
              try {
                json = jsonDecode(buffer.toString()) as Map<String, dynamic>;
              } on FormatException catch (e) {
                _log('[SSE] JSON decode error: $e');
                _log(
                    '[SSE] Malformed frame (first 200 chars): ${buffer.toString().substring(0, min(buffer.length, 200))}');
                _controller
                    ?.addError(Exception('Malformed JSON in SSE frame: $e'));
                return; // Skip this frame, continue stream
              }

              // Step 2: Deserialize to ValidatorSnapshot (can throw on schema mismatch)
              final ValidatorSnapshot snapshot;
              try {
                snapshot = ValidatorSnapshot.fromJson(json);
              } catch (e) {
                _log('[SSE] Schema validation error: $e');
                _log('[SSE] JSON keys: ${json.keys.toList()}');
                _controller
                    ?.addError(Exception('Schema mismatch in SSE data: $e'));
                return; // Skip this frame, continue stream
              }

              // Debug: Log alert sent status
              if (snapshot.events != null) {
                final temporal = snapshot.events!.temporal.alertSentThisCycle;
                final fork = snapshot.events!.fork.alertSentThisCycle;
                if (temporal || fork) {
                  debugPrint(
                      '[ALERT] Snapshot ${snapshot.timestamp}: temporal=$temporal, fork=$fork');
                }
              }

              _log('[SSE] Snapshot at ${snapshot.timestamp}');
              // Reset retry counter on successful data receipt
              _retryCount = 0;
              _controller?.add(snapshot);
            } finally {
              // Always clear buffer after processing attempt (success or failure)
              buffer.clear();
            }
          }
        },
        onError: (error) {
          // Classify error for structured logging and user feedback
          final errorType = _classifyStreamError(error);
          final userMessage = switch (errorType) {
            StreamErrorType.network => 'Network connection lost. Retrying...',
            StreamErrorType.malformedData =>
              'Received malformed data from server. This may indicate a backend issue.',
            StreamErrorType.serverError =>
              'Server error occurred. Retrying connection...',
            StreamErrorType.unknown =>
              'Unexpected stream error: ${error.runtimeType}',
          };

          _log('[SSE] Stream error (type: $errorType): $error');
          _controller?.addError(Exception(userMessage));

          // CRITICAL FIX [ERR-01]: Trigger reconnection immediately on ANY stream error
          // Stream transformer errors (utf8.decoder) may not call onDone
          // Clean up resources and initiate fresh connection attempt
          _subscription?.cancel();
          _subscription = null;
          _response = null;

          // Trigger retry loop with exponential backoff
          _startStream();
        },
        onDone: () {
          _log('[SSE] Stream closed, reconnecting');
          // Don't close controller - trigger reconnection
          // Keep as redundant safety net for graceful closures
          _startStream();
        },
        cancelOnError: false,
      );
    } catch (e) {
      throw Exception('Failed to connect to stream: $e');
    }
  }

  Future<void> _stopStream() async {
    _isDisposed =
        true; // Set flag FIRST to prevent new connections during teardown

    // NULL-02: _subscription may be null if connection never established or already cleaned up
    // Using null-safe operator (?.) ensures cancel() only called when subscription active
    await _subscription?.cancel();
    _subscription = null;
    // Response stream already consumed by subscription - no drain needed
    _response = null;
  }

  Future<void> dispose() async {
    await _stopStream();
    await _controller?.close();
    _controller = null;
    _httpClient.close();
  }
}
