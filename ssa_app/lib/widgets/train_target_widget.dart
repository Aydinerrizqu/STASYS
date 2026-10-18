import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/data_models.dart';
import '../models/train_preset.dart';
import 'shot_trace_geometry.dart';
import 'target_replay_view.dart';

enum TrainTargetDisplay { start, activeTrace, seriesScatter }

const _holdColor = Color(0xFFFF4444);
const _pressColor = Color(0xFFFFFF44);
const _recoilColor = Color(0xFF44FFFF);

/// Responsive target surface shared by the ready (TRAIN-0) and active (TRAIN-1) states.
class TrainTargetWidget extends StatelessWidget {
  final bool isActive;
  final double? latestScore;
  final List<ShotResult>? sessionShots;
  final TrainPreset? preset;
  final TrainingMode? trainingMode;
  final VoidCallback? onStart;
  final TrainTargetDisplay? display;
  final ShotResult? selectedShot;
  final double replayProgress;
  final List<ShotResult> scatterShots;

  const TrainTargetWidget({
    super.key,
    required this.isActive,
    this.latestScore,
    this.sessionShots,
    this.preset,
    this.trainingMode,
    this.onStart,
    this.display,
    this.selectedShot,
    this.replayProgress = 1.0,
    this.scatterShots = const [],
  });

  TrainTargetDisplay get _display =>
      display ??
      (isActive ? TrainTargetDisplay.activeTrace : TrainTargetDisplay.start);

  /// Deterministic marker coordinates for one scatter shot in a canvas of [size].
  /// Uses the shot's own trace endpoint with the same scaling as the live
  /// active-trace painting so live impact and scatter markers coincide exactly.
  static List<Offset> markerPositions(List<ShotResult> shots, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide * 0.40;
    return shots
        .map((shot) => _markerOffset(shot, center, maxR, size))
        .toList(growable: false);
  }

  static Offset _markerOffset(
    ShotResult shot,
    Offset center,
    double maxR,
    Size size,
  ) {
    final trace = ShotTraceGeometry.fromShot(shot);
    if (trace.points.isNotEmpty) {
      final scaleX = size.width / 2 / trace.maxDeviation;
      final scaleY = size.height / 2 / trace.maxDeviation;
      final endpoint = trace.points.last;
      return Offset(
        center.dx + endpoint.x * scaleX,
        center.dy + endpoint.y * scaleY,
      );
    }
    // Fallback for shots without trace data.
    final norm = (shot.totalScore / 100).clamp(0.0, 1.0);
    final radius = maxR * (1 - norm) * .72;
    final angle = (shot.timestamp.millisecondsSinceEpoch % 360) * math.pi / 180;
    return Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = _display;
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: mode == TrainTargetDisplay.start
            ? _StartTarget(key: const ValueKey('start'), onStart: onStart)
            : _TargetCanvas(
                key: ValueKey(mode),
                mode: mode,
                latestScore: latestScore,
                preset: preset,
                trainingMode: trainingMode,
                selectedShot: selectedShot,
                replayProgress: replayProgress,
                scatterShots: scatterShots,
              ),
      ),
    );
  }
}

