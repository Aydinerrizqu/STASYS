// ============================================
// File: widgets/muzzle_trace_widget.dart
// MantisX-Style Real-time Muzzle Trace — Dark Theme STSYS
// ============================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_data_provider.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';

// Phase colors (MantisX style — STSYS palette)
const Color _holdColor = Color(0xFFFFB693);    // STSYS primary — orange
const Color _pressColor = Color(0xFF8BCEFF);   // STSYS secondary — blue
const Color _recoilColor = Color(0xFFFFB4AB);  // STSYS error — coral

// Scoring ring colors (MantisX zones)
const Color _eliteColor = Color(0xFFFFD700);    // Gold
const Color _expertColor = Color(0xFF4CAF50);   // Green
const Color _advancedColor = Color(0xFF2196F3); // Blue
const Color _intermediateColor = Color(0xFFFF9800); // Orange
const Color _beginnerColor = Color(0xFFF44336); // Red

class MuzzleTraceWidget extends StatefulWidget {
  final double zoom;
  final bool showGrid;

  const MuzzleTraceWidget({
    super.key,
    this.zoom = 0.05,
    this.showGrid = true,
  });

  @override
  State<MuzzleTraceWidget> createState() => _MuzzleTraceWidgetState();
}

class _MuzzleTraceWidgetState extends State<MuzzleTraceWidget> {
  // Integrated gyro trace — resets on each new shot
  double _currX = 0.0;
  double _currY = 0.0;

  final List<_TracePoint> _recentTrace = [];
  // Extended window: 2s tail (was 500ms) for better visibility
  static const int _maxTracePoints = 400;
  static const int _traceWindowMs = 2000;

  // Velocity tracking for dynamic dot sizing
  static const double _liveDotSensitivity = 0.08; // increased from 0.05
  double _prevAccelX = 0.0;
  double _prevAccelY = 0.0;
  double _liveSpeed = 0.0;

  // Phase coloring
  bool _isHold = true;
  bool _isPress = false;
  bool _isRecoil = false;

  // Shot display
  ShotResult? _lastShot;
  int _shotCount = 0;

  // Timer-based phase transitions (replaces Future.delayed closures)
  Timer? _phaseResetTimer;

  Color get _currentPhaseColor {
    if (_isRecoil) return _recoilColor;
    if (_isPress) return _pressColor;
    return _holdColor;
  }

  @override
  void dispose() {
    _phaseResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, provider, child) {
        _processLatestData(provider);

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Header row
              Row(
                children: [
                  // Phase indicator dots
                  _PhaseDot('H', _holdColor, _isHold),
                  _PhaseDot('P', _pressColor, _isPress),
                  _PhaseDot('R', _recoilColor, _isRecoil),
                  const Spacer(),
                  // Shot counter badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: StsysTheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_shotCount shots',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: StsysTheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // XY Plot — dark background
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: StsysTheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: StsysTheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _MuzzleTracePainter(
                          trace: _recentTrace,
                          currentX: _currX,
                          currentY: _currY,
                          zoom: widget.zoom,
                          showGrid: widget.showGrid,
                          phaseColor: _currentPhaseColor,
                          liveSpeed: _liveSpeed,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Score display row
              if (_lastShot != null) _buildScoreRow(_lastShot!),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScoreRow(ShotResult shot) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: StsysTheme.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _scoreChip('HOLD', shot.holdScore, _holdColor),
          Container(width: 1, height: 28, color: StsysTheme.outlineVariant.withValues(alpha: 0.2)),
          _scoreChip('PRESS', shot.pressScore, _pressColor),
          Container(width: 1, height: 28, color: StsysTheme.outlineVariant.withValues(alpha: 0.2)),
          _scoreChip('RECOIL', shot.recoilScore, _recoilColor),
        ],
      ),
    );
  }

