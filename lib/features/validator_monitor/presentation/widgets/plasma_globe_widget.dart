import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class PlasmaGlobeWidget extends StatefulWidget {
  const PlasmaGlobeWidget({
    super.key,
    this.boltCount = 7,
    this.baseColor = const Color(0xFF63F2FF),
    this.glowColor = const Color(0xFF2B7BFF),
    this.coreColor = Colors.white,
    this.period = const Duration(milliseconds: 1800),
    this.animationValue,
  });

  final int boltCount;
  final Color baseColor;
  final Color glowColor;
  final Color coreColor;
  final Duration period;
  final double? animationValue; // External animation control

  @override
  State<PlasmaGlobeWidget> createState() => _PlasmaGlobeWidgetState();
}

class _PlasmaGlobeWidgetState extends State<PlasmaGlobeWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<_BoltSeed> _seeds;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.period,
    )..repeat();
    _seeds = _createSeeds(widget.boltCount);
  }

  @override
  void didUpdateWidget(PlasmaGlobeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boltCount != widget.boltCount) {
      _seeds = _createSeeds(widget.boltCount);
    }
    if (oldWidget.period != widget.period) {
      _controller.duration = widget.period;
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_BoltSeed> _createSeeds(int count) {
    final rand = math.Random(42);
    final safeCount = count < 1 ? 1 : count;
    return List.generate(safeCount, (index) {
      return _BoltSeed(
        angle: rand.nextDouble() * math.pi * 2,
        wobble: 0.18 + rand.nextDouble() * 0.25,
        speed: 0.6 + rand.nextDouble() * 1.1,
        lengthFactor: 0.72 + rand.nextDouble() * 0.22,
        phase: rand.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use external animation value if provided, otherwise use internal controller
    final tValue = widget.animationValue ?? _controller.value;
    
    return CustomPaint(
      painter: _PlasmaGlobePainter(
        t: tValue,
        seeds: _seeds,
        baseColor: widget.baseColor,
        glowColor: widget.glowColor,
        coreColor: widget.coreColor,
      ),
    );
  }
}

class _PlasmaGlobePainter extends CustomPainter {
  _PlasmaGlobePainter({
    required this.t,
    required this.seeds,
    required this.baseColor,
    required this.glowColor,
    required this.coreColor,
  });

  final double t;
  final List<_BoltSeed> seeds;
  final Color baseColor;
  final Color glowColor;
  final Color coreColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final coreRadius = radius * 0.18;
    final outerRadius = radius * 0.92;

    // Just the core dot with a white marker line to show rotation
    final corePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [
          Colors.white.withOpacity(0.95),
          coreColor,
          coreColor.withOpacity(0.7),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, corePaint);
    
    // White line marker to show rotation
    final markerPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = coreRadius * 0.15
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center,
      Offset(center.dx, center.dy - coreRadius * 0.8),
      markerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PlasmaGlobePainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.coreColor != coreColor ||
        oldDelegate.seeds != seeds;
  }
}

class _BoltSeed {
  _BoltSeed({
    required this.angle,
    required this.wobble,
    required this.speed,
    required this.lengthFactor,
    required this.phase,
  });

  final double angle;
  final double wobble;
  final double speed;
  final double lengthFactor;
  final double phase;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;