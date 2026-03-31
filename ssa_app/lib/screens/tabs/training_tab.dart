// ============================================
// File: screens/tabs/training_tab.dart
// Live Training View — redesigned dark theme
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bluetooth_provider.dart';
import '../../providers/sensor_data_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gyro_realtime_chart.dart';
import '../../widgets/muzzle_trace_widget.dart';

class TrainingTab extends StatefulWidget {
  const TrainingTab({super.key});

  @override
  State<TrainingTab> createState() => _TrainingTabState();
}

class _TrainingTabState extends State<TrainingTab> {
  int _selectedView = 0; // 0 = Gyro, 1 = Trace

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
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),

            // Connection status bar
            _buildConnectionBar(),

            const SizedBox(height: 12),

            // Control panel
            _buildControlPanel(),

            const SizedBox(height: 12),

            // Chart/Trace toggle
            _buildViewToggle(),

            const SizedBox(height: 12),

            // Chart area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: IndexedStack(
                  index: _selectedView,
                  children: const [
                    GyroRealtimeChart(),
                    MuzzleTraceWidget(zoom: 0.05),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<SensorDataProvider>(
      builder: (context, sensorData, child) {
        final score = sensorData.stabilityScore;
        final scoreColor = AppTheme.getScoreColor(score);
        final scoreLabel = AppTheme.getScoreLabel(score);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Live Training',
                    style: AppTheme.title,
                  ),
                  const SizedBox(height: 2),
                  Consumer<SettingsProvider>(
                    builder: (context, settings, _) {
                      return Row(
                        children: [
                          _buildChip(settings.firearmType.displayName, AppTheme.primary.withValues(alpha: 0.15), AppTheme.primary),
                          const SizedBox(width: 6),
                          _buildChip(settings.trainingMode.displayName, AppTheme.secondary.withValues(alpha: 0.15), AppTheme.secondary),
                        ],
                      );
                    },
                  ),
                ],
              ),
              // Live score badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: scoreColor.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      '${score.toInt()}',
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      scoreLabel.toUpperCase(),
                      style: TextStyle(
                        color: scoreColor.withValues(alpha: 0.8),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChip(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildConnectionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Consumer<BluetoothProvider>(
        builder: (context, btProvider, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: AppTheme.cardDecoration(),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: btProvider.isConnected ? AppTheme.success : AppTheme.textTertiary,
                    boxShadow: btProvider.isConnected
                        ? [
                            BoxShadow(
                              color: AppTheme.success.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    btProvider.isConnected
                        ? btProvider.selectedDevice?.name ?? 'STASYS Device'
                        : 'No device connected',
                    style: TextStyle(
                      color: btProvider.isConnected ? AppTheme.textPrimary : AppTheme.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => _showDeviceList(context, btProvider),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    btProvider.isConnected ? 'Disconnect' : 'Connect',
                    style: TextStyle(
                      color: btProvider.isConnected ? AppTheme.error : AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Consumer<SensorDataProvider>(
        builder: (context, sensorData, child) {
          return Row(
            children: [
              Expanded(child: _buildActionButton(
                icon: sensorData.isRecording ? Icons.stop : Icons.fiber_manual_record,
                label: sensorData.isRecording ? 'Stop' : 'Record',
                color: sensorData.isRecording ? AppTheme.error : AppTheme.primary,
                onTap: () => sensorData.toggleRecording(),
                enabled: context.read<BluetoothProvider>().isConnected,
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildActionButton(
                icon: Icons.tune,
                label: sensorData.isCalibrating ? 'Calibrating...' : 'Calibrate',
                color: AppTheme.secondary,
                onTap: () => sensorData.startCalibration(),
                enabled: context.read<BluetoothProvider>().isConnected && !sensorData.isCalibrating,
                isLoading: sensorData.isCalibrating,
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildActionButton(
                icon: Icons.save_outlined,
                label: 'Save',
                color: AppTheme.accent,
                onTap: () async {
                  final scaffold = ScaffoldMessenger.of(context);
                  try {
                    await sensorData.saveCurrentSession();
                    if (mounted) {
                      scaffold.showSnackBar(
                        SnackBar(
                          content: const Text('Session saved successfully!'),
                          backgroundColor: AppTheme.success.withValues(alpha: 0.9),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      scaffold.showSnackBar(
                        SnackBar(
                          content: Text('Failed to save: $e'),
                          backgroundColor: AppTheme.error.withValues(alpha: 0.9),
                        ),
                      );
                    }
                  }
                },
                enabled: context.read<BluetoothProvider>().isConnected && sensorData.isRecording,
              )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.15)
              : AppTheme.surfaceLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? color.withValues(alpha: 0.4) : AppTheme.cardBorder,
            width: 1,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
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
                  color: color.withValues(alpha: 0.6),
                ),
              )
            else
              Icon(
                icon,
                size: 18,
                color: enabled ? color : AppTheme.textTertiary,
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: enabled ? color : AppTheme.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          children: [
            Expanded(child: _toggleBtn(0, 'Gyroscope', Icons.show_chart)),
            Expanded(child: _toggleBtn(1, 'Muzzle Trace', Icons.gps_fixed)),
          ],
        ),
      ),
    );
  }

  Widget _toggleBtn(int index, String label, IconData icon) {
    final isSelected = _selectedView == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedView = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeviceList(BuildContext context, BluetoothProvider btProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DeviceListSheet(btProvider: btProvider),
    );
  }
}

class _DeviceListSheet extends StatelessWidget {
  final BluetoothProvider btProvider;

  const _DeviceListSheet({required this.btProvider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Select Device', style: AppTheme.title),
          const SizedBox(height: 4),
          Text(
            'Choose a paired STASYS device',
            style: AppTheme.subtitle,
          ),
          const SizedBox(height: 16),
          if (btProvider.isScanning)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (btProvider.devicesList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.bluetooth_searching, size: 48, color: AppTheme.textTertiary),
                    const SizedBox(height: 12),
                    Text('No devices found', style: AppTheme.subtitle),
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: btProvider.devicesList.length,
                itemBuilder: (context, index) {
                  final device = btProvider.devicesList[index];
                  final isSTASYS = device.name?.contains('STASYS') ?? false;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: AppTheme.cardDecoration(),
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSTASYS
                              ? AppTheme.primary.withValues(alpha: 0.15)
                              : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.bluetooth,
                          color: isSTASYS ? AppTheme.primary : AppTheme.textSecondary,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        device.name ?? 'Unknown Device',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        device.address,
                        style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                      ),
                      trailing: isSTASYS
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'STASYS',
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        btProvider.connectToDevice(device);
                      },
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: btProvider.isScanning ? null : () => btProvider.startScan(),
              icon: const Icon(Icons.search, size: 18),
              label: Text(btProvider.isScanning ? 'Scanning...' : 'Scan for Devices'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
