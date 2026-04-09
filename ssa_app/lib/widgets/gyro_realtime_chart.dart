// ============================================
// File: widgets/gyro_realtime_chart.dart (FIXED)
// ============================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../providers/sensor_data_provider.dart';
import '../models/data_models.dart';

class GyroRealtimeChart extends StatelessWidget {
  const GyroRealtimeChart({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, provider, child) {
        
        // Mengambil data langsung dari provider — stable references.
        // _handleDiffUpdate now uses immutable assignment, so lists are already
        // stable. No extra List.from() copy needed (Syncfusion creates its own internal copy).
        final xData = provider.gyroXData;
        final yData = provider.gyroYData;
        final zData = provider.gyroZData;

        // Debug print (gunakan list hasil copy)
        // debugPrint("Chart Points: ${xData.length}");
        
        return Card(
          color: Colors.white,
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Realtime Gyro (5s)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          // Gunakan xData.length bukan provider.gyroXData.length
                          'Points: ${xData.length}', 
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: provider.stabilityScore > 80 ? Colors.green : 
                               provider.stabilityScore > 50 ? Colors.orange : Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Score: ${provider.stabilityScore.toInt()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // /// --- PERBAIKAN 2: CEK KEKOSONGAN PADA HASIL COPY ---
                Expanded(
                  child: xData.isEmpty
                      ? _buildPlaceholder()
                      : _buildChart(xData, yData, zData), // Kirim list copy, bukan provider
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              'Waiting for sensor data...',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  // Ubah parameter untuk menerima List<DataPoint> langsung
  Widget _buildChart(List<DataPoint> xData, List<DataPoint> yData, List<DataPoint> zData) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SfCartesianChart(
          plotAreaBorderWidth: 0,
          backgroundColor: Colors.black,
          
          legend: const Legend(
            isVisible: true,
            position: LegendPosition.bottom,
            textStyle: TextStyle(color: Colors.white70, fontSize: 10),
          ),
          
          primaryXAxis: NumericAxis(
            isVisible: true,
            // Nonaktifkan autoScrollingMode jika bikin lag/jumpy, 
            // tapi ok jika data streaming lancar
            autoScrollingMode: AutoScrollingMode.end, 
            autoScrollingDelta: 5, 
            interval: 1,
            majorGridLines: MajorGridLines(width: 0.5, color: Colors.grey[800]),
            axisLine: const AxisLine(width: 1, color: Colors.grey),
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
            // Format angka (detik)
            numberFormat: NumberFormat('##0.0'), 
          ),
          
          primaryYAxis: NumericAxis(
            isVisible: true,
            minimum: -5.0,
            maximum: 5.0,
            interval: 2.5,
            majorGridLines: MajorGridLines(width: 0.5, color: Colors.grey[800]),
            axisLine: const AxisLine(width: 1, color: Colors.grey),
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
          ),
          
          series: <CartesianSeries>[
            /// --- PERBAIKAN 3: GUNAKAN LIST COPY (xData) ---
            /// Pastikan model DataPoint kamu punya properti 'x' dan 'y' atau 'value'.
            /// Jika DataPoint error "getter x not defined", ganti p.x dengan p.timestamp (jika DateTimeAxis)
            /// atau logika konversi waktu. Asumsi di sini p.x (double waktu) dan p.y (double nilai) ada.
            
            LineSeries<DataPoint, double>(
              dataSource: xData, 
              xValueMapper: (DataPoint p, _) => p.x, // Pastikan DataPoint punya getter .x
              yValueMapper: (DataPoint p, _) => p.y, // Pastikan DataPoint punya getter .y (value)
              name: 'X',
              color: Colors.blueAccent,
              width: 2,
              animationDuration: 0, // Matikan animasi agar realtime mulus
            ),
            LineSeries<DataPoint, double>(
              dataSource: yData,
              xValueMapper: (DataPoint p, _) => p.x,
              yValueMapper: (DataPoint p, _) => p.y,
              name: 'Y',
              color: Colors.redAccent,
              width: 2,
              animationDuration: 0,
            ),
            LineSeries<DataPoint, double>(
              dataSource: zData,
              xValueMapper: (DataPoint p, _) => p.x,
              yValueMapper: (DataPoint p, _) => p.y,
              name: 'Z',
              color: Colors.greenAccent,
              width: 2,
              animationDuration: 0,
            ),
          ],
        ),
      ),
    );
  }
}