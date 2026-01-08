import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutWidget extends StatefulWidget {
  const AboutWidget({super.key});

  @override
  State<AboutWidget> createState() => _AboutWidgetState();
}

class _AboutWidgetState extends State<AboutWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHolographicCard(),
        const SizedBox(height: 16),
        _buildNeonLinksGrid(),
      ],
    );
  }

  Widget _buildHolographicCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          width: 1,
          color: const Color(0xFF00AAFF).withValues(alpha: 0.2),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            _buildScanLines(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedBuilder(
                        animation: _glowController,
                        builder: (context, child) {
                          final pulse = 0.3 + (_glowController.value * 0.2);
                          return Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00AAFF),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00AAFF)
                                      .withValues(alpha: pulse),
                                  blurRadius: 6 + (_glowController.value * 4),
                                  spreadRadius: 1 + (_glowController.value * 1),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SLEEPY UI',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF00AAFF),
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'v1.0.0 // GENESIS',
                            style: TextStyle(
                              fontSize: 9,
                              color: const Color(0xFF666666),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDataBlock(
                    'MISSION',
                    'Engineering Emergency Knife For Real-Time Monitoring',
                  ),
                  const SizedBox(height: 10),
                  _buildDataBlock(
                    'CAPABILITY',
                    'Sub-3-second incident response • Real-time SSE stream • Cycle tracking',
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 1,
                    color: const Color(0xFF00AAFF).withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildCompactEntity(
                            'ORGANIZATION', 'ART3MIS.CLOUD'),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: const Color(0xFF00AAFF).withValues(alpha: 0.15),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      Expanded(
                        child:
                            _buildCompactEntity('ENGINEER', 'Matsuro Hadouken'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactEntity(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            color: const Color(0xFF666666),
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFFCCCCCC),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildScanLines() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return Positioned.fill(
          child: CustomPaint(
            painter: _ScanLinePainter(_glowController.value),
          ),
        );
      },
    );
  }

  Widget _buildDataBlock(String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '// $label',
          style: TextStyle(
            fontSize: 9,
            color: const Color(0xFF00AAFF).withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFFCCCCCC),
            height: 1.4,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildNeonLinksGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildMinimalLinkButton(
            icon: Icons.language_rounded,
            label: 'PORTAL',
            sublabel: 'art3mis.cloud',
            url: 'https://art3mis.cloud',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMinimalLinkButton(
            icon: Icons.code_rounded,
            label: 'REPO',
            sublabel: 'GitHub',
            url: 'https://github.com/a3mc/sleepy_ui',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMinimalLinkButton(
            icon: Icons.email_rounded,
            label: 'CONTACT',
            sublabel: 'team@art3mis.cloud',
            url: 'mailto:team@art3mis.cloud',
          ),
        ),
      ],
    );
  }

  Widget _buildMinimalLinkButton({
    required IconData icon,
    required String label,
    required String sublabel,
    required String url,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: () async {
            // Capture scaffold messenger before async gap
            final scaffoldMessenger = ScaffoldMessenger.of(context);

            try {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                // URL cannot be launched (no handler available)
                if (context.mounted) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content:
                          Text('Cannot open link - no application available'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }
            } catch (e) {
              // Handle platform channel errors or malformed URLs
              if (context.mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to open link: ${e.toString()}'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            }
          },
          hoverColor: const Color(0xFF00AAFF).withValues(alpha: 0.05),
          splashColor: const Color(0xFF00AAFF).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: const Color(0xFF00AAFF).withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: const Color(0xFF00AAFF),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: const Color(0xFF00AAFF),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  sublabel,
                  style: TextStyle(
                    fontSize: 9,
                    color: const Color(0xFF666666),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanLinePainter extends CustomPainter {
  final double progress;

  _ScanLinePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle horizontal scan lines
    final paint = Paint()
      ..color = const Color(0xFF00AAFF).withValues(alpha: 0.02)
      ..strokeWidth = 1;

    for (var i = 0; i < size.height; i += 3) {
      canvas.drawLine(
        Offset(0, i.toDouble()),
        Offset(size.width, i.toDouble()),
        paint,
      );
    }

    // Very subtle moving scan line
    final scanY = (progress * size.height);
    final scanPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF00AAFF).withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, scanY - 30, size.width, 60));

    canvas.drawRect(
      Rect.fromLTWH(0, scanY - 30, size.width, 60),
      scanPaint,
    );
  }

  @override
  bool shouldRepaint(_ScanLinePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
