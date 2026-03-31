// ============================================
// File: widgets/gyro_realtime_chart.dart
// Dark theme real-time gyro chart
// ============================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../providers/sensor_data_provider.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';

class GyroRealtimeChart extends StatelessWidget {
  const GyroRealtimeChart({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, provider, child) {
        final xData = List<DataPoint>.from(provider.gyroXData);
        final yData = List<DataPoint>.from(provider.gyroYData);
        final zData = List<DataPoint>.from(provider.gyroZData);

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
                        Icon(Icons.show_chart, color: AppTheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Gyroscope',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.getScoreColor(provider.stabilityScore).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.getScoreColor(provider.stabilityScore).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'Score: ${provider.stabilityScore.toInt()}',
                        style: TextStyle(
                          color: AppTheme.getScoreColor(provider.stabilityScore),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Legend
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _legendDot('X', const Color(0xFF4285F4)),
                    const SizedBox(width: 12),
                    _legendDot('Y', const Color(0xFFEA4335)),
                    const SizedBox(width: 12),
                    _legendDot('Z', const Color(0xFF34A853)),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Chart
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
                  child: xData.isEmpty
                      ? _buildPlaceholder()
                      : _buildChart(xData, yData, zData),
                ),
              ),
            ],
          ),
        );
      },
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
        Text(
          label,
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(
              'Waiting for sensor data...',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(List<DataPoint> xData, List<DataPoint> yData, List<DataPoint> zData) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SfCartesianChart(
          plotAreaBorderWidth: 0,
          backgroundColor: AppTheme.background,
          legend: const Legend(isVisible: false),
          primaryXAxis: NumericAxis(
            isVisible: true,
            autoScrollingMode: AutoScrollingMode.end,
            autoScrollingDelta: 5,
            interval: 1,
            majorGridLines: MajorGridLines(width: 0.5, color: Colors.grey[800]),
            axisLine: const AxisLine(width: 1, color: Color(0xFF2A2A4A)),
            labelStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 9),
            numberFormat: NumberFormat('##0.0'),
          ),
          primaryYAxis: NumericAxis(
            isVisible: true,
            minimum: -5.0,
            maximum: 5.0,
            interval: 2.5,
            majorGridLines: MajorGridLines(width: 0.5, color: Colors.grey[800]),
            axisLine: const AxisLine(width: 1, color: Color(0xFF2A2A4A)),
            labelStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 9),
          ),
          series: <CartesianSeries>[
            LineSeries<DataPoint, double>(
              dataSource: xData,
              xValueMapper: (DataPoint p, _) => p.x,
              yValueMapper: (DataPoint p, _) => p.y,
              name: 'X',
              color: const Color(0xFF4285F4),
              width: 2,
              animationDuration: 0,
            ),
            LineSeries<DataPoint, double>(
              dataSource: yData,
              xValueMapper: (DataPoint p, _) => p.x,
              yValueMapper: (DataPoint p, _) => p.y,
              name: 'Y',
              color: const Color(0xFFEA4335),
              width: 2,
              animationDuration: 0,
            ),
            LineSeries<DataPoint, double>(
              dataSource: zData,
              xValueMapper: (DataPoint p, _) => p.x,
              yValueMapper: (DataPoint p, _) => p.y,
              name: 'Z',
              color: const Color(0xFF34A853),
              width: 2,
              animationDuration: 0,
            ),
          ],
        ),
      ),
    );
  }
}
