import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssa_app/providers/bluetooth_provider.dart';
import 'package:ssa_app/providers/sensor_data_provider.dart';
import 'package:ssa_app/widgets/gyro_realtime_chart.dart';
import 'package:ssa_app/widgets/muzzle_trace_widget.dart';

class GraphTab extends StatefulWidget {
  const GraphTab({super.key});

  @override
  State<GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends State<GraphTab> {
  int _selectedChartIndex = 0; // 0=Gyro, 1=Muzzle Trace

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothProvider>().initializeBluetooth();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Control Panel — Record / Calibrate / Save (atas langsung)
            Consumer<SensorDataProvider>(
              builder: (context, sensorData, child) {
                return Consumer<BluetoothProvider>(
                  builder: (context, btProvider, child) {
                    return Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: sensorData.isRecording ? Icons.stop : Icons.fiber_manual_record,
                            label: sensorData.isRecording ? 'Stop' : 'Record',
                            color: sensorData.isRecording ? Colors.red : Colors.blue,
                            enabled: btProvider.isConnected && btProvider.isAuthenticated,
                            onTap: () => sensorData.toggleRecording(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: sensorData.isCalibrating ? Icons.sync : Icons.tune,
                            label: sensorData.isCalibrating
                                ? 'Calibrating... (${sensorData.calibrationSamplesCount}/${sensorData.samplesToCollect})'
                                : 'Calibrate',
                            color: Colors.orange,
                            enabled: btProvider.isConnected && btProvider.isAuthenticated && !sensorData.isCalibrating,
                            isLoading: sensorData.isCalibrating,
                            onTap: () {
                              debugPrint("[GRAPH] Calibrate button tapped — isAuth: ${btProvider.isAuthenticated}");
                              if (!btProvider.isAuthenticated) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Connect and authenticate first!')),
                                );
                                return;
                              }
                              debugPrint("[GRAPH] Calling sensorData.startCalibration()...");
                              sensorData.startCalibration();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.save_outlined,
                            label: 'Save',
                            color: Colors.green,
                            enabled: btProvider.isConnected && sensorData.canSaveSession,
                            onTap: () async {
                              final scaffold = ScaffoldMessenger.of(context);
                              try {
                                await sensorData.saveCurrentSession();
                                if (mounted) {
                                  scaffold.showSnackBar(
                                    const SnackBar(content: Text('Session saved successfully!')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  scaffold.showSnackBar(
                                    SnackBar(content: Text('Failed to save session: $e')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 12),

            // Chart toggle
            _buildChartToggle(),
            const SizedBox(height: 12),

            // Chart area
            Expanded(
              child: IndexedStack(
                index: _selectedChartIndex,
                children: const [
                  GyroRealtimeChart(),
                  MuzzleTraceWidget(zoom: 0.05),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleButton(0, 'Gyro', Icons.show_chart),
          _toggleButton(1, 'Trace', Icons.gps_fixed),
        ],
      ),
    );
  }

  Widget _toggleButton(int index, String label, IconData icon) {
    final isSelected = _selectedChartIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedChartIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Action Button Widget
// ============================================
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final bool isLoading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? color : Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                icon,
                size: 18,
                color: enabled ? Colors.white : Colors.grey[500],
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.grey[500],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}