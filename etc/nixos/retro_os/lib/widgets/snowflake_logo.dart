import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Recreates the NixOS-style snowflake from assets/images/logo.svg as six
/// independently-animatable petals plus a scanline core, so each part can
/// spin/scale/fade into place instead of the logo popping in as one image.
class SnowflakeLogo extends StatelessWidget {
  const SnowflakeLogo({super.key, required this.progress, required this.size});

  /// 0.0 -> assembly starts, 1.0 -> fully assembled.
  final Animation<double> progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) => CustomPaint(
        size: Size.square(size),
        painter: _SnowflakePainter(progress.value),
      ),
    );
  }
}

class _SnowflakePainter extends CustomPainter {
  _SnowflakePainter(this.t);

  final double t;

  static const _viewBox = 440.0;
  static const _center = Offset(220, 220);
  static const _sunRect = Rect.fromLTWH(90, 90, 260, 260);
  static const _petalBounds = Rect.fromLTWH(-30, -130, 60, 120);

  static const _petalA = [Color(0xFFFFFFFF), Color(0xFF5A5A5A)];
  static const _petalB = [Color(0xFF8A8A8A), Color(0xFF0A0A0A)];

  static final _petalPath = Path()
    ..moveTo(0, -10)
    ..cubicTo(-30, -50, -26, -100, 0, -130)
    ..cubicTo(26, -100, 30, -50, 0, -10)
    ..close();

  // Fractions of _assemblyDuration (4.5s), staggered so petal 0 is at 50%
  // progress by 0.524s and the last petal finishes right at 3.3s, matching
  // the manually-marked toque timings.
  static const _petalIntervals = [
    [0.0000, 0.2300],
    [0.1000, 0.2800],
    [0.1400, 0.4000],
    [0.1800, 0.5300],
    [0.2100, 0.5500],
    [0.2500, 0.6000],
  ];

  double _local(double start, double end, Curve curve) {
    final raw = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return curve.transform(raw);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewBox;
    canvas.save();
    canvas.scale(scale, scale);

    _paintSun(canvas);
    for (var i = 0; i < 6; i++) {
      _paintPetal(canvas, i);
    }
    _paintCore(canvas);

    canvas.restore();
  }

  // Background disc holds the screen alone from 0 to 0.524s (fraction of the
  // 4.5s assembly), matching the manually-marked toque timings.
  void _paintSun(Canvas canvas) {
    final sunT = _local(0.0, 0.1164, Curves.easeOutCubic);
    if (sunT <= 0) return;

    canvas.save();
    canvas.translate(_center.dx, _center.dy);
    canvas.scale(0.6 + 0.4 * sunT);
    canvas.translate(-_center.dx, -_center.dy);

    canvas.saveLayer(
      const Rect.fromLTWH(0, 0, _viewBox, _viewBox),
      Paint()..color = Colors.white.withValues(alpha: sunT),
    );
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: _center, radius: 130)));

    final gradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white, Color(0xFF6E6E6E)],
    ).createShader(_sunRect);
    canvas.drawRect(_sunRect, Paint()..shader = gradient);

    final stripe = Paint()..color = Colors.black;
    for (var y = 104.0; y <= 324; y += 22) {
      canvas.drawRect(Rect.fromLTWH(90, y, 260, 12), stripe);
    }

    canvas.restore(); // saveLayer
    canvas.restore(); // scale/translate
  }

  void _paintPetal(Canvas canvas, int index) {
    final interval = _petalIntervals[index];
    final petalT = _local(interval[0], interval[1], Curves.easeOutBack);
    if (petalT <= 0) return;

    final angle = index * 60.0;
    final colors = index.isEven ? _petalA : _petalB;
    final opacity = petalT.clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(_center.dx, _center.dy);
    canvas.rotate((angle - 90 * (1 - petalT)) * math.pi / 180);
    canvas.scale(petalT);

    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
    ).createShader(_petalBounds);
    canvas.drawPath(
      _petalPath,
      Paint()
        ..shader = shader
        ..color = Colors.white.withValues(alpha: opacity),
    );
    canvas.restore();
  }

  // Pops in on the last beat of the boot jingle, 2.3s (fraction of the 4.5s
  // assembly). Curves.elasticOut rises to ~full size only ~10% into its
  // interval then just wobbles/settles for the rest, so the window has to
  // be short (150ms) or the pop reads as happening much earlier than 2.3s.
  void _paintCore(Canvas canvas) {
    final coreT = _local(0.5278, 0.8111, Curves.elasticOut);
    if (coreT <= 0) return;

    final radius = 17.0 * coreT.clamp(0.0, 1.3);
    canvas.drawCircle(_center, radius, Paint()..color = Colors.black);
    canvas.drawCircle(
      _center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SnowflakePainter oldDelegate) => oldDelegate.t != t;
}
