// ============================================
// File: widgets/benchmark_analysis_widget.dart
// Dark theme benchmark analysis
// ============================================
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../providers/session_logger.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';
import 'dart:math';

class ShotDetection {
  final double time;
  final double stabilityScore;
  final double magnitude;
  ShotDetection({required this.time, required this.stabilityScore, required this.magnitude});
}

class BenchmarkAnalysisWidget extends StatefulWidget {
  final SessionLog session;
  const BenchmarkAnalysisWidget({super.key, required this.session});
  @override
  State<BenchmarkAnalysisWidget> createState() => _BenchmarkAnalysisWidgetState();
}

class _BenchmarkAnalysisWidgetState extends State<BenchmarkAnalysisWidget> {
  List<ShotDetection> _detectedShots = [];
  bool _isAnalyzing = false;
  double _gyroThreshold = 3.0;
  double _minShotInterval = 1.0;

  @override
  void initState() {
    super.initState();
    _analyzeShots();
  }

  @override
  Widget build(BuildContext context) {
    return _isAnalyzing
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppTheme.primary),
                const SizedBox(height: 16),
                Text('Analyzing shots...', style: AppTheme.subtitle),
              ],
            ),
          )
        : Column(
            children: [
              _buildControlPanel(),
              const SizedBox(height: 8),
              _buildStatsCards(),
              Expanded(child: _buildShotsList()),
            ],
          );
  }

  Widget _buildControlPanel() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assessment, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              const Text('Benchmark Analysis', style: TextStyle(
                color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSlider('Gyro: ${_gyroThreshold.toStringAsFixed(1)}', _gyroThreshold, 1.0, 10.0, (v) { setState(() => _gyroThreshold = v); }, () => _analyzeShots())),
              const SizedBox(width: 12),
              Expanded(child: _buildSlider('Interval: ${_minShotInterval.toStringAsFixed(1)}s', _minShotInterval, 0.5, 3.0, (v) { setState(() => _minShotInterval = v); }, () => _analyzeShots())),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _outlinedBtn(Icons.refresh, 'Re-analyze', () => _analyzeShots())),
              const SizedBox(width: 8),
              Expanded(child: _outlinedBtn(Icons.analytics, 'Detailed Chart', _showDetailedChart)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, VoidCallback onEnd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbColor: AppTheme.primary,
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: AppTheme.cardBorder,
            overlayColor: AppTheme.primary.withValues(alpha: 0.2),
          ),
          child: Slider(value: value, min: min, max: max, divisions: 18, onChanged: onChanged, onChangeEnd: (_) => onEnd()),
        ),
      ],
    );
  }

  Widget _outlinedBtn(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primary,
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildStatsCards() {
    if (_detectedShots.isEmpty) return const SizedBox.shrink();

    double avgScore = _detectedShots.map((s) => s.stabilityScore).reduce((a, b) => a + b) / _detectedShots.length;
    double totalTime = _detectedShots.isNotEmpty ? _detectedShots.last.time : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _miniStat('Avg Score', avgScore.toStringAsFixed(1), Icons.star_outline, AppTheme.scoreElite)),
              Expanded(child: _miniStat('Total Time', '${totalTime.toStringAsFixed(2)}s', Icons.timer_outlined, AppTheme.primary)),
              Expanded(child: _miniStat('Shots', '${_detectedShots.length}', Icons.gps_fixed, AppTheme.success)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
      ],
    );
  }

  Widget _buildShotsList() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                SizedBox(width: 30, child: Text('SHOT', style: _headerStyle)),
                Expanded(child: Center(child: Text('SCORE', style: _headerStyle))),
                SizedBox(width: 70, child: Text('TIME', style: _headerStyle)),
                SizedBox(width: 70, child: Text('MAG', style: _headerStyle)),
              ],
            ),
          ),
          Expanded(
            child: _detectedShots.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 40, color: AppTheme.textTertiary),
                        const SizedBox(height: 8),
                        Text('No shots detected', style: AppTheme.subtitle),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _detectedShots.length,
                    itemBuilder: (context, index) {
                      final shot = _detectedShots[index];
                      final shotTime = index == 0 ? shot.time : shot.time - _detectedShots[index - 1].time;
                      final scoreColor = AppTheme.getScoreColor(shot.stabilityScore);

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppTheme.cardBorder.withValues(alpha: 0.5))),
                        ),
                        child: Row(
                          children: [
                            SizedBox(width: 30, child: Text('${index + 1}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13))),
                            Expanded(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: scoreColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    shot.stabilityScore.toStringAsFixed(1),
                                    style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 70,
                              child: Text(shotTime.toStringAsFixed(2), style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'monospace')),
                            ),
                            SizedBox(
                              width: 70,
                              child: Text(shot.magnitude.toStringAsFixed(2), style: TextStyle(color: AppTheme.textTertiary, fontSize: 12, fontFamily: 'monospace')),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  TextStyle get _headerStyle => TextStyle(color: AppTheme.textTertiary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1);

  void _analyzeShots() {
    setState(() => _isAnalyzing = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      List<ShotDetection> shots = [];
      List<double> gyroMagnitudes = [];
      List<double> times = [];

      for (int i = 0; i < widget.session.gyroX.length; i++) {
        double magnitude = sqrt(
          pow(widget.session.gyroX[i].y, 2) +
          pow(widget.session.gyroY[i].y, 2) +
          pow(widget.session.gyroZ[i].y, 2),
        );
        gyroMagnitudes.add(magnitude);
        times.add(widget.session.gyroX[i].x);
      }

      for (int i = 1; i < gyroMagnitudes.length - 1; i++) {
        if (gyroMagnitudes[i] > _gyroThreshold &&
            gyroMagnitudes[i] > gyroMagnitudes[i - 1] &&
            gyroMagnitudes[i] > gyroMagnitudes[i + 1]) {
          bool validInterval = shots.isEmpty || (times[i] - shots.last.time >= _minShotInterval);
          if (validInterval) {
            shots.add(ShotDetection(
              time: times[i],
              stabilityScore: _calculateStabilityScore(i, gyroMagnitudes),
              magnitude: gyroMagnitudes[i],
            ));
          }
        }
      }

      setState(() { _detectedShots = shots; _isAnalyzing = false; });
    });
  }

  double _calculateStabilityScore(int peakIndex, List<double> magnitudes) {
    int windowSize = 10;
    int start = max(0, peakIndex - windowSize);
    int end = min(magnitudes.length, peakIndex + windowSize + 1);
    List<double> window = magnitudes.sublist(start, end);
    double mean = window.reduce((a, b) => a + b) / window.length;
    double variance = window.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / window.length;
    return max(0, min(100, 100 - (variance * 10)));
  }

  void _showDetailedChart() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Detailed Analysis', style: AppTheme.title),
                const SizedBox(height: 16),
                Expanded(child: _buildDetailedChart()),
                const SizedBox(height: 16),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedChart() {
    List<DataPoint> magnitudeData = [];
    for (int i = 0; i < widget.session.gyroX.length; i++) {
      double magnitude = sqrt(
        pow(widget.session.gyroX[i].y, 2) +
        pow(widget.session.gyroY[i].y, 2) +
        pow(widget.session.gyroZ[i].y, 2),
      );
      magnitudeData.add(DataPoint(widget.session.gyroX[i].x, magnitude));
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SfCartesianChart(
        backgroundColor: AppTheme.background,
        primaryXAxis: NumericAxis(
          title: AxisTitle(text: 'Time (s)', textStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
          majorGridLines: MajorGridLines(width: 0.5, color: AppTheme.cardBorder),
          axisLine: AxisLine(color: AppTheme.cardBorder),
          labelStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 9),
        ),
        primaryYAxis: NumericAxis(
          title: AxisTitle(text: 'Magnitude', textStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
          majorGridLines: MajorGridLines(width: 0.5, color: AppTheme.cardBorder),
          axisLine: AxisLine(color: AppTheme.cardBorder),
          labelStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 9),
        ),
        series: <CartesianSeries>[
          LineSeries<DataPoint, double>(
            dataSource: magnitudeData,
            xValueMapper: (DataPoint p, _) => p.x,
            yValueMapper: (DataPoint p, _) => p.y,
            name: 'Gyro Magnitude',
            color: AppTheme.primary,
            width: 2,
          ),
        ],
        annotations: _detectedShots.map((shot) => CartesianChartAnnotation(
          widget: Icon(Icons.my_location, color: AppTheme.error, size: 16),
          coordinateUnit: CoordinateUnit.point,
          x: shot.time,
          y: shot.magnitude,
        )).toList(),
      ),
    );
  }
}
