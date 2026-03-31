// ============================================
// File: screens/session_detail_screen.dart
// Dark theme session detail
// ============================================
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../providers/session_logger.dart';
import '../models/data_models.dart';
import '../widgets/benchmark_analysis_widget.dart';
import '../theme/app_theme.dart';

class SessionDetailScreen extends StatefulWidget {
  final SessionLog session;
  const SessionDetailScreen({super.key, required this.session});
  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Session Details',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.analytics, size: 20), text: 'Chart'),
            Tab(icon: Icon(Icons.assessment, size: 20), text: 'Benchmark'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChartView(),
          BenchmarkAnalysisWidget(session: widget.session),
        ],
      ),
    );
  }

  Widget _buildChartView() {
    final avgScore = widget.session.averageScore;
    final scoreColor = AppTheme.getScoreColor(avgScore);
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('HH:mm');

    return Column(
      children: [
        // Session info card
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateFormat.format(widget.session.date),
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'at ${timeFormat.format(widget.session.date)}',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  // Score badge
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: scoreColor.withValues(alpha: 0.3), width: 2),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            avgScore > 0 ? '${avgScore.toInt()}' : '--',
                            style: TextStyle(
                              color: scoreColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (avgScore > 0)
                            Text(
                              AppTheme.getScoreLabel(avgScore).substring(0, 1),
                              style: TextStyle(color: scoreColor.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _infoChip(Icons.timer_outlined, '${widget.session.duration.toStringAsFixed(1)}s'),
                  const SizedBox(width: 8),
                  _infoChip(Icons.gps_fixed, widget.session.firearmType.displayName),
                  const SizedBox(width: 8),
                  _infoChip(Icons.flash_on, widget.session.trainingMode.displayName),
                  const SizedBox(width: 8),
                  _infoChip(Icons.data_usage, '${widget.session.gyroX.length} pts'),
                ],
              ),
            ],
          ),
        ),

        // Chart
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.show_chart, color: AppTheme.primary, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Gyroscope Data',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _legendDot('X', const Color(0xFF4285F4)),
                    const SizedBox(width: 12),
                    _legendDot('Y', const Color(0xFFEA4335)),
                    const SizedBox(width: 12),
                    _legendDot('Z', const Color(0xFF34A853)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SfCartesianChart(
                        plotAreaBorderWidth: 0,
                        backgroundColor: AppTheme.background,
                        primaryXAxis: NumericAxis(
                          majorGridLines: MajorGridLines(width: 0.5, color: AppTheme.cardBorder),
                          axisLine: AxisLine(color: AppTheme.cardBorder),
                          labelStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 9),
                        ),
                        primaryYAxis: NumericAxis(
                          majorGridLines: MajorGridLines(width: 0.5, color: AppTheme.cardBorder),
                          axisLine: AxisLine(color: AppTheme.cardBorder),
                          labelStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 9),
                        ),
                        tooltipBehavior: TooltipBehavior(
                          enable: true,
                          textStyle: TextStyle(color: AppTheme.textPrimary),
                        ),
                        zoomPanBehavior: ZoomPanBehavior(
                          enablePinching: true,
                          enablePanning: true,
                          enableDoubleTapZooming: true,
                        ),
                        legend: const Legend(isVisible: false),
                        series: <CartesianSeries>[
                          LineSeries<DataPoint, double>(
                            dataSource: widget.session.gyroX,
                            xValueMapper: (DataPoint p, _) => p.x,
                            yValueMapper: (DataPoint p, _) => p.y,
                            name: 'Gyro X',
                            color: const Color(0xFF4285F4),
                            width: 2,
                          ),
                          LineSeries<DataPoint, double>(
                            dataSource: widget.session.gyroY,
                            xValueMapper: (DataPoint p, _) => p.x,
                            yValueMapper: (DataPoint p, _) => p.y,
                            name: 'Gyro Y',
                            color: const Color(0xFFEA4335),
                            width: 2,
                          ),
                          LineSeries<DataPoint, double>(
                            dataSource: widget.session.gyroZ,
                            xValueMapper: (DataPoint p, _) => p.x,
                            yValueMapper: (DataPoint p, _) => p.y,
                            name: 'Gyro Z',
                            color: const Color(0xFF34A853),
                            width: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
      ],
    );
  }
}
