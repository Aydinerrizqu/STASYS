import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssa_app/providers/bluetooth_provider.dart';
import 'package:ssa_app/providers/sensor_data_provider.dart';
import 'package:ssa_app/widgets/muzzle_trace_widget.dart';
import 'package:ssa_app/widgets/shot_analysis_panel.dart';
import 'package:ssa_app/widgets/shot_history_list.dart';
import '../../models/data_models.dart';

class GraphTab extends StatefulWidget {
  const GraphTab({super.key});

  @override
  State<GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends State<GraphTab> {
  ShotResult? _selectedShot;
  int? _selectedShotIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothProvider>().initializeBluetooth();
    });
  }

  void _updateSelection(ShotResult? shot) {
    final sensor = context.read<SensorDataProvider>();
    final shots = sensor.sessionShots;

    if (shot != null) {
      final idx = shots.indexOf(shot);
      if (idx >= 0) {
        setState(() {
          _selectedShot = shot;
          _selectedShotIndex = idx;
        });
        return;
      }
    }

    // Fallback: select latest shot
    if (shots.isNotEmpty) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Control Panel — Record / Calibrate / Save
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

            // Real-time Muzzle Trace
            Expanded(
              child: MuzzleTraceWidget(zoom: 0.05),
            ),

            const SizedBox(height: 12),

            // Post-shot analysis
            Expanded(
              child: Consumer<SensorDataProvider>(
                builder: (context, sensor, child) {
                  final shots = sensor.sessionShots;

                  // Auto-select latest shot when shots change
                  if (shots.isNotEmpty && (_selectedShot == null || !shots.contains(_selectedShot))) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _updateSelection(shots.last);
                    });
                  }

                  if (shots.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.analytics_outlined, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 8),
                          Text(
                            'No shots recorded yet',
                            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      Expanded(
                        flex: 3,
                        child: ShotAnalysisPanel(
                          shot: _selectedShot,
                          shotIndex: _selectedShotIndex,
                          getScoreColor: _getScoreColor,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: ShotHistoryList(
                          shots: shots,
                          selectedShot: _selectedShot,
                          onShotSelected: _updateSelection,
                          getScoreColor: _getScoreColor,
                          formatTime: _formatTime,
                          formatScore: (s) => s.toInt().toString(),
                        ),
                      ),
                    ],
                  );
                },
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
