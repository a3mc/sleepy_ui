import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for resource feed panel visibility state
/// Mobile default: hidden (saves space)
/// Desktop default: shown (full UI)
final creditsFeedVisibilityProvider = StateProvider<bool>((ref) {
  // Default to hidden on mobile platforms
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    return false;
  }
  // Default to shown on desktop
  return true;
});
