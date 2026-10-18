// ============================================
// File: widgets/target_replay_view.dart
// ============================================
// SCATT-style target replay of a single ShotResult trace.
// Shows a scaled target (rings + crosshair) with the shot trace
// drawn on top and a moving dot; play/pause/seek/reset controls.

import 'package:flutter/material.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';
import 'shot_trace_geometry.dart';

const Color _holdColor = Color(0xFFFF4444);
const Color _pressColor = Color(0xFFFFFF44);
const Color _recoilColor = Color(0xFF44FFFF);

class TargetReplayMath {
  const TargetReplayMath._();

  static int pointIndexForProgress(int pointCount, double progress) {
    if (pointCount <= 1) return 0;
    final clamped = progress.clamp(0.0, 1.0);
    return (clamped * (pointCount - 1)).round();
  }

  static double clampProgress(double progress) =>
      progress.clamp(0.0, 1.0).toDouble();
}

class TargetReplayView extends StatefulWidget {
  final ShotResult shot;
  final int shotIndex;
  final Color Function(double score) getScoreColor;
  final bool compact;

  const TargetReplayView({
    super.key,
    required this.shot,
    required this.shotIndex,
    required this.getScoreColor,
    this.compact = false,
  });

  @override
  State<TargetReplayView> createState() => _TargetReplayViewState();
}

