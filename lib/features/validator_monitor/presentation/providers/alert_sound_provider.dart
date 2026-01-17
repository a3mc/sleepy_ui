import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/alert_sound_service.dart';
import './sound_settings_provider.dart';

/// Alert sound service provider with lifecycle management
final alertSoundServiceProvider =
    FutureProvider<AlertSoundService>((ref) async {
  final service = AlertSoundService();

  await service.initialize();

  final initialVolume = ref.read(soundVolumeProvider);
  await service.setVolume(initialVolume);

  ref.listen<double>(
    soundVolumeProvider,
    (previous, next) async {
      try {
        await service.setVolume(next);
      } catch (e) {
        debugPrint('Failed to update sound volume: $e');
      }
    },
  );

  ref.onDispose(() async {
    await service.dispose();
  });

  return service;
});
