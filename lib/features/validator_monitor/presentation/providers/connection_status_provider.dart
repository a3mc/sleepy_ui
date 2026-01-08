import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionStatus {
  connected,
  disconnected,
  reconnecting,
}

class ConnectionStatusState {
  final ConnectionStatus status;
  final String? errorMessage;
  final int retryAttempt;

  const ConnectionStatusState({
    required this.status,
    this.errorMessage,
    this.retryAttempt = 0,
  });

  ConnectionStatusState copyWith({
    ConnectionStatus? status,
    String? errorMessage,
    int? retryAttempt,
  }) {
    return ConnectionStatusState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      retryAttempt: retryAttempt ?? this.retryAttempt,
    );
  }
}

final connectionStatusProvider =
    StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatusState>(
        (ref) {
  return ConnectionStatusNotifier();
});

class ConnectionStatusNotifier extends StateNotifier<ConnectionStatusState> {
  // Initial state: reconnecting (establishing first connection)
  // NOT disconnected (implies connection was lost)
  ConnectionStatusNotifier()
      : super(const ConnectionStatusState(
            status: ConnectionStatus.reconnecting, retryAttempt: 0));

  void setConnected() {
    state = const ConnectionStatusState(status: ConnectionStatus.connected);
  }

  void setDisconnected(String? error) {
    state = ConnectionStatusState(
      status: ConnectionStatus.disconnected,
      errorMessage: error,
    );
  }

  void setReconnecting(int attempt) {
    state = ConnectionStatusState(
      status: ConnectionStatus.reconnecting,
      retryAttempt: attempt,
    );
  }

  void clearError() {
    state = const ConnectionStatusState(status: ConnectionStatus.disconnected);
  }
}
