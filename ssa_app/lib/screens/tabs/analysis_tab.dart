// ============================================
// File: screens/tabs/analysis_tab.dart
// Post-Shot Analysis Tab — MantisX-Style
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/sensor_data_provider.dart';
import '../../models/data_models.dart';

// Phase colors (MantisX style)
const Color _holdColor = Color(0xFFFF4444);   // Red
const Color _pressColor = Color(0xFFFFFF44);  // Yellow
const Color _recoilColor = Color(0xFF44FFFF); // Cyan

class AnalysisTab extends StatefulWidget {
  const AnalysisTab({super.key});

  @override
  State<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<AnalysisTab> {
  ShotResult? _selectedShot;
  int? _selectedShotIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSelection(null);
    });
  }

  void _updateSelection(ShotResult? shot) {
    final sensor = context.read<SensorDataProvider>();
    final shots = sensor.sessionShots;

    if (shot != null) {
      setState(() {
        _selectedShot = shot;
        _selectedShotIndex = shots.indexOf(shot);
      });
    } else if (shots.isNotEmpty) {
      setState(() {
        _selectedShot = shots.last;
        _selectedShotIndex = shots.length - 1;
      });
    } else {
      setState(() {
        _selectedShot = null;
        _selectedShotIndex = null;
      });
    }
  }

  Color _getScoreColor(double score) {
    if (score >= 95) return Colors.amber;
    if (score >= 85) return Colors.green;
    if (score >= 70) return Colors.blue;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatScore(double score) {
    return score.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Consumer<SensorDataProvider>(
        builder: (context, sensor, child) {
          final shots = sensor.sessionShots;

          // Auto-select latest shot when shots change
          if (shots.isNotEmpty && (_selectedShot == null || !shots.contains(_selectedShot))) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateSelection(shots.last);
            });
          }

          if (shots.isEmpty) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              // Top: Selected shot analysis
              Expanded(
                flex: 3,
                child: _ShotAnalysisPanel(
                  shot: _selectedShot,
                  shotIndex: _selectedShotIndex,
                  getScoreColor: _getScoreColor,
                ),
              ),
              // Bottom: Shot history list
              Expanded(
                flex: 2,
                child: _ShotHistoryList(
                  shots: shots,
                  selectedShot: _selectedShot,
                  onShotSelected: _updateSelection,
                  getScoreColor: _getScoreColor,
                  formatTime: _formatTime,
                  formatScore: _formatScore,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No shots recorded yet',
            style: TextStyle(fontSize: 18, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a recording session to see\nshot analysis here',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

// ============================================
// SHOT ANALYSIS PANEL (top section)
// ============================================
class _ShotAnalysisPanel extends StatelessWidget {
  final ShotResult? shot;
  final int? shotIndex;
  final Color Function(double) getScoreColor;

  const _ShotAnalysisPanel({
    required this.shot,
    required this.shotIndex,
    required this.getScoreColor,
  });

  @override
  Widget build(BuildContext context) {
    if (shot == null) {
      return Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'Select a shot below',
            style: TextStyle(color: Colors.grey[400], fontSize: 16),
          ),
        ),
      );
    }

    final scoreColor = getScoreColor(shot!.totalScore);

    return Container(
      margin: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Big score + header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Big score
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scoreColor, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      shot!.totalScore.toInt().toString(),
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Shot info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SHOT #${(shotIndex ?? 0) + 1}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        _formatDateTime(shot!.timestamp),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Phase scores row
                      Row(
                        children: [
                          _phaseBadge('H', shot!.holdScore.toInt(), _holdColor),
                          const SizedBox(width: 8),
                          _phaseBadge('P', shot!.pressScore.toInt(), _pressColor),
                          const SizedBox(width: 8),
                          _phaseBadge('R', shot!.recoilScore.toInt(), _recoilColor),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 3-Phase chart
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: _ThreePhaseChartPainter(shot: shot!),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Phase score chips
          Row(
            children: [
              _scoreChip('HOLD', shot!.holdScore, _holdColor),
              const SizedBox(width: 6),
              _scoreChip('PRESS', shot!.pressScore, _pressColor),
              const SizedBox(width: 6),
              _scoreChip('RECOIL', shot!.recoilScore, _recoilColor),
              const SizedBox(width: 6),
              _scoreChip('ELEV', shot!.elevationScore, Colors.purple),
              const SizedBox(width: 6),
              _scoreChip('WIND', shot!.windageScore, Colors.teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _phaseBadge(String label, int score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Text(
            '$score',
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _scoreChip(String label, double score, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
            ),
            Text(
              score.toInt().toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

// ============================================
// SHOT HISTORY LIST (bottom section)
// ============================================
class _ShotHistoryList extends StatelessWidget {
  final List<ShotResult> shots;
  final ShotResult? selectedShot;
  final void Function(ShotResult) onShotSelected;
  final Color Function(double) getScoreColor;
  final String Function(DateTime) formatTime;
  final String Function(double) formatScore;

  const _ShotHistoryList({
    required this.shots,
    required this.selectedShot,
    required this.onShotSelected,
    required this.getScoreColor,
    required this.formatTime,
    required this.formatScore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Text(
                  'SESSION HISTORY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                _buildStats(shots),
              ],
            ),
          ),
          // Shot cards
          Expanded(
            child: ListView.builder(
              itemCount: shots.length,
              itemBuilder: (context, index) {
                final i = shots.length - 1 - index; // Most recent first
                final shot = shots[i];
                final isSelected = shot == selectedShot;
                return _ShotCard(
                  shot: shot,
                  shotNumber: i + 1,
                  isSelected: isSelected,
                  onTap: () => onShotSelected(shot),
                  getScoreColor: getScoreColor,
                  formatTime: formatTime,
                  prevShot: i > 0 ? shots[i - 1] : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(List<ShotResult> shots) {
    if (shots.isEmpty) return const SizedBox.shrink();
    final avg = shots.map((s) => s.totalScore).reduce((a, b) => a + b) / shots.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${shots.length} shots | Avg: ${avg.toStringAsFixed(1)}',
        style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ============================================
// SHOT CARD
// ============================================
class _ShotCard extends StatelessWidget {
  final ShotResult shot;
  final int shotNumber;
  final bool isSelected;
  final VoidCallback onTap;
  final Color Function(double) getScoreColor;
  final String Function(DateTime) formatTime;
  final ShotResult? prevShot;

  const _ShotCard({
    required this.shot,
    required this.shotNumber,
    required this.isSelected,
    required this.onTap,
    required this.getScoreColor,
    required this.formatTime,
    this.prevShot,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = getScoreColor(shot.totalScore);
    final split = prevShot != null
        ? shot.timestamp.difference(prevShot!.timestamp).inMilliseconds
        : 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[200]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Shot number
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$shotNumber',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Time
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatTime(shot.timestamp),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'H:${shot.holdScore.toInt()} P:${shot.pressScore.toInt()} R:${shot.recoilScore.toInt()}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            // Split
            if (split > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: split < 1500
                      ? Colors.green.withValues(alpha: 0.1)
                      : split > 3000
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(split / 1000).toStringAsFixed(2)}s',
                  style: TextStyle(
                    fontSize: 11,
                    color: split < 1500
                        ? Colors.green
                        : split > 3000
                            ? Colors.red
                            : Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            // Score
            Container(
              width: 48,
              height: 32,
              decoration: BoxDecoration(
                color: scoreColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  shot.totalScore.toInt().toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// 3-PHASE CHART PAINTER
// ============================================
class _ThreePhaseChartPainter extends CustomPainter {
  final ShotResult shot;

  _ThreePhaseChartPainter({required this.shot});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Auto-calculate scale based on max deviation
    double maxDev = 0.005; // min ±0.005 rad
    final allPoints = <List<double>>[];
    if (shot.holdX != null) allPoints.addAll([shot.holdX!, shot.holdY!]);
    if (shot.pressX != null) allPoints.addAll([shot.pressX!, shot.pressY!]);
    if (shot.recoilX != null) allPoints.addAll([shot.recoilX!, shot.recoilY!]);

    for (final list in allPoints) {
      for (final v in list) {
        if (v.abs() > maxDev) maxDev = v.abs();
      }
    }
    maxDev *= 1.3; // 30% margin

    final scaleX = size.width / 2 / maxDev;
    final scaleY = size.height / 2 / maxDev;

    // Grid
    final gridPaint = Paint()
      ..color = Colors.grey[800]!
      ..strokeWidth = 0.5;

    // Cross hairs
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), gridPaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), gridPaint);

    // Concentric circles
    for (final r in [0.25, 0.5, 0.75, 1.0]) {
      final rx = r * maxDev * scaleX;
      final ry = r * maxDev * scaleY;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
        Paint()
          ..color = Colors.grey[700]!.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }

    // Draw curves
    _drawCurve(canvas, shot.holdX, shot.holdY, cx, cy, scaleX, scaleY, _holdColor);
    _drawCurve(canvas, shot.pressX, shot.pressY, cx, cy, scaleX, scaleY, _pressColor);
    _drawCurve(canvas, shot.recoilX, shot.recoilY, cx, cy, scaleX, scaleY, _recoilColor);

    // Hit marker at origin
    final markerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 4, markerPaint);
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1);

    // Labels
    _drawLabel(canvas, 'H', cx + size.width * 0.42, cy + 12, _holdColor);
    _drawLabel(canvas, 'P', cx + size.width * 0.42, cy + 28, _pressColor);
    _drawLabel(canvas, 'R', cx + size.width * 0.42, cy + 44, _recoilColor);
  }

  void _drawCurve(Canvas canvas, List<double>? xList, List<double>? yList,
      double cx, double cy, double sx, double sy, Color color) {
    if (xList == null || yList == null || xList.length < 2) return;

    final path = Path();
    for (int i = 0; i < xList.length; i++) {
      final px = cx + xList[i] * sx;
      final py = cy + yList[i] * sy;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawLabel(Canvas canvas, String label, double x, double y, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _ThreePhaseChartPainter oldDelegate) {
    return oldDelegate.shot != shot;
  }
}