  Widget _scoreChip(String label, double score, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 8,
            letterSpacing: 1,
            color: color.withValues(alpha: 0.7),
          ),
        ),
        Text(
          score.toInt().toString(),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  void _processLatestData(SensorDataProvider provider) {
    if (provider.accelXData.isEmpty) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // --- LIVE DOT: ACCELEROMETER with velocity tracking ---
    final ax = provider.accelXData.last.value;
    final ay = provider.accelYData.last.value;
    _currX = ax * _liveDotSensitivity;
    _currY = ay * _liveDotSensitivity;

    // Compute speed for dynamic dot sizing
    final dax = ax - _prevAccelX;
    final day = ay - _prevAccelY;
    _liveSpeed = _sqrt(dax * dax + day * day);
    _prevAccelX = ax;
    _prevAccelY = ay;

    // --- TRACE PATH: Extended 2s gyro integration with opacity fade ---
    final windowStart = nowMs - _traceWindowMs;
    final data = provider.gyroXData;
    int startIdx = 0;
    for (int i = data.length - 1; i >= 0; i--) {
      if (data[i].timestamp >= windowStart) {
        startIdx = i;
      } else {
        break;
      }
    }

    _recentTrace.clear();
    double traceX = 0.0, traceY = 0.0;
    for (int i = startIdx; i < data.length; i++) {
      final gx = data[i].value;
      final gz = provider.gyroZData[i].value;
      final ts = data[i].timestamp;

      const dt = 0.01;
      traceX += (-gz) * dt;
      traceY += (-gx) * dt;

      final phase = _isRecoil
          ? TracePhase.recoil
          : (_isPress ? TracePhase.press : TracePhase.hold);
      _recentTrace.add(_TracePoint(traceX, traceY, ts, phase));
    }

    // Trim from front to maintain max size
    if (_recentTrace.length > _maxTracePoints) {
      _recentTrace.removeRange(0, _recentTrace.length - _maxTracePoints);
    }

    // Phase detection from shot state
    if (_lastShot != null) {
      _isHold = false;
      _isPress = false;
      _isRecoil = true;
      _phaseResetTimer?.cancel();
      _phaseResetTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _isRecoil = false;
            _isHold = true;
          });
        }
      });
    }

    // New shot detected
    if (provider.latestShot != null && provider.latestShot != _lastShot) {
      _lastShot = provider.latestShot;
      _shotCount++;
      _isHold = false;
      _isPress = false;
      _isRecoil = true;
      _phaseResetTimer?.cancel();
      _phaseResetTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isRecoil = false;
            _isHold = true;
            _recentTrace.clear();
          });
        }
      });
    }
  }

  // Inline sqrt to avoid dart:math import overhead in hot path
  double _sqrt(double v) => v <= 0 ? 0 : _invSqrt(v) * v;

  double _invSqrt(double v) {
    double x = v;
    double y = 1.5 + v * 0.5;
    y = y * (1.5 - x * y * y);
    y = y * (1.5 - x * y * y);
    y = y * (1.5 - x * y * y);
    return y;
  }
}

// ============================================
// PHASE DOT INDICATOR
// ============================================
class _PhaseDot extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;

  const _PhaseDot(this.label, this.color, this.active);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color : color.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 9,
              fontWeight: active ? FontWeight.w800 : FontWeight.w400,
              color: active ? color : StsysTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// TRACE DATA CLASSES
// ============================================
enum TracePhase { hold, press, recoil }

class _TracePoint {
  final double x;
  final double y;
  final double timestamp;
  final TracePhase phase;

  _TracePoint(this.x, this.y, this.timestamp, this.phase);
}

// ============================================
// CUSTOM PAINTER — Pre-allocated Paint/Color/TextPainter
// ============================================
class _MuzzleTracePainter extends CustomPainter {
  final List<_TracePoint> trace;
  final double currentX;
  final double currentY;
  final double zoom;
  final bool showGrid;
  final Color phaseColor;
  final double liveSpeed;