class _StartTarget extends StatelessWidget {
  final VoidCallback? onStart;
  const _StartTarget({super.key, this.onStart});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: 'Start training series',
        child: GestureDetector(
          onTap: onStart,
          child: Container(
            width: 178,
            height: 178,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF10171C),
              border: Border.all(color: const Color(0xFF00E5FF), width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x3300E5FF), blurRadius: 24),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gps_fixed, color: Color(0xFF00E5FF), size: 42),
                SizedBox(height: 10),
                Text(
                  'START',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Color(0xFF00E5FF),
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

class _TargetCanvas extends StatelessWidget {
  final TrainTargetDisplay mode;
  final double? latestScore;
  final TrainPreset? preset;
  final TrainingMode? trainingMode;
  final ShotResult? selectedShot;
  final double replayProgress;
  final List<ShotResult> scatterShots;

  const _TargetCanvas({
    super.key,
    required this.mode,
    this.latestScore,
    this.preset,
    this.trainingMode,
    this.selectedShot,
    required this.replayProgress,
    required this.scatterShots,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TargetPainter(
      mode: mode,
      latestScore: latestScore,
      selectedShot: selectedShot,
      replayProgress: replayProgress,
      scatterShots: scatterShots,
    ),
    child: const SizedBox.expand(),
  );
}

class _TargetPainter extends CustomPainter {
  final TrainTargetDisplay mode;
  final double? latestScore;
  final ShotResult? selectedShot;
  final double replayProgress;
  final List<ShotResult> scatterShots;

  _TargetPainter({
    required this.mode,
    this.latestScore,
    this.selectedShot,
    required this.replayProgress,
    required this.scatterShots,
  });

  static const _bullColor = Color(0xFF000000);
  static const _outerRingColor = Color(0xFF1A1D21);
  static const _innerRingColor = Colors.white;
  static const _crosshairColor = Color(0xFF22272C);

  static final List<TextPainter> _ringLabels = List.generate(10, (index) {
    final ringNumber = index + 1;
    final lightLabel = ringNumber >= 7;
    final painter = TextPainter(
      text: TextSpan(
        text: '$ringNumber',
        style: TextStyle(
          color: lightLabel ? Colors.white : _outerRingColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    return painter;
  }, growable: false);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide * 0.40;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= 10; i++) {
      final ringNumber = 11 - i;
      ring.color = ringNumber <= 6 ? _outerRingColor : _innerRingColor;
      canvas.drawCircle(center, maxR * i / 10, ring);
    }

    canvas.drawCircle(center, maxR * 0.4, Paint()..color = _bullColor);

    // Redraw the white scoring rings over the bull so all ten rings remain
    // visible against the black disc.
    for (var i = 1; i <= 4; i++) {
      ring.color = _innerRingColor;
      canvas.drawCircle(center, maxR * i / 10, ring);
    }

    final crosshair = Paint()
      ..color = _crosshairColor.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    const dashLength = 4.0;
    const gapLength = 4.0;
    for (var offset = -maxR; offset < maxR; offset += dashLength + gapLength) {
      final endX = math.min(offset + dashLength, maxR);
      final startX = math.max(offset, -maxR);
      canvas.drawLine(
        Offset(center.dx + startX, center.dy),
        Offset(center.dx + endX, center.dy),
        crosshair,
      );
      final endY = math.min(offset + dashLength, maxR);
      final startY = math.max(offset, -maxR);
      canvas.drawLine(
        Offset(center.dx, center.dy + startY),
        Offset(center.dx, center.dy + endY),
        crosshair,
      );
    }

    for (var i = 1; i <= 10; i++) {
      final ringNumber = 11 - i;
      final label = _ringLabels[ringNumber - 1];
      final fontSize = maxR * 0.06;
      // Labels are cached at a nominal size; scale their canvas placement to
      // the requested target dimensions without allocating TextPainters.
      final scale = fontSize / 12;
      canvas.save();
      canvas.translate(center.dx, center.dy - maxR * i / 10 + 1);
      canvas.scale(scale);
      label.paint(canvas, Offset(-label.width / 2, 0));
      canvas.restore();
    }

    canvas.drawCircle(center, 2, Paint()..color = Colors.white);

    if (mode == TrainTargetDisplay.activeTrace) {
      final shot = selectedShot;
      if (shot != null) {
        _paintTrace(canvas, size, ShotTraceGeometry.fromShot(shot));
        // Impact marker uses the same deterministic placement as scatter so
        // a shot's dot is at an identical position live and after END SERIES.
        final impactOffset = TrainTargetWidget._markerOffset(
          shot,
          center,
          maxR,
          size,
        );
        canvas.drawCircle(
          impactOffset,
          5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          impactOffset,
          5,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    } else if (mode == TrainTargetDisplay.seriesScatter) {
      final marker = Paint()..color = const Color(0xFFFF4D5A);
      for (final shot in scatterShots) {
        canvas.drawCircle(
          TrainTargetWidget._markerOffset(shot, center, maxR, size),
          5.5,
          marker,
        );
      }
    }
  }

  void _paintTrace(Canvas canvas, Size size, ShotTracePath trace) {
    final points = trace.points;
    if (points.isEmpty) return;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final scaleX = size.width / 2 / trace.maxDeviation;
    final scaleY = size.height / 2 / trace.maxDeviation;
    // Replay progress clips every phase at the visible point index so the
    // trace draws progressively as playback advances.
    final visibleEnd = TargetReplayMath.pointIndexForProgress(
      points.length,
      replayProgress,
    );
    _paintPhase(
      canvas,
      points,
      0,
      math.min(trace.holdEnd, visibleEnd),
      centerX,
      centerY,
      scaleX,
      scaleY,
      _holdColor,
    );
    _paintPhase(
      canvas,
      points,
      trace.holdEnd,
      math.min(trace.pressEnd, visibleEnd),
      centerX,
      centerY,
      scaleX,
      scaleY,
      _pressColor,
    );
    _paintPhase(
      canvas,
      points,
      trace.pressEnd,
      math.min(points.length - 1, visibleEnd),
      centerX,
      centerY,
      scaleX,
      scaleY,
      _recoilColor,
    );
    // Moving playback dot (same styling as TargetReplayView) while partial.
    if (replayProgress < 1.0) {
      final point = points[visibleEnd];
      final position = Offset(
        centerX + point.x * scaleX,
        centerY + point.y * scaleY,
      );
      canvas.drawCircle(
        position,
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        position,
        5,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _paintPhase(
    Canvas canvas,
    List<ShotTracePoint> points,
    int start,
    int end,
    double centerX,
    double centerY,
    double scaleX,
    double scaleY,
    Color color,
  ) {
    if (points.isEmpty) return;
    start = start.clamp(0, points.length - 1);
    end = end.clamp(0, points.length - 1);
    if (end <= start) return;
    final first = points[start];
    final path = Path()
      ..moveTo(centerX + first.x * scaleX, centerY + first.y * scaleY);
    for (var i = start + 1; i <= end; i++) {
      final point = points[i];
      path.lineTo(centerX + point.x * scaleX, centerY + point.y * scaleY);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TargetPainter old) =>
      old.mode != mode ||
      old.latestScore != latestScore ||
      old.selectedShot != selectedShot ||
      old.replayProgress != replayProgress ||
      !identical(old.scatterShots, scatterShots);
}
