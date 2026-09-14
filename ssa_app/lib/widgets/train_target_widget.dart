import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/data_models.dart';

/// Renders the center target canvas for TRAIN-0 / TRAIN-1 views.
/// Shows START placeholder when no series is active, scoring rings when active.
class TrainTargetWidget extends StatelessWidget {
  final bool isActive;
  final double? latestScore;
  final List<ShotResult>? sessionShots;

  const TrainTargetWidget({
    super.key,
    required this.isActive,
    this.latestScore,
    this.sessionShots,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: isActive
            ? _ActiveTarget(
                key: const ValueKey('active'),
                latestScore: latestScore,
                shots: sessionShots,
              )
            : const _StartPlaceholder(key: ValueKey('start')),
      ),
    );
  }
}

class _StartPlaceholder extends StatelessWidget {
  const _StartPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0C0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F242C)),
      ),
      child: const Center(
        child: Text(
          'START',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            color: Color(0xFF00D8FF),
          ),
        ),
      ),
    );
  }
}

class _ActiveTarget extends StatelessWidget {
  final double? latestScore;
  final List<ShotResult>? shots;

  const _ActiveTarget({super.key, this.latestScore, this.shots});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0C0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F242C)),
      ),
      child: CustomPaint(
        painter: _TargetPainter(latestScore: latestScore, shots: shots),
      ),
    );
  }
}

class _TargetPainter extends CustomPainter {
  final double? latestScore;
  final List<ShotResult>? shots;

  _TargetPainter({this.latestScore, this.shots});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide / 2 - 16;

    // Scoring rings (outer → inner)
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      ringPaint.color = const Color(0xFF1F242C);
      canvas.drawCircle(center, maxR * (5 - i) / 5, ringPaint);
    }

    // Crosshair
    final gridPaint = Paint()
      ..color = const Color(0xFF1F242C)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(center.dx - maxR, center.dy),
      Offset(center.dx + maxR, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - maxR),
      Offset(center.dx, center.dy + maxR),
      gridPaint,
    );

    // Shot markers
    if (shots != null && shots!.isNotEmpty) {
      final markerPaint = Paint()..style = PaintingStyle.fill;
      for (final s in shots!) {
        // Place shots in a stable layout based on score
        final norm = (s.totalScore / 100).clamp(0.0, 1.0);
        final r = maxR * (1 - norm) * 0.8;
        final angle =
            (s.timestamp.millisecondsSinceEpoch % 360) * 3.14159 / 180;
        final dx = center.dx + r * math.cos(angle);
        final dy = center.dy + r * math.sin(angle);

        markerPaint.color = const Color(0xFF00D8FF).withValues(alpha: 0.8);
        canvas.drawCircle(Offset(dx, dy), 4, markerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TargetPainter old) =>
      old.latestScore != latestScore || old.shots != shots;
}