  _MuzzleTracePainter({
    required this.trace,
    required this.currentX,
    required this.currentY,
    required this.zoom,
    required this.showGrid,
    required this.phaseColor,
    required this.liveSpeed,
  });

  // --- PRE-ALLOCATED STATIC PAINT OBJECTS ---
  static final Paint _crossHairPaint = Paint()
    ..color = StsysTheme.outlineVariant.withValues(alpha: 0.15)
    ..strokeWidth = 0.5;

  static final Paint _crosshairPaint2 = Paint()
    ..color = StsysTheme.primary.withValues(alpha: 0.4)
    ..strokeWidth = 1.5;

  static final Paint _centerDotPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static final Paint _centerDotBgPaint = Paint()
    ..color = StsysTheme.primary.withValues(alpha: 0.6)
    ..style = PaintingStyle.fill;

  static final Paint _tracePaint = Paint()
    ..strokeWidth = 2.5
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  // Trail dot paint for motion blur ghost dots
  static final Paint _trailDotPaint = Paint()..style = PaintingStyle.fill;

  // Pre-allocated mutable paints (mutate .color only)
  final Paint _glowPaint1 = Paint()..style = PaintingStyle.fill;
  final Paint _glowPaint2 = Paint()..style = PaintingStyle.fill;
  final Paint _currentDotPaint = Paint()..style = PaintingStyle.fill;

  // Pre-computed ring render data (radius factor, fill color, stroke color)
  static final List<(double, Color, Color)> _ringRenders = [
    (0.2, _beginnerColor.withValues(alpha: 0.04), _beginnerColor.withValues(alpha: 0.2)),
    (0.4, _intermediateColor.withValues(alpha: 0.04), _intermediateColor.withValues(alpha: 0.2)),
    (0.6, _advancedColor.withValues(alpha: 0.04), _advancedColor.withValues(alpha: 0.2)),
    (0.8, _expertColor.withValues(alpha: 0.04), _expertColor.withValues(alpha: 0.2)),
    (1.0, _eliteColor.withValues(alpha: 0.04), _eliteColor.withValues(alpha: 0.2)),
  ];

  static final Paint _ringFillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _ringStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;

