// ============================================
// File: screens/replay_screen.dart
// ============================================
// Offline replay screen: loads a SessionLog by id, runs it through
// ReplayEngine, and shows the reconstructed barrel trace + per-shot
// 3-phase breakdown.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/session_logger.dart';
import '../services/database_service.dart';
import '../services/trajectory/replay_engine.dart';
import '../services/trajectory/replay_models.dart';
import '../theme/app_theme.dart';
import '../widgets/replay_trace_painter.dart';

class ReplayScreen extends StatefulWidget {
  final String sessionId;

  const ReplayScreen({super.key, required this.sessionId});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  late Future<_ReplayResult?> _future;
  ReplayShot? _selectedShot;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReplayResult?> _load() async {
    final session = await DatabaseService().getSession(widget.sessionId);
    if (session == null) return null;
    final trace = ReplayEngine().replay(session);
    if (trace.hasShots) {
      _selectedShot = trace.shots.first;
    }
    return _ReplayResult(session: session, trace: trace);
  }

  Color _scoreColor(double score) {
    if (score >= 95) return const Color(0xFFFFD700);
    if (score >= 85) return const Color(0xFF4CAF50);
    if (score >= 70) return const Color(0xFF2196F3);
    if (score >= 50) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  void _selectShot(ReplayShot shot) {
    setState(() => _selectedShot = shot);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StsysTheme.surfaceContainerLowest,
      body: SafeArea(
        child: FutureBuilder<_ReplayResult?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final result = snapshot.data;
            if (result == null) {
              return _ErrorView(onBack: () => Navigator.pop(context));
            }
            return _buildBody(result);
          },
        ),
      ),
    );
  }

  Widget _buildBody(_ReplayResult result) {
    final session = result.session;
    final trace = result.trace;
    final avgScore = trace.shots.isEmpty
        ? 0.0
        : trace.shots.map((s) => s.totalScore).reduce((a, b) => a + b) /
            trace.shots.length;

    return Column(
      children: [
        _buildHeader(session, trace, avgScore),
        if (trace.hasShots)
          Expanded(
            flex: 2,
            child: _buildTraceView(trace),
          )
        else
          Expanded(
            flex: 2,
            child: _buildEmptyTrace(),
          ),
        if (_selectedShot != null)
          Expanded(
            flex: 3,
            child: _ReplayShotPanel(
              shot: _selectedShot!,
              shotIndex: trace.shots.indexOf(_selectedShot!),
              getScoreColor: _scoreColor,
            ),
          )
        else
          Expanded(
            flex: 3,
            child: _buildEmptyPanel(),
          ),
        if (trace.hasShots)
          Expanded(
            flex: 1,
            child: _buildShotChips(trace),
          ),
      ],
    );
  }

  // ============================================
  // Header
  // ============================================
  Widget _buildHeader(SessionLog session, ReplayTrace trace, double avgScore) {
    final duration = Duration(milliseconds: (trace.totalDurationSeconds * 1000).round());
    final durStr = '${duration.inMinutes.toString().padLeft(2, '0')}:'
        '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: StsysTheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: StsysTheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.arrow_back,
                size: 20,
                color: StsysTheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OFFLINE REPLAY',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: StsysTheme.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${trace.shots.length} shots · $durStr · ${trace.sampleRateHz.toInt()} Hz',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: trace.hasShots
                        ? _scoreColor(avgScore)
                        : StsysTheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showInfoDialog(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: StsysTheme.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.info_outline,
                size: 20,
                color: StsysTheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        backgroundColor: StsysTheme.surfaceContainerHigh,
        title: Text(
          'ABOUT REPLAY',
          style: StsysText.labelBold.copyWith(color: StsysTheme.secondary),
        ),
        content: Text(
          'The barrel trace and shot breakdown are reconstructed from '
          'the original raw sensor data using the offline replay engine. '
          'Results should match what was scored live.',
          style: StsysText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
                color: StsysTheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // Trace view
  // ============================================
  Widget _buildTraceView(ReplayTrace trace) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Text(
                  'BARREL TRACE',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: StsysTheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                _legendChip('PATH', const Color(0xFFFFB693)),
                const SizedBox(width: 6),
                _legendChip('HIT', const Color(0xFF4CAF50)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: StsysTheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: ReplayTracePainter(
                      trace: trace,
                      selectedShot: _selectedShot,
                      getScoreColor: _scoreColor,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: StsysTheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyTrace() {
    return Center(
      child: Text(
        'NO SHOTS RECORDED',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          color: StsysTheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  Widget _buildEmptyPanel() {
    return Center(
      child: Text(
        'SELECT A SHOT TO INSPECT',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          color: StsysTheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  // ============================================
  // Shot chips
  // ============================================
  Widget _buildShotChips(ReplayTrace trace) {
    return Container(
      color: StsysTheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'REPLAYED SHOTS',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: StsysTheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: StsysTheme.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${trace.shots.length}',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: StsysTheme.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: trace.shots.length,
              itemBuilder: (context, index) {
                final shot = trace.shots[index];
                final isSelected = shot == _selectedShot;
                final color = _scoreColor(shot.totalScore);

                return GestureDetector(
                  onTap: () => _selectShot(shot),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 70,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.15)
                          : StsysTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? color
                            : StsysTheme.outlineVariant.withValues(alpha: 0.2),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '#${index + 1}',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: StsysTheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          shot.totalScore.toInt().toString(),
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          't=${shot.breakTSeconds.toStringAsFixed(2)}s',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 8,
                            color: StsysTheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Per-shot 3-phase panel
// ============================================
class _ReplayShotPanel extends StatelessWidget {
  final ReplayShot shot;
  final int shotIndex;
  final Color Function(double) getScoreColor;

  const _ReplayShotPanel({
    required this.shot,
    required this.shotIndex,
    required this.getScoreColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = getScoreColor(shot.totalScore);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      shot.totalScore.toInt().toString(),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SHOT #${shotIndex + 1}'.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: StsysTheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('HH:mm:ss').format(shot.timestamp),
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: StsysTheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _phaseBadge('H', shot.holdScore.toInt(),
                              const Color(0xFFFF4444)),
                          const SizedBox(width: 6),
                          _phaseBadge('P', shot.pressScore.toInt(),
                              const Color(0xFFFFFF44)),
                          const SizedBox(width: 6),
                          _phaseBadge('R', shot.recoilScore.toInt(),
                              const Color(0xFF44FFFF)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
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
                    painter: _ThreePhasePainter(shot: shot),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    _scoreChip('HOLD', shot.holdScore, const Color(0xFFFF4444)),
                    const SizedBox(width: 4),
                    _scoreChip('PRESS', shot.pressScore, const Color(0xFFFFFF44)),
                    const SizedBox(width: 4),
                    _scoreChip('RECOIL', shot.recoilScore, const Color(0xFF44FFFF)),
                    const SizedBox(width: 4),
                    _scoreChip('ELEV', shot.elevationScore, Colors.purple),
                    const SizedBox(width: 4),
                    _scoreChip('WIND', shot.windageScore, Colors.teal),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _metaChip(Icons.straighten, '${shot.travelDistance.toStringAsFixed(1)}°'),
                    const SizedBox(width: 6),
                    _metaChip(Icons.bolt, 'jerk ${shot.peakJerk.toStringAsFixed(1)}'),
                    const SizedBox(width: 6),
                    _metaChip(Icons.gps_fixed, shot.firearmType),
                    const SizedBox(width: 6),
                    _metaChip(Icons.center_focus_strong, shot.trainingMode),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseBadge(String label, int score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label:$score',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _scoreChip(String label, double score, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 7,
                letterSpacing: 1,
                color: color.withValues(alpha: 0.7),
              ),
            ),
            Text(
              score.toInt().toString(),
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: StsysTheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: StsysTheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// 3-phase chart painter (small, inline)
// ============================================
class _ThreePhasePainter extends CustomPainter {
  final ReplayShot shot;

  _ThreePhasePainter({required this.shot});

  static const Color _holdColor = Color(0xFFFF4444);
  static const Color _pressColor = Color(0xFFFFFF44);
  static const Color _recoilColor = Color(0xFF44FFFF);

  static final Paint _gridPaint = Paint()
    ..color = const Color(0xFF6B7280).withValues(alpha: 0.3)
    ..strokeWidth = 0.5;

  static final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;

  static final Paint _hitFill = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static final Paint _hitStroke = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  static final Paint _curvePaint = Paint()
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    double maxDev = 0.005;
    for (final v in shot.holdX) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    for (final v in shot.holdY) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    for (final v in shot.pressX) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    for (final v in shot.pressY) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    for (final v in shot.recoilX) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    for (final v in shot.recoilY) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    maxDev *= 1.3;
    if (maxDev < 0.001) maxDev = 0.01;

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

    _drawCurve(canvas, shot.holdX, shot.holdY, cx, cy, scaleX, scaleY, _holdColor);
    _drawCurve(canvas, shot.pressX, shot.pressY, cx, cy, scaleX, scaleY, _pressColor);
    _drawCurve(canvas, shot.recoilX, shot.recoilY, cx, cy, scaleX, scaleY, _recoilColor);

    canvas.drawCircle(Offset(cx, cy), 3, _hitFill);
    canvas.drawCircle(Offset(cx, cy), 3, _hitStroke);
  }

  void _drawCurve(Canvas canvas, List<double> xList, List<double> yList,
      double cx, double cy, double sx, double sy, Color color) {
    if (xList.length < 2) return;

    final path = Path()..moveTo(cx + xList[0] * sx, cy + yList[0] * sy);
    for (int i = 1; i < xList.length; i++) {
      path.lineTo(cx + xList[i] * sx, cy + yList[i] * sy);
    }

    _curvePaint.color = color.withValues(alpha: 0.8);
    canvas.drawPath(path, _curvePaint);
  }

  @override
  bool shouldRepaint(covariant _ThreePhasePainter oldDelegate) {
    return oldDelegate.shot != shot;
  }
}

// ============================================
// Error / not-found view
// ============================================
class _ErrorView extends StatelessWidget {
  final VoidCallback onBack;

  const _ErrorView({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: StsysTheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.arrow_back,
                      size: 20,
                      color: StsysTheme.onSurface.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: StsysTheme.error.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(
                  'SESSION NOT FOUND',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: StsysTheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================
// Internal result wrapper
// ============================================
class _ReplayResult {
  final SessionLog session;
  final ReplayTrace trace;

  const _ReplayResult({required this.session, required this.trace});
}