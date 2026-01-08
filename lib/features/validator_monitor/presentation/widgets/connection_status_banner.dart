import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/connection_status_provider.dart';
import '../../../../core/themes/app_theme.dart';

// Connection status banner with animated state transitions
class ConnectionStatusBanner extends ConsumerWidget {
  const ConnectionStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionStatusProvider);

    // Hide banner when connected
    if (connectionState.status == ConnectionStatus.connected) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: connectionState.status == ConnectionStatus.connected ? 0 : 32,
      decoration: BoxDecoration(
        color: _getBackgroundColor(connectionState.status),
        boxShadow: [
          BoxShadow(
            color: AppTheme.backgroundDarkest.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: connectionState.status == ConnectionStatus.connected ? 0 : 1,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status indicator
            SizedBox(
              width: 16,
              height: 16,
              child: _buildStatusIndicator(connectionState.status),
            ),
            const SizedBox(width: 8),
            // Status text
            Text(
              _getStatusText(connectionState),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(ConnectionStatus status) {
    return switch (status) {
      ConnectionStatus.reconnecting => const CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ConnectionStatus.disconnected => const Icon(
          Icons.cloud_off,
          size: 16,
          color: Colors.white,
        ),
      ConnectionStatus.connected => const Icon(
          Icons.cloud_done,
          size: 16,
          color: Colors.white,
        ),
    };
  }

  Color _getBackgroundColor(ConnectionStatus status) {
    return switch (status) {
      ConnectionStatus.connected => Colors.green.shade600,
      ConnectionStatus.reconnecting => Colors.orange.shade600,
      ConnectionStatus.disconnected => Colors.red.shade600,
    };
  }

  String _getStatusText(ConnectionStatusState state) {
    return switch (state.status) {
      ConnectionStatus.connected => 'Connected',
      ConnectionStatus.reconnecting => state.retryAttempt > 0
          ? 'Reconnecting (attempt ${state.retryAttempt})...'
          : 'Reconnecting...',
      ConnectionStatus.disconnected => (state.errorMessage?.isNotEmpty ?? false)
          ? 'Connection lost: ${_cleanErrorMessage(state.errorMessage!)}'
          : 'Connection lost',
    };
  }

  String _cleanErrorMessage(String error) {
    // Strip 'Exception: ' prefix from error messages
    final cleaned = error.replaceFirst(RegExp(r'^Exception:\s*'), '');

    // Extract user-friendly message from common patterns
    if (cleaned.contains('Reconnecting')) {
      return 'Retrying connection';
    }
    if (cleaned.contains('SocketException') ||
        cleaned.contains('Connection refused')) {
      return 'Backend unavailable';
    }
    if (cleaned.contains('Authentication failed')) {
      return 'Authentication failed';
    }
    if (cleaned.contains('TimeoutException')) {
      return 'Connection timeout';
    }

    // Fallback: return first sentence or first 60 chars
    final firstSentence = cleaned.split('.').first;
    return firstSentence.length > 60
        ? '${firstSentence.substring(0, 60)}...'
        : firstSentence;
  }
}
