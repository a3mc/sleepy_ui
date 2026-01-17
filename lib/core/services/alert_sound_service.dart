import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service for managing alert sounds with state tracking and loop control
class AlertSoundService {
  final List<AudioPlayer> _playerPool = [];
  AudioPlayer? _loopPlayer;
  double _volume = 0.7;
  static const int _poolSize = 4; // Support up to 4 simultaneous beeps
  int _currentPlayerIndex = 0; // Round-robin index
  DateTime? _lastBeepTime; // Rate limit beeps

  bool _isLooping = false;
  bool _isMuted = false;
  bool _criticalLoopSnoozed = false;
  bool _isInitialized = false;
  bool _isTogglingMute = false;
  bool _isDisposing = false;

  /// Initialize the audio players
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Create player pool for overlapping sounds
      // Use LOW LATENCY mode for short beep sounds (reduces UI/visual impact)
      for (int i = 0; i < _poolSize; i++) {
        final player = AudioPlayer();
        await player.setPlayerMode(PlayerMode
            .lowLatency); // Platform-specific optimization for short sounds
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setVolume(_volume);
        _playerPool.add(player);
      }

      // Loop player uses mediaPlayer mode (needs position/duration for loops)
      _loopPlayer = AudioPlayer();
      await _loopPlayer!.setReleaseMode(ReleaseMode.loop);
      await _loopPlayer!.setVolume(_volume);
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize audio players: $e');
      // Clean up any partially created players
      for (final player in _playerPool) {
        try {
          await player.dispose();
        } catch (_) {}
      }
      _playerPool.clear();
      try {
        await _loopPlayer?.dispose();
      } catch (_) {}
      _loopPlayer = null;
      _isInitialized = false;
    }
  }

  /// Update volume for all players
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_isInitialized) {
      for (final player in _playerPool) {
        await player.setVolume(_volume);
      }
      await _loopPlayer?.setVolume(_volume);
    }
  }

  /// Play beep sound (early warning)
  Future<void> playBeep() async {
    if (!_isInitialized || _isMuted || _isLooping) return;

    // RELIABILITY [SOUND-01]: Rate limit using UTC to survive DST transitions
    // Linux audioplayers can queue multiple beeps too fast
    // Prevent overlap glitches by enforcing minimum 200ms between beeps
    final now =
        DateTime.now().toUtc(); // UTC unaffected by DST/timezone changes
    if (_lastBeepTime != null) {
      final elapsed = now.difference(_lastBeepTime!).inMilliseconds;
      if (elapsed < 200) {
        debugPrint('[AlertSound] Beep rate-limited ($elapsed ms < 200ms)');
        return;
      }
    }
    _lastBeepTime = now;

    await _playSound('assets/sounds/beep.wav');
  }

  /// Play warning sound
  Future<void> playWarning() async {
    if (!_isInitialized || _isMuted || _isLooping) return;
    await _playSound('assets/sounds/warning.mp3');
  }

  /// Play critical loop
  Future<void> playCritical() async {
    if (!_isInitialized || _isMuted) return;
    if (!_criticalLoopSnoozed) {
      await _stopCriticalLoop();
      await _startCriticalLoop();
      _criticalLoopSnoozed = false;
    }
  }

  /// Play recovery sound and stop critical loop
  Future<void> playRecovery() async {
    if (!_isInitialized || _isMuted) return;
    await _stopCriticalLoop();
    await Future.delayed(const Duration(milliseconds: 100));
    await _playSound('assets/sounds/recover.mp3');
    _criticalLoopSnoozed = false;
  }

  Future<void> _playSound(String assetPath) async {
    if (!_isInitialized || _playerPool.isEmpty || _isDisposing) {
      debugPrint('Audio player not initialized or disposing');
      return;
    }

    // CRITICAL FIX [ALERT-01]: Never interrupt critical loop - it has absolute priority
    // Critical alert is "big boss" - engineers must hear it clearly during incidents
    if (_isLooping) {
      debugPrint(
          '[AlertSound] Skipped ${assetPath.split('/').last} - critical loop active');
      return;
    }

    try {
      // Use round-robin instead of state checking (Linux timing issues)
      // This prevents the same player being selected multiple times before state updates
      final player = _playerPool[_currentPlayerIndex];
      _currentPlayerIndex = (_currentPlayerIndex + 1) % _poolSize;

      // Stop any existing sound on this player
      try {
        await player.stop();
      } catch (_) {
        // Ignore stop errors - player might not be playing
      }

      final normalizedPath = assetPath.replaceAll('assets/', '');
      await player.play(AssetSource(normalizedPath));

      debugPrint(
          '[AlertSound] Playing ${assetPath.split('/').last} on player ${_currentPlayerIndex - 1}/$_poolSize');
    } catch (e) {
      debugPrint('Failed to play sound $assetPath: $e');
    }
  }

  /// Start looping critical sound
  Future<void> _startCriticalLoop() async {
    if (!_isInitialized || _loopPlayer == null || _isDisposing) {
      debugPrint('Loop player not initialized or disposing');
      return;
    }

    if (_isLooping) return;

    try {
      await _loopPlayer!.stop();
      _isLooping = true;
      await _loopPlayer!.play(AssetSource('sounds/critical.mp3'));
    } catch (e) {
      debugPrint('Failed to start critical loop: $e');
      _isLooping = false;
    }
  }

  Future<void> _stopCriticalLoop() async {
    if (!_isLooping || _loopPlayer == null || _isDisposing) return;

    try {
      await _loopPlayer!.stop();
      _isLooping = false;
    } catch (e) {
      debugPrint('Failed to stop critical loop: $e');
      _isLooping = false;
    }
  }

  /// Acknowledge critical alarm and prevent restart until new critical event
  Future<void> snoozeCriticalLoop() async {
    if (_isLooping) {
      await _stopCriticalLoop();
      _criticalLoopSnoozed = true;
    }
  }

  /// Mute all sounds
  Future<void> mute() async {
    _isMuted = true;
    for (final player in _playerPool) {
      await player.stop();
    }
    if (_isLooping) {
      await _stopCriticalLoop();
      _criticalLoopSnoozed = true;
    }
  }

  void unmute() {
    _isMuted = false;
    _criticalLoopSnoozed = false;
  }

  /// Toggle mute state or snooze critical alarm if active
  Future<void> toggleMute() async {
    if (_isTogglingMute) return;
    _isTogglingMute = true;

    try {
      if (_isMuted) {
        unmute();
      } else {
        if (_isLooping) {
          await snoozeCriticalLoop();
        } else {
          await mute();
        }
      }
    } finally {
      _isTogglingMute = false;
    }
  }

  /// Check if currently muted
  bool get isMuted => _isMuted;

  /// Check if critical loop is active
  bool get isLooping => _isLooping;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Reset all tracked severity states (useful for testing or reconnection)
  void resetStates() {
    _criticalLoopSnoozed = false;
  }

  /// Dispose resources
  Future<void> dispose() async {
    _isDisposing = true;

    for (final player in _playerPool) {
      try {
        await player.stop();
        await player.dispose();
      } catch (e) {
        debugPrint('Error disposing player: $e');
      }
    }
    _playerPool.clear();

    try {
      if (_loopPlayer != null) {
        await _loopPlayer!.stop();
        await _loopPlayer!.dispose();
        _loopPlayer = null;
      }
    } catch (e) {
      debugPrint('Error disposing loop player: $e');
    }

    _isInitialized = false;
    _isLooping = false;
  }
}
