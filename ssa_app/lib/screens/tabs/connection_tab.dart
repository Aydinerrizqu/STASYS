// ============================================
// File: screens/tabs/connection_tab.dart
// Bluetooth Connection — scan, pair, authenticate
// ============================================
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:provider/provider.dart';
import '../../providers/bluetooth_provider.dart';
import '../../theme/app_theme.dart';

class ConnectionTab extends StatefulWidget {
  const ConnectionTab({super.key});

  @override
  State<ConnectionTab> createState() => _ConnectionTabState();
}

class _ConnectionTabState extends State<ConnectionTab> {
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothProvider>().initializeBluetooth();
    });
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    await context.read<BluetoothProvider>().startScan();
    setState(() => _isScanning = false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    final btProvider = context.read<BluetoothProvider>();

    // Show connecting dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ConnectingDialog(device: device),
    );

    final success = await btProvider.connectToDevice(device);

    if (mounted) {
      Navigator.pop(context); // close dialog

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.success),
                const SizedBox(width: 10),
                Text('Connected to ${device.name ?? "STASYS"}'),
              ],
            ),
            backgroundColor: AppTheme.success.withValues(alpha: 0.9),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: AppTheme.error),
                const SizedBox(width: 10),
                const Text('Connection failed. Check device and try again.'),
              ],
            ),
            backgroundColor: AppTheme.error.withValues(alpha: 0.9),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Consumer<BluetoothProvider>(
          builder: (context, btProvider, child) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header
                const Text('Connection', style: AppTheme.title),
                const SizedBox(height: 4),
                Text(
                  'Connect your STASYS device',
                  style: AppTheme.subtitle,
                ),

                const SizedBox(height: 24),

                // Connection status card
                _buildStatusCard(btProvider),

                const SizedBox(height: 16),

                // Scan button
                _buildScanSection(btProvider),

                const SizedBox(height: 16),

                // Devices list
                _buildDevicesList(btProvider),

                const SizedBox(height: 24),

                // Pairing guide
                _buildPairingGuide(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusCard(BluetoothProvider btProvider) {
    final isConnected = btProvider.isConnected;
    final isAuth = btProvider.isAuthenticated;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected
            ? AppTheme.success.withValues(alpha: 0.1)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? AppTheme.success.withValues(alpha: 0.3)
              : AppTheme.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isConnected
                  ? AppTheme.success.withValues(alpha: 0.2)
                  : AppTheme.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: isConnected ? AppTheme.success : AppTheme.textTertiary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected
                      ? btProvider.selectedDevice?.name ?? 'STASYS Device'
                      : 'Not Connected',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isAuth
                            ? AppTheme.success
                            : isConnected
                                ? AppTheme.warning
                                : AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isAuth
                          ? 'Authenticated'
                          : isConnected
                              ? 'Authenticating...'
                              : 'Waiting for connection',
                      style: TextStyle(
                        color: isAuth
                            ? AppTheme.success
                            : isConnected
                                ? AppTheme.warning
                                : AppTheme.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isConnected)
            IconButton(
              onPressed: () => btProvider.disconnect(),
              icon: Icon(Icons.link_off, color: AppTheme.error),
              tooltip: 'Disconnect',
            ),
        ],
      ),
    );
  }

  Widget _buildScanSection(BluetoothProvider btProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isScanning || btProvider.isScanning
                      ? 'Scanning for devices...'
                      : 'Bluetooth Devices',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${btProvider.devicesList.length} device${btProvider.devicesList.length != 1 ? 's' : ''} found',
                  style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _isScanning || btProvider.isScanning ? null : _startScan,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: (_isScanning || btProvider.isScanning)
                    ? AppTheme.textTertiary.withValues(alpha: 0.2)
                    : AppTheme.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: (_isScanning || btProvider.isScanning)
                    ? null
                    : [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                        ),
                      ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isScanning || btProvider.isScanning) ...[
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Scanning...',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else ...[
                    Icon(Icons.search, color: AppTheme.background, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Scan',
                      style: TextStyle(
                        color: AppTheme.background,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList(BluetoothProvider btProvider) {
    final devices = btProvider.devicesList;

    if (devices.isEmpty && !btProvider.isScanning) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          children: [
            Icon(
              Icons.bluetooth_searching,
              size: 48,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              'No paired devices found',
              style: AppTheme.subtitle,
            ),
            const SizedBox(height: 4),
            Text(
              'Tap "Scan" to search or pair a device',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'PAIRED DEVICES',
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
        ...devices.map((device) => _buildDeviceItem(device)),
      ],
    );
  }

  Widget _buildDeviceItem(BluetoothDevice device) {
    final isSTASYS = device.name?.contains('STASYS') ?? false;
    final btProvider = context.read<BluetoothProvider>();
    final isThisDevice = btProvider.selectedDevice?.address == device.address;
    final isConnected = btProvider.isConnected && isThisDevice;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.cardDecoration(
        borderColor: isConnected ? AppTheme.success : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isSTASYS
                ? AppTheme.primary.withValues(alpha: 0.15)
                : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.bluetooth,
            color: isSTASYS ? AppTheme.primary : AppTheme.textSecondary,
            size: 22,
          ),
        ),
        title: Text(
          device.name ?? 'Unknown Device',
          style: TextStyle(
            color: isConnected ? AppTheme.success : AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          device.address,
          style: TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 12,
          ),
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
        onTap: isConnected ? null : () => _connect(device),
      ),
    );
  }

  Widget _buildPairingGuide() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.warning, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Pairing Guide',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _guideStep('1', 'Make sure your STASYS device is powered ON (LED blinking)'),
          const SizedBox(height: 6),
          _guideStep('2', 'First time? Go to Phone Settings > Bluetooth and pair STASYS-V2-XXXX'),
          const SizedBox(height: 6),
          _guideStep('3', 'Tap "Scan" to find your device, then tap to connect'),
          const SizedBox(height: 6),
          _guideStep('4', 'Authentication happens automatically — no PIN needed'),
        ],
      ),
    );
  }

  Widget _guideStep(String num, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              num,
              style: TextStyle(
                color: AppTheme.warning,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================
// Connecting Dialog with auth progress
// ============================================
class _ConnectingDialog extends StatefulWidget {
  final BluetoothDevice device;

  const _ConnectingDialog({required this.device});

  @override
  State<_ConnectingDialog> createState() => _ConnectingDialogState();
}

class _ConnectingDialogState extends State<_ConnectingDialog> {
  String _status = 'Connecting...';
  int _step = 0;

  final List<String> _steps = [
    'Connecting...',
    'Device connected',
    'Waiting for authentication...',
    'Sending challenge...',
    'Verifying response...',
    'Authenticated!',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _simulateProgress();
    });
  }

  void _simulateProgress() async {
    final btProvider = context.read<BluetoothProvider>();

    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      if (btProvider.isAuthenticated) {
        setState(() {
          _step = 5;
          _status = _steps[5];
        });
        break;
      }

      if (btProvider.isConnected && _step < 4) {
        setState(() {
          _step = 4;
          _status = _steps[4];
        });
      } else if (_step < i ~/ 5 + 1 && i ~/ 5 + 1 < 4) {
        setState(() {
          _step = i ~/ 5 + 1;
          _status = _steps[_step];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final btProvider = context.read<BluetoothProvider>();

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                btProvider.isAuthenticated
                    ? Icons.check_circle
                    : btProvider.isConnected
                        ? Icons.lock_open
                        : Icons.bluetooth,
                color: AppTheme.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.device.name ?? 'STASYS Device',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value: (_step + 1) / _steps.length,
                backgroundColor: AppTheme.cardBorder,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            if (btProvider.isAuthenticated)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user, color: AppTheme.success, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Authentication Successful',
                    style: TextStyle(color: AppTheme.success, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            if (!btProvider.isConnected && !btProvider.isAuthenticated)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: AppTheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
