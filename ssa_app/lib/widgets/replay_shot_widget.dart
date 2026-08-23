// ============================================
// File: widgets/replay_shot_widget.dart
// ============================================
// Animated replay of a single ShotResult barrel trace.
// Shows hold/press/recoil segments with a moving dot.
// Press PLAY to animate, STOP to reset.

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';
import 'shot_trace_geometry.dart';

const Color _holdColor = Color(0xFFFF4444);
const Color _pressColor = Color(0xFFFFFF44);
const Color _recoilColor = Color(0xFF44FFFF);

class ReplayShotWidget extends StatefulWidget {
  final ShotResult shot;
  final int shotIndex;
  final Color Function(double) getScoreColor;

  const ReplayShotWidget({
    super.key,
    required this.shot,
    required this.shotIndex,
    required this.getScoreColor,
  });

  @override
  State<ReplayShotWidget> createState() => _ReplayShotWidgetState();
}

class _ReplayShotWidgetState extends State<ReplayShotWidget>
    with TickerProviderStateMixin {
  late final ShotTracePath _trace;
  late final AnimationController _animCtrl;
  Timer? _timer;
  int _currentSegIdx = 0; // 0=hold, 1=press, 2=recoil
  double _segProgress = 0.0;
  double _dotX = 0.0, _dotY = 0.0;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _trace = ShotTraceGeometry.fromShot(widget.shot);
    _animCtrl = AnimationController(vsync: this, duration: _totalDuration);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  Duration get _totalDuration => const Duration(milliseconds: 2500);

  List<double> get _holdX => widget.shot.holdX ?? [];
  List<double> get _holdY => widget.shot.holdY ?? [];
  List<double> get _pressX => widget.shot.pressX ?? [];
  List<double> get _pressY => widget.shot.pressY ?? [];
  List<double> get _recoilX => widget.shot.recoilX ?? [];
  List<double> get _recoilY => widget.shot.recoilY ?? [];

  int get _totalPoints => _trace.points.length;
  void _play() {
    setState(() => _isPlaying = true);
    _animCtrl.forward(from: 0.0);
    _startTimer();
  }

  void _stop() {
    _timer?.cancel();
    _animCtrl.stop();
    setState(() {
      _isPlaying = false;
      _segProgress = 0.0;
      _currentSegIdx = 0;
      _dotX = 0.0;
      _dotY = 0.0;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    const interval = Duration(milliseconds: 16);
    _timer = Timer.periodic(interval, (_) {
      if (!_isPlaying) return;
      final totalPts = _totalPoints;
      if (totalPts == 0) return;

      final currentPt = (_animCtrl.value * (totalPts - 1)).round().clamp(
        0,
        totalPts - 1,
      );
      final point = _trace.points[currentPt];
      _currentSegIdx = switch (_trace.phaseForPoint(currentPt)) {
        ShotTracePhase.hold => 0,
        ShotTracePhase.press => 1,
        ShotTracePhase.recoil => 2,
      };
      _segProgress = totalPts <= 1 ? 1.0 : currentPt / (totalPts - 1);

      setState(() {
        _dotX = point.x;
        _dotY = point.y;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.getScoreColor(widget.shot.totalScore);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header: score + play controls
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      widget.shot.totalScore.toInt().toString(),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SHOT #${widget.shotIndex + 1} — REPLAY'.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: StsysTheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _phaseDot('H', _holdColor, _holdX.length > 1),
                          const SizedBox(width: 6),
                          _phaseDot('P', _pressColor, _pressX.length > 1),
                          const SizedBox(width: 6),
                          _phaseDot('R', _recoilColor, _recoilX.length > 1),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.stop : Icons.play_arrow,
                        color: StsysTheme.secondary,
                        size: 24,
                      ),
                      onPressed: _isPlaying ? _stop : _play,
                      tooltip: _isPlaying ? 'Stop' : 'Play',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        color: StsysTheme.onSurface.withValues(alpha: 0.5),
                        size: 20,
                      ),
                      onPressed: () => _stop(),
                      tooltip: 'Reset',
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Trace canvas
          SizedBox(
            height: 140,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: StsysTheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _ReplayPainter(
                      shot: widget.shot,
                      trace: _trace,
                      dotX: _dotX,
                      dotY: _dotY,
                      currentSegIdx: _currentSegIdx,
                      segProgress: _segProgress,
                      isPlaying: _isPlaying,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          // Phase progress bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: _isPlaying
                      ? _animCtrl.value
                      : (_dotX != 0.0 || _dotY != 0.0 ? 1.0 : 0.0),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: StsysTheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    color.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _phaseLabel(
                      'HOLD',
                      _holdX.length,
                      _holdColor,
                      _currentSegIdx == 0 && _isPlaying,
                    ),
                    _phaseLabel(
                      'PRESS',
                      _pressX.length,
                      _pressColor,
                      _currentSegIdx == 1 && _isPlaying,
                    ),
                    _phaseLabel(
                      'RECOIL',
                      _recoilX.length,
                      _recoilColor,
                      _currentSegIdx == 2 && _isPlaying,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseDot(String label, Color color, bool hasData) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: hasData ? 0.25 : 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: hasData ? 0.7 : 0.2)),
      ),
      child: Text(
        '$label:${hasData ? '✓' : '—'}',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color.withValues(alpha: hasData ? 1.0 : 0.3),
        ),
      ),
    );
  }

  Widget _phaseLabel(String label, int count, Color color, bool active) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: active ? 0.25 : 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$label ($count)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 7,
            fontWeight: active ? FontWeight.w900 : FontWeight.w600,
            letterSpacing: 0.5,
            color: color.withValues(alpha: active ? 1.0 : 0.5),
          ),
        ),
      ),
    );
  }
}