  // Pre-built static TextPainters (layout done once at construction)
  static final TextPainter _eliteLabel = TextPainter(
    text: TextSpan(
      text: 'ELITE',
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 7,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: _eliteColor.withValues(alpha: 0.25),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  static final TextPainter _expertLabel = TextPainter(
    text: TextSpan(
      text: 'EXPERT',
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 7,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: _expertColor.withValues(alpha: 0.25),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = size.width / 2 / zoom;

    if (showGrid) {
      _drawScoringRings(canvas, cx, cy, scale, size);
      // Cross hairs
      canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), _crossHairPaint);
      canvas.drawLine(Offset(0, cy), Offset(size.width, cy), _crossHairPaint);
    }

    // --- TRACE PATH (colored by phase, opacity fade) ---
    // Oldest = 0.3 alpha, newest = 1.0 alpha
    if (trace.length >= 2) {
      const fadeMin = 0.3;
      final traceLen = trace.length;
      for (int i = 1; i < traceLen; i++) {
        final prev = trace[i - 1];
        final curr = trace[i];
        final ageFraction = i / traceLen;
        final opacity = fadeMin + (1.0 - fadeMin) * ageFraction;
        _tracePaint.color = _getPhaseColor(curr.phase).withValues(alpha: opacity);
        canvas.drawLine(
          Offset(cx + prev.x * scale, cy + prev.y * scale),
          Offset(cx + curr.x * scale, cy + curr.y * scale),
          _tracePaint,
        );
      }
    }

    // --- CENTER ORIGIN CROSSHAIR ---
    canvas.drawLine(Offset(cx - 12, cy), Offset(cx + 12, cy), _crosshairPaint2);
    canvas.drawLine(Offset(cx, cy - 12), Offset(cx, cy + 12), _crosshairPaint2);
    canvas.drawCircle(Offset(cx, cy), 2, _centerDotBgPaint);
    canvas.drawCircle(Offset(cx, cy), 2, _centerDotPaint);

    // --- CURRENT POSITION DOT (dynamic sizing + motion blur) ---
    final currentPx = cx + currentX * scale;
    final currentPy = cy + currentY * scale;

    // Speed-based dot sizing: 0 speed = 5px, max speed = 8px
    final speedNorm = _clamp(liveSpeed * 4.0, 0.0, 1.0);
    final dotRadius = 5.0 + speedNorm * 3.0;
    final dotOpacity = 0.6 + speedNorm * 0.4;
    final glowRadius = 10.0 + speedNorm * 5.0;

    // Motion blur: 3 ghost trail dots behind current dot
    for (int t = 3; t >= 1; t--) {
      final trailAlpha = (0.3 - t * 0.08) * dotOpacity;
      final trailRadius = dotRadius * (1.0 - t * 0.2);
      _trailDotPaint.color = phaseColor.withValues(alpha: trailAlpha.clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(currentPx - t * 3.0 * speedNorm, currentPy),
        trailRadius,
        _trailDotPaint,
      );
    }

    // Glow layers (dynamic intensity)
    _glowPaint1.color = phaseColor.withValues(alpha: 0.15 + speedNorm * 0.15);
    _glowPaint2.color = phaseColor.withValues(alpha: 0.25 + speedNorm * 0.2);
    _currentDotPaint.color = phaseColor.withValues(alpha: dotOpacity);

    canvas.drawCircle(Offset(currentPx, currentPy), glowRadius, _glowPaint1);
    canvas.drawCircle(Offset(currentPx, currentPy), dotRadius + 2, _glowPaint2);
    canvas.drawCircle(Offset(currentPx, currentPy), dotRadius, _currentDotPaint);
    canvas.drawCircle(Offset(currentPx, currentPy), 2, _centerDotPaint);
  }

  void _drawScoringRings(Canvas canvas, double cx, double cy, double scale, Size size) {
    for (final ring in _ringRenders) {
      final radius = ring.$1 * scale;
      if (radius > 0 && radius < size.width / 2) {
        _ringFillPaint.color = ring.$2;
        _ringStrokePaint.color = ring.$3;
        canvas.drawCircle(Offset(cx, cy), radius, _ringFillPaint);
        canvas.drawCircle(Offset(cx, cy), radius, _ringStrokePaint);
      }
    }
    // Labels — reuse static TextPainters
    _eliteLabel.paint(canvas, Offset(cx + scale * 0.7 * 0.7, cy - scale * 0.7 * 0.7));
    _expertLabel.paint(canvas, Offset(cx + scale * 0.9 * 0.7 * 0.7, cy - scale * 0.9 * 0.7 * 0.7));
  }

  Color _getPhaseColor(TracePhase phase) {
    switch (phase) {
      case TracePhase.hold:
        return _holdColor;
      case TracePhase.press:
        return _pressColor;
      case TracePhase.recoil:
        return _recoilColor;
    }
  }

  double _clamp(double v, double lo, double hi) => v < lo ? lo : v > hi ? hi : v;

  @override
  bool shouldRepaint(covariant _MuzzleTracePainter oldDelegate) {
    if (oldDelegate.currentX != currentX) return true;
    if (oldDelegate.currentY != currentY) return true;
    if (oldDelegate.trace.length != trace.length) return true;
    if (trace.isNotEmpty && oldDelegate.trace.isNotEmpty) {
      final oldLast = oldDelegate.trace.last;
      final newLast = trace.last;
      if (oldLast.x != newLast.x || oldLast.y != newLast.y ||
          oldLast.phase != newLast.phase) return true;
    }
    if (oldDelegate.phaseColor != phaseColor) { return true; }
    if (oldDelegate.liveSpeed != liveSpeed) { return true; }
    return false;
  }
}