class _TargetReplayViewState extends State<TargetReplayView>
    with SingleTickerProviderStateMixin {
  late ShotTracePath _trace;
  late final AnimationController _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _trace = ShotTraceGeometry.fromShot(widget.shot);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
      value: 1.0,
    )..addListener(_onProgress);
  }

  void _onProgress() {
    if (!mounted) return;
    if (_controller.value >= 1.0 && _isPlaying) {
      setState(() => _isPlaying = false);
    } else {
      setState(() {});
    }
  }

  bool get _hasTrace => _trace.points.isNotEmpty;

  void _play() {
    setState(() => _isPlaying = true);
    if (_controller.isCompleted) _controller.value = 0.0;
    _controller.forward();
  }

  void _pause() {
    setState(() => _isPlaying = false);
    _controller.stop();
  }

  void _reset() {
    setState(() => _isPlaying = false);
    _controller.reset();
  }

  void _seek(double value) {
    final wasPlaying = _isPlaying;
    _controller.value = TargetReplayMath.clampProgress(value);
    if (wasPlaying) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant TargetReplayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shot != widget.shot) {
      _trace = ShotTraceGeometry.fromShot(widget.shot);
      _controller.reset();
      _isPlaying = false;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = widget.getScoreColor(widget.shot.totalScore);
    final progress = _controller.value;

    final compact = widget.compact;
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: EdgeInsets.all(compact ? 4 : 16),
        decoration: BoxDecoration(
          color: StsysTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(compact ? 8 : 12),
        ),
        child: Column(
          children: [
            // Target canvas. TRAIN-1 uses the compact form so the replay never
            // competes with the target, shot log, or bottom navigation.
            Container(
              margin: EdgeInsets.fromLTRB(
                compact ? 6 : 12,
                compact ? 6 : 12,
                compact ? 6 : 12,
                0,
              ),
              decoration: BoxDecoration(
                color: StsysTheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: RepaintBoundary(
                  child: SizedBox(
                    height: compact ? 50 : 250,
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          painter: _TargetReplayPainter(
                            trace: _trace,
                            progress: progress,
                            isPlaying: _isPlaying,
                          ),
                          size: Size.infinite,
                        ),
                        if (!_hasTrace)
                          Text(
                            'NO TRACE DATA FOR THIS SHOT',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: StsysTheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Selected shot card
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 8 : 12,
                compact ? 3 : 10,
                compact ? 8 : 12,
                0,
              ),
              child: Row(
                children: [
                  Text(
                    'SHOT ${widget.shotIndex + 1}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: compact ? 9 : 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: StsysTheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.shot.totalScore.toInt().toString(),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: compact ? 14 : 18,
                      fontWeight: FontWeight.w900,
                      color: scoreColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'HOLD ${widget.shot.holdScore.toInt()}'
                      ' · PRESS ${widget.shot.pressScore.toInt()}'
                      ' · RECOIL ${widget.shot.recoilScore.toInt()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: compact ? 8 : 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: StsysTheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Playback controls
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 0 : 4,
                0,
                compact ? 0 : 4,
                compact ? 0 : 4,
              ),
              child: SizedBox(
                height: compact ? 34 : null,
                child: Row(
                  children: [
                    IconButton(
                      constraints: compact
                          ? const BoxConstraints.tightFor(width: 32, height: 32)
                          : null,
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: StsysTheme.primary,
                        size: compact ? 18 : 24,
                      ),
                      onPressed: _hasTrace
                          ? (_isPlaying ? _pause : () => _play())
                          : null,
                      tooltip: _isPlaying ? 'Pause' : 'Play',
                    ),
                    Expanded(
                      child: Slider(
                        value: progress,
                        activeColor: StsysTheme.primary,
                        onChanged: _hasTrace ? _seek : null,
                      ),
                    ),
                    Text(
                      '${(_controller.value * 2.5).toStringAsFixed(1)}s',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: StsysTheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        color: StsysTheme.onSurface.withValues(alpha: 0.5),
                        size: compact ? 16 : 20,
                      ),
                      onPressed: _hasTrace ? _reset : null,
                      tooltip: 'Reset',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetReplayPainter extends CustomPainter {
  final ShotTracePath trace;
  final double progress;
  final bool isPlaying;

  const _TargetReplayPainter({
    required this.trace,
    required this.progress,
    required this.isPlaying,
  });

  static final Paint _ringStroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;

  static final Paint _ringFillHold = Paint()
    ..style = PaintingStyle.fill
    ..color = StsysTheme.surfaceContainerLow;

  static final Paint _ringFillPress = Paint()
    ..style = PaintingStyle.fill
    ..color = StsysTheme.surfaceContainerLowest;

  static final Paint _crosshair = Paint()
    ..color = StsysTheme.outlineVariant.withValues(alpha: 0.3)
    ..strokeWidth = 0.5;

  static final Paint _curve = Paint()
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
    _paintTarget(canvas, size, cx, cy);

    final points = trace.points;
    if (points.isEmpty) return;

    final scaleX = size.width / 2 / trace.maxDeviation;
    final scaleY = size.height / 2 / trace.maxDeviation;

    final visibleEnd = isPlaying
        ? TargetReplayMath.pointIndexForProgress(points.length, progress)
        : points.length - 1;

    _paintPhase(
      canvas,
      points,
      0,
      trace.holdEnd,
      visibleEnd,
      cx,
      cy,
      scaleX,
      scaleY,
      _holdColor,
    );
    _paintPhase(
      canvas,
      points,
      trace.holdEnd,
      trace.pressEnd,
      visibleEnd,
      cx,
      cy,
      scaleX,
      scaleY,
      _pressColor,
    );
    _paintPhase(
      canvas,
      points,
      trace.pressEnd,
      points.length - 1,
      visibleEnd,
      cx,
      cy,
      scaleX,
      scaleY,
      _recoilColor,
    );

    // Center hit marker
    canvas.drawCircle(Offset(cx, cy), 3, _dotFill);
    canvas.drawCircle(Offset(cx, cy), 3, _dotStroke);

    // Moving dot
    final index = TargetReplayMath.pointIndexForProgress(
      points.length,
      progress,
    );
    final point = points[index];
    final px = cx + point.x * scaleX;
    final py = cy + point.y * scaleY;
    canvas.drawCircle(Offset(px, py), 5, _dotFill);
    canvas.drawCircle(Offset(px, py), 5, _dotStroke);
  }

  void _paintTarget(Canvas canvas, Size size, double cx, double cy) {
    // Alternating filled surfaces from outer to inner
    for (var i = 5; i >= 1; i--) {
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: size.width * i / 5,
        height: size.height * i / 5,
      );
      canvas.drawOval(rect, i.isOdd ? _ringFillPress : _ringFillHold);
    }
    _ringStroke.color = StsysTheme.outlineVariant.withValues(alpha: 0.4);
    for (var i = 5; i >= 1; i--) {
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: size.width * i / 5,
        height: size.height * i / 5,
      );
      canvas.drawOval(rect, _ringStroke);
    }
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), _crosshair);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), _crosshair);
  }

  void _paintPhase(
    Canvas canvas,
    List<ShotTracePoint> points,
    int start,
    int end,
    int visibleEnd,
    double cx,
    double cy,
    double scaleX,
    double scaleY,
    Color color,
  ) {
    if (points.isEmpty) return;
    start = start.clamp(0, points.length - 1);
    end = end.clamp(0, points.length - 1);
    if (end <= start) return;
    final drawTo = visibleEnd < end ? visibleEnd : end;
    if (drawTo <= start) return;
    final first = points[start];
    final path = Path()..moveTo(cx + first.x * scaleX, cy + first.y * scaleY);
    for (var i = start + 1; i <= drawTo; i++) {
      final point = points[i];
      path.lineTo(cx + point.x * scaleX, cy + point.y * scaleY);
    }
    _curve.color = color.withValues(alpha: 0.85);
    canvas.drawPath(path, _curve);
  }

  @override
  bool shouldRepaint(covariant _TargetReplayPainter oldDelegate) {
    return !identical(oldDelegate.trace, trace) ||
        oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying;
  }
}
