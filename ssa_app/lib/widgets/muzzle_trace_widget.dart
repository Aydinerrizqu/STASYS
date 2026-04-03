// ============================================
// File: widgets/muzzle_trace_widget.dart
// MantisX-Style Real-time Muzzle Trace (XY Plot)
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_data_provider.dart';
import '../models/data_models.dart';

// Phase colors (MantisX style)
const Color _holdColor = Color(0xFFFF4444);   // Red
const Color _pressColor = Color(0xFFFFFF44);  // Yellow
const Color _recoilColor = Color(0xFF44FFFF); // Cyan

class MuzzleTraceWidget extends StatefulWidget {
  final double zoom;
  final bool showGrid;

  const MuzzleTraceWidget({
    super.key,
    this.zoom = 0.05,  // ±0.05 radians = ±2.86 degrees default
    this.showGrid = true,
  });

  @override
  State<MuzzleTraceWidget> createState() => _MuzzleTraceWidgetState();
}

class _MuzzleTraceWidgetState extends State<MuzzleTraceWidget> {
  // Integrated gyro trace — resets on each new shot
  double _currX = 0.0; // Windage (left/right)
  double _currY = 0.0; // Elevation (up/down)

  final List<_TracePoint> _recentTrace = [];
  static const int _maxTracePoints = 200;
  // Window: only integrate last 2 seconds of gyro data per shot
  static const int _traceWindowMs = 2000;

  // Phase coloring
  bool _isHold = true;
  bool _isPress = false;
  bool _isRecoil = false;

  // Shot display
  ShotResult? _lastShot;
  int _shotCount = 0;

  Color get _currentPhaseColor {
    if (_isRecoil) return _recoilColor;
    if (_isPress) return _pressColor;
    return _holdColor;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, provider, child) {
        // Process latest data
        _processLatestData(provider);

        return Card(
          elevation: 4,
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Muzzle Trace',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Row(
                      children: [
                        // Phase indicator dots
                        _phaseDot('H', _holdColor, _isHold),
                        _phaseDot('P', _pressColor, _isPress),
                        _phaseDot('R', _recoilColor, _isRecoil),
                        const SizedBox(width: 12),
                        // Shot counter
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_shotCount shots',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // XY Plot
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[700]!, width: 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: CustomPaint(
                        painter: _MuzzleTracePainter(
                          trace: _recentTrace,
                          currentX: _currX,
                          currentY: _currY,
                          zoom: widget.zoom,
                          showGrid: widget.showGrid,
                          phaseColor: _currentPhaseColor,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Score display
                if (_lastShot != null) _buildScoreDisplay(_lastShot!),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _phaseDot(String label, Color color, bool active) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: active ? color : color.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: active ? color : Colors.grey,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreDisplay(ShotResult shot) {
    final scoreColor = _getScoreColor(shot.totalScore);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      decoration: BoxDecoration(
        color: scoreColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scoreColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _scoreChip('TOTAL', shot.totalScore, scoreColor),
          _scoreChip('HOLD', shot.holdScore, _holdColor),
          _scoreChip('PRESS', shot.pressScore, _pressColor),
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
          style: TextStyle(fontSize: 8, color: Colors.grey[500]),
        ),
        Text(
          score.toInt().toString(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 95) return Colors.amber;
    if (score >= 85) return Colors.green;
    if (score >= 70) return Colors.blue;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  void _processLatestData(SensorDataProvider provider) {
    if (provider.gyroXData.isEmpty) return;

    // Only process data within our trace window (last 2 seconds)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final windowStart = nowMs - _traceWindowMs;

    // Filter to windowed data
    final windowedGx = provider.gyroXData.where((p) => p.timestamp >= windowStart).toList();
    final windowedGz = provider.gyroZData.where((p) => p.timestamp >= windowStart).toList();

    if (windowedGx.isEmpty) return;

    // Reintegrate from scratch within the window
    _currX = 0.0;
    _currY = 0.0;
    _recentTrace.clear();

    for (int i = 0; i < windowedGx.length; i++) {
      final gx = windowedGx[i].value;
      final gz = windowedGz[i].value;
      final ts = windowedGx[i].timestamp;

      const dt = 0.01; // 100Hz
      _currX += (-gz) * dt;
      _currY += (-gx) * dt;

      final phase = _isRecoil ? TracePhase.recoil : (_isPress ? TracePhase.press : TracePhase.hold);
      _recentTrace.add(_TracePoint(_currX, _currY, ts, phase));
    }

    // Trim if still too many points
    while (_recentTrace.length > _maxTracePoints) {
      _recentTrace.removeAt(0);
    }

    // Update phase based on shot detector state
    if (_lastShot != null) {
      _isHold = false;
      _isPress = false;
      _isRecoil = true;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _isRecoil = false;
            _isHold = true;
          });
        }
      });
    }

    // Check for new shot
    if (provider.latestShot != null && provider.latestShot != _lastShot) {
      _lastShot = provider.latestShot;
      _shotCount++;
      _isHold = false;
      _isPress = false;
      _isRecoil = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isRecoil = false;
            _isHold = true;
            _currX = 0;
            _currY = 0;
            _recentTrace.clear();
          });
        }
      });
    }
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
// CUSTOM PAINTER
// ============================================

