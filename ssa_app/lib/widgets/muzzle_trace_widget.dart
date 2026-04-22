// ============================================
// File: widgets/muzzle_trace_widget.dart
// MantisX-Style Real-time Muzzle Trace — Smooth 60fps
// ============================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_data_provider.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';

// Phase colors (MantisX style — STSYS palette)
const Color _holdColor = Color(0xFFFFB693);    // STSYS primary — orange
const Color _pressColor = Color(0xFF8BCEFF);   // STSYS secondary — blue
const Color _recoilColor = Color(0xFFFFB4AB);  // STSYS error — coral

// Scoring ring colors (MantisX zones)
const Color _eliteColor = Color(0xFFFFD700);
const Color _expertColor = Color(0xFF4CAF50);
const Color _advancedColor = Color(0xFF2196F3);
const Color _intermediateColor = Color(0xFFFF9800);
const Color _beginnerColor = Color(0xFFF44336);

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

class _MuzzleTraceWidgetState extends State<MuzzleTraceWidget>
    with SingleTickerProviderStateMixin {
  // --- 60fps lerp: dot animates toward target ---
  double _dotX = 0.0, _dotY = 0.0;    // current rendered position
  double _targetX = 0.0, _targetY = 0.0; // EMA-smoothed target

  // --- Camera-follow: center lerps toward dot ---
  double _cameraX = 0.0, _cameraY = 0.0; // current camera center (world offset)
  static const double _cameraLerp = 0.3;  // camera follow speed (0-1, higher=faster)

  // --- Speed tracking for dot sizing ---
  double _liveSpeed = 0.0;
  double _prevLiveX = 0.0, _prevLiveY = 0.0;

  // --- Trace path ---
  final List<_TracePoint> _recentTrace = [];
  static const int _maxTracePoints = 400;
  static const int _traceWindowMs = 2000;

  // --- Phase coloring ---
  bool _isHold = true;
  bool _isPress = false;
  bool _isRecoil = false;

  // --- Shot display ---
  ShotResult? _lastShot;
  int _shotCount = 0;

  // --- Timer-based phase transitions ---
  Timer? _phaseResetTimer;

  // --- 60fps ticker for smooth animation ---
  late Ticker _ticker;
  double _lastTickTime = 0;

  Color get _currentPhaseColor {
    if (_isRecoil) return _recoilColor;
    if (_isPress) return _pressColor;
    return _holdColor;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
    _lastTickTime = DateTime.now().millisecondsSinceEpoch.toDouble();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phaseResetTimer?.cancel();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final deltaMs = (now - _lastTickTime.toInt()).toDouble();
    _lastTickTime = now.toDouble();

    // Lerp dot position toward target
    if (deltaMs > 0) {
      final t = (deltaMs / 16.0).clamp(0.0, 1.0);
      _dotX = _dotX + (_targetX - _dotX) * t;
      _dotY = _dotY + (_targetY - _dotY) * t;

      // Camera-follow: center lerps toward dot position
      _cameraX = _cameraX + (_dotX - _cameraX) * _cameraLerp;
      _cameraY = _cameraY + (_dotY - _cameraY) * _cameraLerp;
    }

    if (mounted) setState(() {});
  }

  void _processLatestData(SensorDataProvider provider) {
    // Use pre-computed trace coordinates from isolate
    // No atan2 calculation needed on UI thread

    // --- LIVE DOT: Use pre-computed coordinates from isolate ---
    final rawX = provider.liveTraceX;
    final rawY = provider.liveTraceY;

    // Target follows raw position directly
    // Camera and dot lerp handle the smoothing
    _targetX = rawX;
    _targetY = rawY;

    // Speed for dynamic dot sizing (from trace delta)
    final dx = rawX - _prevLiveX;
    final dy = rawY - _prevLiveY;
    _liveSpeed = _sqrt(dx * dx + dy * dy) * 100; // Scale for visual
    _prevLiveX = rawX;
    _prevLiveY = rawY;

    // --- TRACE PATH: Use pre-computed trace from isolate ---
    final traceX = provider.traceXData;
    final traceY = provider.traceYData;

    _recentTrace.clear();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final windowStart = nowMs - _traceWindowMs;

    // Build trace points from pre-computed coordinates
    // We use timestamp from accel data as proxy
    for (int i = 0; i < traceX.length && i < traceY.length; i++) {
      final ts = provider.accelXData.length > i
          ? provider.accelXData[i].timestamp
          : (nowMs - (traceX.length - i) * 10).toDouble();

      if (ts >= windowStart) {
        final phase = _isRecoil
            ? TracePhase.recoil
            : (_isPress ? TracePhase.press : TracePhase.hold);
        _recentTrace.add(_TracePoint(traceX[i], traceY[i], ts, phase));
      }
    }

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
            _dotX = 0.0;
            _dotY = 0.0;
            _targetX = 0.0;
            _targetY = 0.0;
            _cameraX = 0.0;
            _cameraY = 0.0;
          });
        }
      });
    }
  }

  double _sqrt(double v) => v <= 0 ? 0 : _invSqrt(v) * v;

  double _invSqrt(double v) {
    double x = v;
    double y = 1.5 + v * 0.5;
    y = y * (1.5 - x * y * y);
    y = y * (1.5 - x * y * y);
    y = y * (1.5 - x * y * y);
    return y;
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
              Row(
                children: [
                  _PhaseDot('H', _holdColor, _isHold),
                  _PhaseDot('P', _pressColor, _isPress),
                  _PhaseDot('R', _recoilColor, _isRecoil),
                  const Spacer(),
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
                          dotX: _dotX,
                          dotY: _dotY,
                          cameraX: _cameraX,
                          cameraY: _cameraY,
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
  final double dotX;
  final double dotY;
  final double cameraX; // camera center offset (world space)
  final double cameraY;
  final double zoom;
  final bool showGrid;
  final Color phaseColor;
  final double liveSpeed;

  _MuzzleTracePainter({
    required this.trace,
    required this.dotX,
    required this.dotY,
    required this.cameraX,
    required this.cameraY,
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

  static final Paint _trailDotPaint = Paint()..style = PaintingStyle.fill;

  // Pre-allocated mutable paints
  final Paint _glowPaint1 = Paint()..style = PaintingStyle.fill;
  final Paint _glowPaint2 = Paint()..style = PaintingStyle.fill;
  final Paint _currentDotPaint = Paint()..style = PaintingStyle.fill;

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

    // Camera offset: camera position in world space
    // Visual center = cx - cameraX * scale, cy - cameraY * scale
    // This makes the dot stay centered as it moves
    final offsetX = cx - cameraX * scale;
    final offsetY = cy - cameraY * scale;

    if (showGrid) {
      _drawScoringRings(canvas, offsetX, offsetY, scale, size);
      canvas.drawLine(Offset(offsetX, 0), Offset(offsetX, size.height), _crossHairPaint);
      canvas.drawLine(Offset(0, offsetY), Offset(size.width, offsetY), _crossHairPaint);
    }

    // --- TRACE PATH (relative to camera) ---
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
          Offset(offsetX + prev.x * scale, offsetY + prev.y * scale),
          Offset(offsetX + curr.x * scale, offsetY + curr.y * scale),
          _tracePaint,
        );
      }
    }

    // --- CENTER ORIGIN CROSSHAIR (at camera center) ---
    canvas.drawLine(Offset(offsetX - 12, offsetY), Offset(offsetX + 12, offsetY), _crosshairPaint2);
    canvas.drawLine(Offset(offsetX, offsetY - 12), Offset(offsetX, offsetY + 12), _crosshairPaint2);
    canvas.drawCircle(Offset(offsetX, offsetY), 2, _centerDotBgPaint);
    canvas.drawCircle(Offset(offsetX, offsetY), 2, _centerDotPaint);

    // --- LIVE DOT (relative to camera — stays centered) ---
    final dotPx = offsetX + dotX * scale;
    final dotPy = offsetY + dotY * scale;

    final speedNorm = _clamp(liveSpeed * 4.0, 0.0, 1.0);
    final dotRadius = 5.0 + speedNorm * 3.0;
    final dotOpacity = 0.6 + speedNorm * 0.4;
    final glowRadius = 10.0 + speedNorm * 5.0;

    // Motion blur: 3 ghost trail dots
    for (int t = 3; t >= 1; t--) {
      final trailAlpha = (0.3 - t * 0.08) * dotOpacity;
      final trailRadius = dotRadius * (1.0 - t * 0.2);
      _trailDotPaint.color = phaseColor.withValues(alpha: trailAlpha.clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(dotPx - t * 3.0 * speedNorm, dotPy),
        trailRadius,
        _trailDotPaint,
      );
    }

    _glowPaint1.color = phaseColor.withValues(alpha: 0.15 + speedNorm * 0.15);
    _glowPaint2.color = phaseColor.withValues(alpha: 0.25 + speedNorm * 0.2);
    _currentDotPaint.color = phaseColor.withValues(alpha: dotOpacity);

    canvas.drawCircle(Offset(dotPx, dotPy), glowRadius, _glowPaint1);
    canvas.drawCircle(Offset(dotPx, dotPy), dotRadius + 2, _glowPaint2);
    canvas.drawCircle(Offset(dotPx, dotPy), dotRadius, _currentDotPaint);
    canvas.drawCircle(Offset(dotPx, dotPy), 2, _centerDotPaint);
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
    _eliteLabel.paint(canvas, Offset(cx + scale * 0.7 * 0.7, cy - scale * 0.7 * 0.7));
    _expertLabel.paint(canvas, Offset(cx + scale * 0.9 * 0.7 * 0.7, cy - scale * 0.9 * 0.7 * 0.7));
  }

  Color _getPhaseColor(TracePhase phase) {
    switch (phase) {
      case TracePhase.hold: return _holdColor;
      case TracePhase.press: return _pressColor;
      case TracePhase.recoil: return _recoilColor;
    }
  }

  double _clamp(double v, double lo, double hi) => v < lo ? lo : v > hi ? hi : v;

  @override
  bool shouldRepaint(covariant _MuzzleTracePainter oldDelegate) {
    if (oldDelegate.dotX != dotX) return true;
    if (oldDelegate.dotY != dotY) return true;
    if (oldDelegate.cameraX != cameraX) return true;
    if (oldDelegate.cameraY != cameraY) return true;
    if (oldDelegate.trace.length != trace.length) return true;
    if (trace.isNotEmpty && oldDelegate.trace.isNotEmpty) {
      final oldLast = oldDelegate.trace.last;
      final newLast = trace.last;
      if (oldLast.x != newLast.x || oldLast.y != newLast.y ||
          oldLast.phase != newLast.phase) return true;
    }
    if (oldDelegate.phaseColor != phaseColor) return true;
    if (oldDelegate.liveSpeed != liveSpeed) return true;
    return false;
  }
}