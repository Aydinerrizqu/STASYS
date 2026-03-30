import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssa_app/providers/bluetooth_provider.dart';
import 'package:ssa_app/providers/sensor_data_provider.dart';
import 'package:ssa_app/widgets/control_panel.dart';
import 'package:ssa_app/widgets/status_bar.dart';
import '../../widgets/gyro_realtime_chart.dart';
import '../../widgets/muzzle_trace_widget.dart';

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
            // Status Bar
            Consumer<BluetoothProvider>(
              builder: (context, btProvider, child) {
                return StatusBar(
                  isConnected: btProvider.isConnected,
                  deviceName: btProvider.selectedDevice?.name ?? 'No Device',
                  onConnect: () => _showDeviceList(context, btProvider),
                  onDisconnect: () => btProvider.disconnect(),
                );
              },
            ),
            const SizedBox(height: 16),

            // Control Panel
            Consumer<SensorDataProvider>(
              builder: (context, sensorData, child) {
                return ControlPanel(
                  isRecording: sensorData.isRecording,
                  isCalibrating: sensorData.isCalibrating,
                  onRecord: () => sensorData.toggleRecording(),
                  onCalibrate: () => sensorData.startCalibration(),
                  onSave: () async {
                    try {
                      await sensorData.saveCurrentSession();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Session saved successfully!')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save session: $e')),
                        );
                      }
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 16),

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

  // Fungsi helper untuk menampilkan dialog pemilihan perangkat Bluetooth
  void _showDeviceList(BuildContext context, BluetoothProvider btProvider) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Select a Device'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Daftar perangkat yang sudah di-bond
                Expanded(
                  child: Consumer<BluetoothProvider>(
                    builder: (context, provider, child) {
                      if (provider.isScanning) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (provider.devicesList.isEmpty) {
                        return const Center(child: Text('No devices found. Try scanning.'));
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: provider.devicesList.length,
                        itemBuilder: (context, index) {
                          final device = provider.devicesList[index];
                          return ListTile(
                            title: Text(device.name ?? 'Unknown Device'),
                            subtitle: Text(device.address),
                            onTap: () async {
                              Navigator.of(dialogContext).pop(); // Tutup dialog
                              bool success = await provider.connectToDevice(device);
                              if (!success && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Failed to connect to device.')),
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(),
                // Tombol untuk scan perangkat baru
                ElevatedButton.icon(
                  onPressed: () {
                    btProvider.startScan();
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Scan for new devices'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
}