class _MuzzleTracePainter extends CustomPainter {
  final List<_TracePoint> trace;
  final double currentX;
  final double currentY;
  final double zoom;
  final bool showGrid;
  final Color phaseColor;

  _MuzzleTracePainter({
    required this.trace,
    required this.currentX,
    required this.currentY,
    required this.zoom,
    required this.showGrid,
    required this.phaseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final scale = size.width / 2 / zoom;

    // --- GRID ---
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.grey[800]!
        ..strokeWidth = 0.5;

      // Cross hairs
      canvas.drawLine(
        Offset(centerX, 0),
        Offset(centerX, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width, centerY),
        gridPaint,
      );

      // Concentric circles (reference rings)
      for (final r in [0.25, 0.5, 0.75, 1.0]) {
        final radius = r * scale;
        if (radius < size.width / 2) {
          canvas.drawCircle(
            Offset(centerX, centerY),
            radius,
            Paint()
              ..color = Colors.grey[700]!.withOpacity(0.5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.5,
          );
        }
      }
    }

    // --- TRACE PATH ---
    if (trace.length < 2) return;

    for (int i = 1; i < trace.length; i++) {
      final prev = trace[i - 1];
      final curr = trace[i];

      final x1 = centerX + prev.x * scale;
      final y1 = centerY + prev.y * scale;
      final x2 = centerX + curr.x * scale;
      final y2 = centerY + curr.y * scale;

      final color = _getPhaseColor(curr.phase);
      final paint = Paint()
        ..color = color.withOpacity(0.7)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }

    // --- CENTER ORIGIN (crosshair) ---
    final crosshairPaint = Paint()
      ..color = Colors.grey[500]!
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(centerX - 10, centerY),
      Offset(centerX + 10, centerY),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - 10),
      Offset(centerX, centerY + 10),
      crosshairPaint,
    );

    // --- CURRENT POSITION DOT ---
    final currentPx = centerX + currentX * scale;
    final currentPy = centerY + currentY * scale;

    // Glow effect
    final glowPaint = Paint()
      ..color = phaseColor.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(currentPx, currentPy), 12, glowPaint);

    // Solid dot
    final dotPaint = Paint()
      ..color = phaseColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(currentPx, currentPy), 6, dotPaint);

    // White center
    canvas.drawCircle(Offset(currentPx, currentPy), 2, Paint()..color = Colors.white);
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

  @override
  bool shouldRepaint(covariant _MuzzleTracePainter oldDelegate) {
    return true; // Always repaint for real-time updates
  }
}
