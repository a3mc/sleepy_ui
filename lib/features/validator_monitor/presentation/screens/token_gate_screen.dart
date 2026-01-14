import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_token_provider.dart';
import '../providers/endpoint_config_provider.dart';
import '../providers/connection_status_provider.dart';
import '../providers/validator_providers.dart';
import 'dashboard_screen.dart';
import '../../../../core/themes/app_theme.dart';

/// Initial setup screen - collects all required configuration before starting app
/// Unified form for bearer token, endpoint host, port, and HTTPS setting
class TokenGateScreen extends ConsumerStatefulWidget {
  const TokenGateScreen({super.key});

  @override
  ConsumerState<TokenGateScreen> createState() => _TokenGateScreenState();
}

class _TokenGateScreenState extends ConsumerState<TokenGateScreen> {
  final _tokenController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8080');
  bool _isObscured = true;
  bool _isSaving = false;
  bool _useHttps = false;
  String? _errorMessage;

  @override
  void dispose() {
    _tokenController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _saveAndProceed() async {
    final token = _tokenController.text.trim();
    final host = _hostController.text.trim();
    final portText = _portController.text.trim();

    // Validate token
    final tokenError = AuthTokenNotifier.validateTokenInput(token);
    if (tokenError != null) {
      setState(() => _errorMessage = tokenError);
      return;
    }

    // Validate host
    if (host.isEmpty) {
      setState(() => _errorMessage = 'Host address is required');
      return;
    }

    // Validate port
    final port = int.tryParse(portText);
    if (port == null) {
      setState(() => _errorMessage = 'Port must be a number');
      return;
    }

    // Create and validate endpoint config
    final endpointConfig = EndpointConfig(
      host: host,
      port: port,
      useHttps: _useHttps,
    );

    final endpointError = endpointConfig.validate();
    if (endpointError != null) {
      setState(() => _errorMessage = endpointError);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      // Save both token and endpoint
      await ref.read(authTokenNotifierProvider.notifier).saveToken(token);
      await ref
          .read(endpointConfigNotifierProvider.notifier)
          .updateConfig(endpointConfig);

      // Clear connection status error
      ref.read(connectionStatusProvider.notifier).clearError();

      // Invalidate providers to force reconnection
      ref.invalidate(snapshotBufferProvider);
      ref.invalidate(validatorSnapshotStreamProvider);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save configuration: $e';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokenAsync = ref.watch(authTokenNotifierProvider);
    final endpointAsync = ref.watch(endpointConfigNotifierProvider);

    // Check if both token and endpoint are configured
    return tokenAsync.when(
      data: (token) {
        return endpointAsync.when(
          data: (endpoint) {
            if (token != null && token.isNotEmpty && endpoint != null) {
              // Both configured - navigate to dashboard
              Future.microtask(() {
                if (!context.mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const DashboardScreen()),
                );
              });
              return const Scaffold(
                backgroundColor: Color(0xFF0A0A0A),
                body: Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.ourValidatorColor),
                ),
              );
            }

            // Load existing values if available
            if (token != null && _tokenController.text.isEmpty) {
              _tokenController.text = token;
            }
            if (endpoint != null) {
              if (_hostController.text.isEmpty) {
                _hostController.text = endpoint.host;
              }
              if (_portController.text == '8080') {
                _portController.text = endpoint.port.toString();
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _useHttps != endpoint.useHttps) {
                  setState(() => _useHttps = endpoint.useHttps);
                }
              });
            }

            return _buildSetupScreen();
          },
          loading: () => const Scaffold(
            backgroundColor: Color(0xFF0A0A0A),
            body: Center(
              child:
                  CircularProgressIndicator(color: AppTheme.ourValidatorColor),
            ),
          ),
          error: (error, stack) {
            // Show storage initialization error to user
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _errorMessage == null) {
                setState(() {
                  _errorMessage = 'Storage initialization failed: $error';
                });
              }
            });
            return _buildSetupScreen();
          },
        );
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.ourValidatorColor),
        ),
      ),
      error: (error, stack) {
        // Show storage initialization error to user
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _errorMessage == null) {
            setState(() {
              _errorMessage = 'Storage initialization failed: $error';
            });
          }
        });
        return _buildSetupScreen();
      },
    );
  }

  Widget _buildSetupScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App title
                const Text(
                  'SLEEPY UI',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF00AAFF),
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4.0,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'VALIDATOR MONITOR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 48),

                // Configuration heading
                Text(
                  'Initial Configuration',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Configure endpoint and authentication',
                  style: TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),

                // Host input
                TextField(
                  controller: _hostController,
                  decoration: InputDecoration(
                    labelText: 'Host Address',
                    hintText: '192.168.1.100',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.dns),
                    errorText: _errorMessage?.contains('Host') == true
                        ? _errorMessage
                        : null,
                  ),
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 16),

                // Port input
                TextField(
                  controller: _portController,
                  decoration: InputDecoration(
                    labelText: 'Port',
                    hintText: '8080',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.settings_ethernet),
                    errorText: _errorMessage?.contains('Port') == true ||
                            _errorMessage?.contains('port') == true
                        ? _errorMessage
                        : null,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 16),

                // HTTPS toggle
                Row(
                  children: [
                    Switch(
                      value: _useHttps,
                      onChanged: (value) {
                        setState(() {
                          _useHttps = value;
                          // Auto-set port: 443 for HTTPS, 80 for HTTP (still editable)
                          _portController.text = value ? '443' : '80';
                        });
                      },
                      activeTrackColor: AppTheme.ourValidatorColor,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Use HTTPS',
                      style: TextStyle(
                        color: Color(0xFFBBBBBB),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Bearer token input
                TextField(
                  controller: _tokenController,
                  obscureText: _isObscured,
                  decoration: InputDecoration(
                    labelText: 'Bearer Token',
                    hintText: 'Enter your API bearer token',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: IconButton(
                      icon: Icon(_isObscured
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _isObscured = !_isObscured),
                    ),
                    errorText: _errorMessage?.contains('token') == true ||
                            _errorMessage?.contains('Token') == true
                        ? _errorMessage
                        : null,
                  ),
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  maxLines: 1,
                ),
                const SizedBox(height: 24),

                // Error message
                if (_errorMessage != null &&
                    !_errorMessage!.contains('Host') &&
                    !_errorMessage!.contains('Port') &&
                    !_errorMessage!.contains('port') &&
                    !_errorMessage!.contains('token') &&
                    !_errorMessage!.contains('Token'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Save button
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveAndProceed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.ourValidatorColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Start Monitoring',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
