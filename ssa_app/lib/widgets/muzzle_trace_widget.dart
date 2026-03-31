// ============================================
// File: widgets/muzzle_trace_widget.dart
// Dark theme muzzle trace with enhanced glow
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_data_provider.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';

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
  double _currX = 0.0;
  double _currY = 0.0;
  final List<_TracePoint> _recentTrace = [];
  static const int _maxTracePoints = 200;
  bool _isHold = true;
  bool _isPress = false;
  bool _isRecoil = false;
  ShotResult? _lastShot;
  int _shotCount = 0;

  Color get _currentPhaseColor {
    if (_isRecoil) return AppTheme.phaseRecoil;
    if (_isPress) return AppTheme.phasePress;
    return AppTheme.phaseHold;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, provider, child) {
        _processLatestData(provider);

        return Container(
          decoration: AppTheme.cardDecoration(),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.gps_fixed, color: AppTheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Muzzle Trace',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _phaseDot('H', AppTheme.phaseHold, _isHold),
                        const SizedBox(width: 6),
                        _phaseDot('P', AppTheme.phasePress, _isPress),
                        const SizedBox(width: 6),
                        _phaseDot('R', AppTheme.phaseRecoil, _isRecoil),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$_shotCount shots',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // XY Plot
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.cardBorder, width: 1),
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
              ),

              // Score display
              if (_lastShot != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _buildScoreDisplay(_lastShot!),
                )
              else
                const SizedBox(height: 52),
            ],
          ),
        );
      },
    );
  }

  Widget _phaseDot(String label, Color color, bool active) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: active ? color : color.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)] : null,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: active ? color : AppTheme.textTertiary,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildScoreDisplay(ShotResult shot) {
    final scoreColor = AppTheme.getScoreColor(shot.totalScore);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: scoreColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scoreColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _scoreChip('TOTAL', shot.totalScore, scoreColor),
          _scoreChip('HOLD', shot.holdScore, AppTheme.phaseHold),
          _scoreChip('PRESS', shot.pressScore, AppTheme.phasePress),
          _scoreChip('RECOIL', shot.recoilScore, AppTheme.phaseRecoil),
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
          style: TextStyle(fontSize: 9, color: AppTheme.textTertiary, fontWeight: FontWeight.w500),
        ),
        Text(
          score.toInt().toString(),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  void _processLatestData(SensorDataProvider provider) {
    if (provider.gyroXData.isEmpty) return;

    final latestGx = provider.gyroXData.last.value;
    final latestGz = provider.gyroZData.last.value;
    final latestTs = provider.gyroXData.last.timestamp;

    const dt = 0.01;
    _currX += (-latestGz) * dt;
    _currY += (-latestGx) * dt;

    final phase = _isRecoil ? TracePhase.recoil : (_isPress ? TracePhase.press : TracePhase.hold);
    _recentTrace.add(_TracePoint(_currX, _currY, latestTs, phase));

    if (_recentTrace.length > _maxTracePoints) {
      _recentTrace.removeAt(0);
    }

    if (_lastShot != null) {
      _isHold = false;
      _isPress = false;
      _isRecoil = true;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() { _isRecoil = false; _isHold = true; });
      });
    }

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

enum TracePhase { hold, press, recoil }

class _TracePoint {
  final double x;
  final double y;
  final double timestamp;
  final TracePhase phase;
  _TracePoint(this.x, this.y, this.timestamp, this.phase);
}

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

    if (showGrid) {
      // Cross hairs
      canvas.drawLine(
        Offset(centerX, 0),
        Offset(centerX, size.height),
        Paint()..color = const Color(0xFF2A2A4A)..strokeWidth = 0.5,
      );
      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width, centerY),
        Paint()..color = const Color(0xFF2A2A4A)..strokeWidth = 0.5,
      );

      // Concentric circles
      for (final r in [0.25, 0.5, 0.75, 1.0]) {
        final radius = r * scale;
        if (radius < size.width / 2) {
          canvas.drawCircle(
            Offset(centerX, centerY),
            radius,
            Paint()
              ..color = const Color(0xFF2A2A4A).withValues(alpha: 0.5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.5,
          );
        }
      }
    }

    // Trace path
    if (trace.length < 2) return;

    for (int i = 1; i < trace.length; i++) {
      final prev = trace[i - 1];
      final curr = trace[i];
      final x1 = centerX + prev.x * scale;
      final y1 = centerY + prev.y * scale;
      final x2 = centerX + curr.x * scale;
      final y2 = centerY + curr.y * scale;

      final paint = Paint()
        ..color = _getPhaseColor(curr.phase).withValues(alpha: 0.7)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }

    // Crosshair origin
    final crosshairPaint = Paint()
      ..color = const Color(0xFF5A5A6E)..strokeWidth = 1.5;
    canvas.drawLine(Offset(centerX - 10, centerY), Offset(centerX + 10, centerY), crosshairPaint);
    canvas.drawLine(Offset(centerX, centerY - 10), Offset(centerX, centerY + 10), crosshairPaint);

    // Current position dot with glow
    final px = centerX + currentX * scale;
    final py = centerY + currentY * scale;

    final glowPaint = Paint()
      ..color = phaseColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(px, py), 14, glowPaint);

    canvas.drawCircle(Offset(px, py), 6, Paint()..color = phaseColor);
    canvas.drawCircle(Offset(px, py), 2, Paint()..color = Colors.white);
  }

  Color _getPhaseColor(TracePhase phase) {
    switch (phase) {
      case TracePhase.hold:
        return AppTheme.phaseHold;
      case TracePhase.press:
        return AppTheme.phasePress;
      case TracePhase.recoil:
        return AppTheme.phaseRecoil;
    }
  }

  @override
  bool shouldRepaint(covariant _MuzzleTracePainter oldDelegate) => true;
}
