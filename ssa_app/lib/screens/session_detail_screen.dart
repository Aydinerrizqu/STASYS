// ============================================
// File: screens/session_detail_screen.dart
// ============================================
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../providers/session_logger.dart';
import '../models/data_models.dart';
import '../widgets/benchmark_analysis_widget.dart';
//import 'dart:math';

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
      appBar: AppBar(
        title: Text('Session Details'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.analytics), text: 'Chart View'),
            Tab(icon: Icon(Icons.assessment), text: 'Benchmark'),
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
    return Column(
      children: [
        // Session Info Card
        _buildSessionInfoCard(),
        
        // Chart
        Expanded(
          child: _buildChart(),
        ),
      ],
    );
  }

  Widget _buildSessionInfoCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session Information',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    'Date & Time',
                    '${widget.session.date.day}/${widget.session.date.month}/${widget.session.date.year}\n'
                    '${widget.session.date.hour.toString().padLeft(2, '0')}:'
                    '${widget.session.date.minute.toString().padLeft(2, '0')}',
                    Icons.calendar_today,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    'Duration',
                    '${widget.session.duration.toStringAsFixed(1)}s',
                    Icons.timer,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    'Data Points',
                    '${widget.session.gyroX.length}',
                    Icons.data_usage,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 24),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildChart() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gyroscope Data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SfCartesianChart(
                plotAreaBorderWidth: 1,
                plotAreaBorderColor: Colors.grey[300],
                backgroundColor: Colors.white,
                
                primaryXAxis: NumericAxis(
                  title: AxisTitle(text: 'Time (seconds)'),
                  majorGridLines: const MajorGridLines(width: 0.5),
                  minorGridLines: const MinorGridLines(width: 0.2),
                ),
                
                primaryYAxis: NumericAxis(
                  title: AxisTitle(text: 'Angular Velocity (°/s)'),
                  majorGridLines: const MajorGridLines(width: 0.5),
                  minorGridLines: const MinorGridLines(width: 0.2),
                ),
                
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  format: 'point.x: point.ys',
                ),
                
                zoomPanBehavior: ZoomPanBehavior(
                  enablePinching: true,
                  enablePanning: true,
                  enableDoubleTapZooming: true,
                  enableMouseWheelZooming: true,
                ),
                
                legend: const Legend(
                  isVisible: true,
                  position: LegendPosition.bottom,
                ),
                
                series: <CartesianSeries>[
                  LineSeries<DataPoint, double>(
                    dataSource: widget.session.gyroX,
                    xValueMapper: (DataPoint point, _) => point.x,
                    yValueMapper: (DataPoint point, _) => point.y,
                    name: 'Gyro X',
                    color: Colors.red,
                    width: 2,
                  ),
                  LineSeries<DataPoint, double>(
                    dataSource: widget.session.gyroY,
                    xValueMapper: (DataPoint point, _) => point.x,
                    yValueMapper: (DataPoint point, _) => point.y,
                    name: 'Gyro Y',
                    color: Colors.green,
                    width: 2,
                  ),
                  LineSeries<DataPoint, double>(
                    dataSource: widget.session.gyroZ,
                    xValueMapper: (DataPoint point, _) => point.x,
                    yValueMapper: (DataPoint point, _) => point.y,
                    name: 'Gyro Z',
                    color: Colors.blue,
                    width: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}