class _ReplayPainter extends CustomPainter {
  final ShotResult shot;
  final ShotTracePath trace;
  final double dotX, dotY;
  final int currentSegIdx;
  final double segProgress;
  final bool isPlaying;

  const _ReplayPainter({
    required this.shot,
    required this.trace,
    required this.dotX,
    required this.dotY,
    required this.currentSegIdx,
    required this.segProgress,
    required this.isPlaying,
  });

  static final Paint _gridPaint = Paint()
    ..color = const Color(0xFF6B7280).withValues(alpha: 0.3)
    ..strokeWidth = 0.5;

  static final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;

  static final Paint _curvePaint = Paint()
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static final Paint _dotFill = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static final Paint _dotStroke = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final maxDev = trace.maxDeviation;

    final scaleX = size.width / 2 / maxDev;
    final scaleY = size.height / 2 / maxDev;

    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), _gridPaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), _gridPaint);

    _ringPaint.color = const Color(0xFF6B7280).withValues(alpha: 0.15);
    for (final r in [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: r * maxDev * scaleX * 2,
          height: r * maxDev * scaleY * 2,
        ),
        _ringPaint,
      );
    }

    // Draw only the completed/active segment up to current progress
    _drawSegment(
      canvas,
      trace,
      0,
      trace.holdEnd,
      cx,
      cy,
      scaleX,
      scaleY,
      _holdColor,
      currentSegIdx > 0 ? 1.0 : segProgress,
      currentSegIdx > 0 || (isPlaying && currentSegIdx == 0),
    );
    _drawSegment(
      canvas,
      trace,
      trace.holdEnd,
      trace.pressEnd,
      cx,
      cy,
      scaleX,
      scaleY,
      _pressColor,
      currentSegIdx > 1 ? 1.0 : segProgress,
      currentSegIdx > 1 || (isPlaying && currentSegIdx == 1),
    );
    _drawSegment(
      canvas,
      trace,
      trace.pressEnd,
      trace.points.length - 1,
      cx,
      cy,
      scaleX,
      scaleY,
      _recoilColor,
      segProgress,
      isPlaying && currentSegIdx == 2,
    );

    // Draw the dot at current position
    if (dotX != 0.0 || dotY != 0.0 || isPlaying) {
      final px = cx + dotX * scaleX;
      final py = cy + dotY * scaleY;
      canvas.drawCircle(Offset(px, py), 5, _dotFill);
      canvas.drawCircle(Offset(px, py), 5, _dotStroke);
    }

    // Center hit marker
    canvas.drawCircle(Offset(cx, cy), 3, _dotFill);
    canvas.drawCircle(Offset(cx, cy), 3, _dotStroke);
  }

  void _drawSegment(
    Canvas canvas,
    ShotTracePath trace,
    int start,
    int end,
    double cx,
    double cy,
    double sx,
    double sy,
    Color color,
    double progress,
    bool visible,
  ) {
    if (!visible || trace.points.length < 2 || end <= start) return;
    final visibleEnd = start + ((end - start) * progress).round();
    final first = trace.points[start.clamp(0, trace.points.length - 1)];
    final path = Path()..moveTo(cx + first.x * sx, cy + first.y * sy);
    for (var i = start + 1; i <= visibleEnd && i < trace.points.length; i++) {
      final point = trace.points[i];
      path.lineTo(cx + point.x * sx, cy + point.y * sy);
    }
    _curvePaint.color = color.withValues(alpha: 0.85);
    canvas.drawPath(path, _curvePaint);
  }

  @override
  bool shouldRepaint(covariant _ReplayPainter oldDelegate) {
    return oldDelegate.shot != shot ||
        oldDelegate.dotX != dotX ||
        oldDelegate.dotY != dotY ||
        oldDelegate.currentSegIdx != currentSegIdx ||
        oldDelegate.segProgress != segProgress ||
        oldDelegate.isPlaying != isPlaying;
  }
}
