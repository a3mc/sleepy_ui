import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for compact mode state (forces compact layout regardless of screen width)
final compactModeProvider =
    StateNotifierProvider<CompactModeNotifier, bool>((ref) {
  return CompactModeNotifier();
});

class CompactModeNotifier extends StateNotifier<bool> {
  CompactModeNotifier() : super(false);

  void toggle() {
    state = !state;
  }

  void enable() {
    state = true;
  }

  void disable() {
    state = false;
  }
}
