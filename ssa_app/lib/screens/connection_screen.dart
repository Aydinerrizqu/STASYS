import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../theme/app_theme.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize BLE and start scan on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
  }

  void _startScan() async {
    final btProvider = context.read<BluetoothProvider>();
    await btProvider.startScan();
  }

  void _connectDevice(BluetoothDevice device) async {
    final btProvider = context.read<BluetoothProvider>();
    final settings = context.read<SettingsProvider>();
    final sensor = context.read<SensorDataProvider>();
    _showConnectingDialog(device.platformName.isNotEmpty
        ? device.platformName
        : 'STASYS-1');

    // Disable demo mode when connecting to real device
    settings.setDemoMode(false);
    sensor.setDemoMode(false);

    bool success = await btProvider.connectToDevice(device);
    if (mounted) {
      Navigator.of(context).pop();
      if (success) {
        context.go('/tracking');
      }
    }
  }

  void _showConnectingDialog(String deviceName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: StsysTheme.surfaceContainerHigh,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: StsysTheme.primary),
            const SizedBox(height: 24),
            Text(
              'CONNECTING',
              style: StsysText.labelBold.copyWith(color: StsysTheme.primary),
            ),
            const SizedBox(height: 8),
            Text(deviceName, style: StsysText.body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _onExploreApp() {
    final settings = context.read<SettingsProvider>();
    final sensor = context.read<SensorDataProvider>();
    settings.setDemoMode(true);
    sensor.setDemoMode(true);
    context.go('/tracking');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothProvider>(
      builder: (context, btProvider, _) {
        return Scaffold(
          backgroundColor: StsysTheme.surfaceContainerLowest,
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) {
                          return StsysTheme.tacticalGradient.createShader(bounds);
                        },
                        child: const Text(
                          'STASYS',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                      const Spacer(),
                      StatusBadge(
                        isConnected: btProvider.isConnected,
                        deviceName: btProvider.isConnected
                            ? btProvider.connectedDeviceName
                            : null,
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _buildStatusCard(btProvider),
                        const SizedBox(height: 16),
                        _buildScanButton(btProvider),
                        const SizedBox(height: 16),
                        Expanded(child: _buildDeviceList(btProvider)),
                      ],
                    ),
                  ),
                ),

                // Explore App button
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: _onExploreApp,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: StsysTheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: StsysTheme.outlineVariant.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.explore,
                                color: StsysTheme.primary.withValues(alpha: 0.7),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'EXPLORE APP',
                                style: TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: StsysTheme.primary.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(BluetoothProvider btProvider) {
    String statusText;
    Color statusColor;

    if (btProvider.isConnected) {
      statusText = 'CONNECTED';
      statusColor = const Color(0xFF4CAF50);
    } else if (btProvider.isScanning) {
      statusText = 'SCANNING FOR STASYS-1...';
      statusColor = const Color(0xFFFF9800);
    } else {
      statusText = 'NOT CONNECTED';
      statusColor = StsysTheme.error;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: statusColor,
                  ),
                ),
                if (btProvider.isConnected)
                  Text(
                    btProvider.connectedDeviceName,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: StsysTheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton(BluetoothProvider btProvider) {
    return GestureDetector(
      onTap: btProvider.isScanning ? () => btProvider.stopScan() : _startScan,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: StsysTheme.tacticalGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (btProvider.isScanning)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: StsysTheme.onPrimary,
                ),
              )
            else
              const Icon(Icons.bluetooth_searching, color: StsysTheme.onPrimary, size: 20),
            const SizedBox(width: 8),
            Text(
              btProvider.isScanning ? 'SCANNING...' : 'SCAN BLE DEVICES',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: StsysTheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(BluetoothProvider btProvider) {
    if (btProvider.isScanning && btProvider.devicesList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: StsysTheme.primary, strokeWidth: 2),
            const SizedBox(height: 16),
            Text(
              'SEARCHING FOR STASYS-1...',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                letterSpacing: 2,
                color: StsysTheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    if (btProvider.devicesList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 48, color: StsysTheme.onSurface.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              'NO STASYS-1 FOUND',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: StsysTheme.onSurface.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure your XIAO nRF52840 Sense\nis powered on and advertising',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: StsysTheme.onSurface.withValues(alpha: 0.3),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: btProvider.devicesList.length,
      itemBuilder: (context, index) {
        final result = btProvider.devicesList[index];
        final device = result.device;
        return _DeviceCard(
          device: device,
          onTap: () => _connectDevice(device),
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final BluetoothDevice device;
  final VoidCallback onTap;

  const _DeviceCard({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: StsysTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: StsysTheme.outlineVariant.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: StsysTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.bluetooth,
                color: StsysTheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.platformName.isNotEmpty ? device.platformName : 'STASYS-1',
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: StsysTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.remoteId.str,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: StsysTheme.primary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: StsysTheme.onSurface.withValues(alpha: 0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
