import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_token_provider.dart';
import '../providers/endpoint_config_provider.dart';
import '../providers/validator_providers.dart';
import '../providers/connection_status_provider.dart';
import '../providers/wake_lock_provider.dart';
import '../../data/datasources/validator_api_client.dart';
import '../widgets/about_widget.dart';
import 'token_gate_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final _tokenController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  bool _isObscured = true;
  bool _isSaving = false;
  bool _useHttps = false;
  bool _isTestingConnection = false;
  String? _endpointValidationError;

  late AnimationController _scrollController;
  List<String> _logLines = [];

  @override
  void initState() {
    super.initState();

    // Initialize scroll animation for background - slower and smoother
    _scrollController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120), // Slower scroll
    )..repeat();

    // Load log file
    _loadLogFile();

    // Load existing token and endpoint config when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tokenAsync = ref.read(authTokenNotifierProvider);
      tokenAsync.whenData((token) {
        if (token != null) {
          _tokenController.text = token;
        }
      });

      final endpointAsync = ref.read(endpointConfigNotifierProvider);
      endpointAsync.whenData((config) {
        if (config != null) {
          _hostController.text = config.host;
          _portController.text = config.port.toString();
          setState(() => _useHttps = config.useHttps);
        }
      });
    });
  }

  Future<void> _loadLogFile() async {
    try {
      final logData = await rootBundle.loadString('assets/background_log.txt');
      setState(() {
        _logLines = logData
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
      });
    } catch (e) {
      debugPrint('Failed to load log file: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tokenController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();

    setState(() => _isSaving = true);

    try {
      await ref.read(authTokenNotifierProvider.notifier).saveToken(token);

      // Clear API client token cache to immediately use new token
      // Without this, old token may be cached for up to 30 seconds
      ref.read(validatorApiClientProvider).clearTokenCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Token saved successfully'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save token: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteToken() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Token'),
        content:
            const Text('Are you sure you want to delete the stored token?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(authTokenNotifierProvider.notifier).deleteToken();
        _tokenController.clear();

        // Invalidate all authenticated providers to force re-check
        ref.invalidate(validatorApiClientProvider);
        ref.invalidate(validatorStreamClientProvider);
        ref.invalidate(serviceHealthProvider);
        ref.invalidate(validatorStatusProvider);
        ref.invalidate(validatorSnapshotStreamProvider);
        ref.invalidate(snapshotBufferProvider);
        ref.read(connectionStatusProvider.notifier).clearError();

        if (mounted) {
          // Navigate to token gate with cleared navigation stack
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const TokenGateScreen()),
            (route) => false, // Clear all routes
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete token: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _saveEndpointConfig() async {
    final host = _hostController.text.trim();
    final portStr = _portController.text.trim();

    if (host.isEmpty) {
      setState(() => _endpointValidationError = 'Host cannot be empty');
      return;
    }

    final port = int.tryParse(portStr);
    if (port == null) {
      setState(() => _endpointValidationError = 'Invalid port number');
      return;
    }

    final config = EndpointConfig(
      host: host,
      port: port,
      useHttps: _useHttps,
    );

    // Validate
    final validationError = config.validate();
    if (validationError != null) {
      setState(() => _endpointValidationError = validationError);
      return;
    }

    setState(() {
      _endpointValidationError = null;
      _isSaving = true;
    });

    try {
      await ref
          .read(endpointConfigNotifierProvider.notifier)
          .updateConfig(config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Endpoint updated to ${config.baseUrl}'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save endpoint: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTestingConnection = true);

    try {
      // Build config from UI state (not persisted state)
      final host = _hostController.text.trim();
      final portStr = _portController.text.trim();
      final port = int.tryParse(portStr);

      if (port == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Invalid port number'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      final tempConfig = EndpointConfig(
        host: host,
        port: port,
        useHttps: _useHttps,
      );

      // Validate before testing
      final validationError = tempConfig.validate();
      if (validationError != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invalid configuration: $validationError'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      // Create temporary client for testing with UI config
      final testClient = ValidatorApiClient(
        getToken: () async {
          final tokenAsync = ref.read(authTokenNotifierProvider);
          return tokenAsync.maybeWhen(
            data: (token) => token,
            orElse: () => null,
          );
        },
        getBaseUrl: () => tempConfig.baseUrl, // Use UI config
      );

      final health = await testClient.getHealth();
      testClient.dispose();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Connection successful to ${tempConfig.baseUrl}: ${health.status}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingConnection = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Stack(
        children: [
          // Matrix-style scrolling background
          if (_logLines.isNotEmpty)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _scrollController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _MatrixBackgroundPainter(
                      logLines: _logLines,
                      progress: _scrollController.value,
                    ),
                  );
                },
              ),
            ),

          // Main content
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Endpoint Configuration Section
                _buildSectionCard(
                  label: 'API ENDPOINT',
                  children: [
                    Text(
                      'Configure connection to validator monitoring backend',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF666666),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Host input
                    _buildTextField(
                      controller: _hostController,
                      label: 'HOST',
                      hint: 'example.com or 192.168.1.100',
                      error: _endpointValidationError,
                    ),
                    const SizedBox(height: 12),

                    // Port and protocol row
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            controller: _portController,
                            label: 'PORT',
                            hint: '8080',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: _buildProtocolToggle(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Preview URL
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Color(0xFF0A0A0A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Color(0xFF00AAFF).withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.link,
                            size: 12,
                            color: Color(0xFF00AAFF).withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_useHttps ? 'https' : 'http'}://${_hostController.text.trim().isEmpty ? 'example.com' : _hostController.text.trim()}:${_portController.text.trim().isEmpty ? '8080' : _portController.text.trim()}',
                              style: TextStyle(
                                color: Color(0xFF00AAFF).withValues(alpha: 0.7),
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Endpoint action buttons
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            label: 'SAVE ENDPOINT',
                            icon: Icons.save,
                            isLoading: _isSaving,
                            onPressed: _isSaving ? null : _saveEndpointConfig,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildActionButton(
                            label: 'TEST',
                            icon: Icons.wifi_find,
                            isLoading: _isTestingConnection,
                            onPressed:
                                _isTestingConnection ? null : _testConnection,
                            isSecondary: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // API Authentication Section
                _buildSectionCard(
                  label: 'API AUTHENTICATION',
                  children: [
                    Text(
                      'Bearer token for API endpoint authentication',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF666666),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Token input
                    _buildTextField(
                      controller: _tokenController,
                      label: 'BEARER TOKEN',
                      hint: 'Enter your API bearer token',
                      obscureText: _isObscured,
                      suffixIcons: [
                        IconButton(
                          icon: Icon(
                            _isObscured
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Color(0xFF00AAFF).withValues(alpha: 0.5),
                            size: 16,
                          ),
                          onPressed: () {
                            setState(() => _isObscured = !_isObscured);
                          },
                          tooltip: 'Toggle visibility',
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            Icons.content_copy,
                            color: Color(0xFF00AAFF).withValues(alpha: 0.5),
                            size: 16,
                          ),
                          onPressed: () {
                            final token = _tokenController.text;
                            if (token.isNotEmpty) {
                              Clipboard.setData(ClipboardData(text: token));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Token copied to clipboard'),
                                  duration: Duration(seconds: 1),
                                  backgroundColor: Color(0xFF00AAFF),
                                ),
                              );
                            }
                          },
                          tooltip: 'Copy token',
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          constraints: BoxConstraints(minWidth: 40),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            label: 'SAVE TOKEN',
                            icon: Icons.save,
                            isLoading: _isSaving,
                            onPressed: _isSaving ? null : _saveToken,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildActionButton(
                            label: 'DELETE',
                            icon: Icons.delete_outline,
                            onPressed: _deleteToken,
                            isDanger: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Token storage info
                    _buildInfoBox(),
                  ],
                ),

                const SizedBox(height: 20),

                // Android wake lock section (conditional)
                if (!kIsWeb && Platform.isAndroid) _buildWakeLockSection(),

                const SizedBox(height: 20),

                // About section
                const AboutWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
      {required String label, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Color(0xFF00AAFF).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00AAFF),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF00AAFF).withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '// $label',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF00AAFF),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? error,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<Widget>? suffixIcons,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Color(0xFF666666),
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: error != null
                  ? Color(0xFFFF3366).withValues(alpha: 0.5)
                  : Color(0xFF00AAFF).withValues(alpha: 0.2),
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            inputFormatters: keyboardType == TextInputType.number
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            style: TextStyle(
              color: Color(0xFFCCCCCC),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Color(0xFF666666),
                fontSize: 11,
              ),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: suffixIcons != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: suffixIcons,
                    )
                  : null,
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error,
            style: TextStyle(
              fontSize: 9,
              color: Color(0xFFFF3366),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProtocolToggle() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Color(0xFF00AAFF).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: !_useHttps
                    ? Color(0xFF00AAFF).withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'HTTP',
                style: TextStyle(
                  color: !_useHttps ? Color(0xFF00AAFF) : Color(0xFF666666),
                  fontWeight: FontWeight.w600,
                  fontSize: 9,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: _useHttps,
              onChanged: (value) => setState(() => _useHttps = value),
              thumbColor: WidgetStateProperty.resolveWith<Color>(
                (states) => states.contains(WidgetState.selected)
                    ? Color(0xFF00AAFF)
                    : Color(0xFF666666),
              ),
              trackColor: WidgetStateProperty.resolveWith<Color>(
                (states) => states.contains(WidgetState.selected)
                    ? Color(0xFF00AAFF).withValues(alpha: 0.3)
                    : Color(0xFF666666).withValues(alpha: 0.2),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _useHttps
                    ? Color(0xFF00AAFF).withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'HTTPS',
                style: TextStyle(
                  color: _useHttps ? Color(0xFF00AAFF) : Color(0xFF666666),
                  fontWeight: FontWeight.w600,
                  fontSize: 9,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool isLoading = false,
    bool isSecondary = false,
    bool isDanger = false,
  }) {
    final Color color = isDanger
        ? Color(0xFFFF3366)
        : isSecondary
            ? Color(0xFF666666)
            : Color(0xFF00AAFF);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            else
              Icon(icon, size: 12, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBox() {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Color(0xFF00AAFF).withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 12,
            color: Color(0xFF00AAFF).withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isMobile
                  ? 'Token stored in secure device keystore'
                  : 'Token stored in plain JSON config file',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF666666),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWakeLockSection() {
    return _buildSectionCard(
      label: 'ANDROID WAKE LOCK',
      children: [
        Text(
          'Keep screen on during monitoring session',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF666666),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Consumer(
          builder: (context, ref, _) {
            final wakeLockEnabled = ref.watch(wakeLockEnabledProvider);
            return InkWell(
              onTap: () {
                ref.read(wakeLockEnabledProvider.notifier).toggle();
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Color(0xFF00AAFF).withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      wakeLockEnabled
                          ? Icons.lightbulb
                          : Icons.lightbulb_outline,
                      size: 14,
                      color: wakeLockEnabled
                          ? Color(0xFF00AAFF)
                          : Color(0xFF666666),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'AUTO-ENABLE WAKE LOCK',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFCCCCCC),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: 0.7,
                      child: Switch(
                        value: wakeLockEnabled,
                        onChanged: (value) {
                          ref.read(wakeLockEnabledProvider.notifier).toggle();
                        },
                        thumbColor: WidgetStateProperty.resolveWith<Color>(
                          (states) => states.contains(WidgetState.selected)
                              ? Color(0xFF00AAFF)
                              : Color(0xFF666666),
                        ),
                        trackColor: WidgetStateProperty.resolveWith<Color>(
                          (states) => states.contains(WidgetState.selected)
                              ? Color(0xFF00AAFF).withValues(alpha: 0.3)
                              : Color(0xFF666666).withValues(alpha: 0.2),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// Matrix-style scrolling background painter
class _MatrixBackgroundPainter extends CustomPainter {
  final List<String> logLines;
  final double progress;

  _MatrixBackgroundPainter({
    required this.logLines,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (logLines.isEmpty) return;

    const fontSize = 9.0;
    const lineHeight = 14.0;
    final linesPerScreen = (size.height / lineHeight).ceil() + 2;

    // Total content height for smooth looping
    final totalContentHeight = logLines.length * lineHeight;

    // Continuous smooth scroll offset (moves upward)
    final pixelOffset = progress * totalContentHeight;

    // Draw lines from top to bottom
    for (var i = 0; i < linesPerScreen; i++) {
      // Calculate Y position (scrolling upward means decreasing Y)
      final baseY = (i * lineHeight) - (pixelOffset % totalContentHeight);

      // Wrap around when lines go off screen
      final y = baseY < -lineHeight ? baseY + totalContentHeight : baseY;

      // Skip if outside visible area
      if (y > size.height + lineHeight) continue;

      // Determine which line to show
      final virtualIndex = ((pixelOffset / lineHeight).floor() + i);
      final lineIndex = virtualIndex % logLines.length;
      final line = logLines[lineIndex];

      // Calculate opacity with fade at top and bottom
      double opacity = 0.20;

      if (y < size.height * 0.25) {
        // Fade in from top
        opacity *= (y / (size.height * 0.25)).clamp(0.0, 1.0);
      } else if (y > size.height * 0.75) {
        // Fade out at bottom
        final fadeStart = size.height * 0.75;
        final fadeRange = size.height * 0.25;
        opacity *= (1.0 - ((y - fadeStart) / fadeRange)).clamp(0.0, 1.0);
      }

      if (opacity < 0.01) continue;

      // Draw text
      final textSpan = TextSpan(
        text: line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          color: Color(0xFF00FF41).withValues(alpha: opacity),
          fontWeight: FontWeight.w400,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );

      textPainter.layout(maxWidth: size.width - 16);
      textPainter.paint(canvas, Offset(8, y));
    }
  }

  @override
  bool shouldRepaint(_MatrixBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
