import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../services/firmware_service.dart';
import '../screens/ota_prompt_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/calibration_flow.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  bool _isScanning = false;
  List<BluetoothDevice> _devices = [];
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySubscription;
  bool _exitDialogOpen = false;
  final FirmwareService _firmwareService = FirmwareService();

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    super.dispose();
  }

  void _startScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _devices = [];
    });

    final bt = FlutterBluetoothSerial.instance;

    // Get already paired devices
    try {
      final bondedDevices = await bt.getBondedDevices();
      if (mounted) {
        setState(() {
          _devices.addAll(
            bondedDevices.where(
              (d) => (d.name ?? '').toLowerCase().contains('stasys'),
            ),
          );
        });
      }
    } catch (_) {}

    // Start discovery
    _discoverySubscription = bt.startDiscovery().listen(
      (result) {
        if (mounted) {
          setState(() {
            final existingIndex = _devices.indexWhere(
              (d) => d.address == result.device.address,
            );
            if (existingIndex < 0 &&
                (result.device.name ?? '').toLowerCase().contains('stasys')) {
              _devices.add(result.device);
            }
          });
        }
      },
      onDone: () {
        if (mounted) setState(() => _isScanning = false);
      },
      onError: (_) {
        if (mounted) setState(() => _isScanning = false);
      },
    );

    // Auto-stop after 12 seconds
    Future.delayed(const Duration(seconds: 12), () {
      _discoverySubscription?.cancel();
      if (mounted) setState(() => _isScanning = false);
    });
  }

  void _stopScan() {
    _discoverySubscription?.cancel();
    setState(() => _isScanning = false);
  }

  void _connectDevice(BluetoothDevice device) async {
    final btProvider = context.read<BluetoothProvider>();
    final settings = context.read<SettingsProvider>();
    final sensor = context.read<SensorDataProvider>();
    _showConnectingDialog(device.name ?? 'Device');

    // Disable demo mode when connecting to real device
    settings.setDemoMode(false);
    sensor.setDemoMode(false);

    await btProvider.connectToDevice(device);
    if (mounted) {
      Navigator.of(context).pop();
      if (btProvider.isConnected && btProvider.isAuthenticated) {
        await _checkFirmwareUpdate(context);
      } else {
        // Connection/auth failed — surface the provider's failure reason
        // (v2 auth failures) so the user gets a readable message.
        final message = btProvider.authError ?? 'Connection failed.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: StsysTheme.error,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  void _showConnectingDialog(String deviceName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: StsysTheme.surfaceContainerHighOf(context),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            CircularProgressIndicator(color: StsysTheme.primaryOf(context)),
            const SizedBox(height: 24),
            Text(
              'CONNECTING',
              style: StsysText.labelBold.copyWith(color: StsysTheme.primaryOf(context)),
            ),
            const SizedBox(height: 8),
            Text(
              deviceName,
              style: StsysText.bodyOf(context),
              textAlign: TextAlign.center,
            ),
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
    // Demo mode skips calibration — go directly to /train
    context.go('/train');
  }

  /// Show mandatory calibration flow after successful BT connection.
  void _showCalibrationFlow() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<SensorDataProvider>(),
        child: const CalibrationFlowDialog(),
      ),
    ).then((_) {
      // After calibration dialog completes, navigate to /train
      if (mounted) context.go('/train');
    });
  }

  Future<void> _checkFirmwareUpdate(BuildContext context) async {
    final bt = context.read<BluetoothProvider>();
    final router = GoRouter.of(context);
    try {
      final currentFw = await bt.getFirmwareVersion();

      if (currentFw == null) {
        // Firmware v2 has no legacy GET_VERSION command — version query
        // unsupported; skip the OTA check and proceed to calibration.
        debugPrint(
          '[BT] Firmware version query unsupported (v2 firmware); skipping OTA check.',
        );
        if (mounted) _showCalibrationFlow();
        return;
      }

      final newFw = await _firmwareService.loadFirmware();

      if (!mounted) return;

      if (currentFw != newFw.version) {
        showDialog(
          // ignore: use_build_context_synchronously — context captured before async gap
          context: context,
          barrierDismissible: false,
          builder: (ctx) => OtaPromptDialog(
            currentVersion: currentFw,
            newVersion: newFw.version,
            onUpdate: () {
              Navigator.of(ctx).pop();
              router.go('/ota-update');
            },
            onSkip: () {
              Navigator.of(ctx).pop();
              // Firmware outdated but user skipped — still require calibration
              _showCalibrationFlow();
            },
          ),
        );
      } else {
        // Firmware up-to-date — require calibration before tracking
        _showCalibrationFlow();
      }
    } catch (e) {
      debugPrint('[BT] Firmware version check failed: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Firmware check error: $e'),
          backgroundColor: StsysTheme.error,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _confirmExit() async {
    if (_exitDialogOpen || !mounted) return;
    _exitDialogOpen = true;
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: Text('Keluar dari STASYS'),
        content: Text('Yakin ingin keluar dari aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('No', style: TextStyle(color: StsysTheme.cyanOf(context))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Yes', style: TextStyle(color: StsysTheme.cyanOf(context))),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (shouldExit == true && mounted) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Consumer<BluetoothProvider>(
        builder: (context, btProvider, _) {
          return Scaffold(
            backgroundColor: const Color(0xFF080B0E),
            body: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  SizedBox(
                    height: 59,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(
                            Icons.gps_fixed,
                            color: StsysTheme.cyanOf(context),
                            size: 22,
                          ),
                          const SizedBox(width: 9),
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                StsysTheme.brandGradient.createShader(bounds),
                            child: const Text(
                              'STASYS',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 2.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          _ConnectionBadge(
                            isConnected: btProvider.isConnected,
                            deviceName: btProvider.isConnected
                                ? btProvider.connectedDeviceName
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildStatusCard(btProvider),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: _buildScanButton(),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _buildDeviceList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: _buildExploreButton(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildExploreButton() {
    return OutlinedButton.icon(
      onPressed: _onExploreApp,
      icon: Icon(Icons.explore_outlined, size: 17),
      label: Text('EXPLORE APP'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: StsysTheme.cyanOf(context),
        side: BorderSide(color: StsysTheme.cyanOf(context), width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.6,
        ),
      ),
    );
  }

  Widget _buildStatusCard(BluetoothProvider btProvider) {
    final isConnected = btProvider.isConnected;
    final color = isConnected ? StsysTheme.cyanOf(context) : StsysTheme.mobileMutedTextOf(context);
    return SizedBox(
      height: 28,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              isConnected ? 'CONNECTED' : 'NOT CONNECTED',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanButton() {
    return Semantics(
      button: true,
      label: _isScanning ? 'Stop scanning for STASYS' : 'Connect to STASYS',
      child: GestureDetector(
        onTap: _isScanning ? _stopScan : _startScan,
        child: Container(
          width: double.infinity,
          height: 48,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: StsysTheme.cyanOf(context),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: StsysTheme.primaryOf(context).withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isScanning)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: const Color(0xFF001519),
                  ),
                )
              else
                const Icon(
                  Icons.bluetooth_searching,
                  color: const Color(0xFF001519),
                  size: 20,
                ),
              const SizedBox(width: 10),
              Text(
                _isScanning ? 'SCANNING...' : 'CONNECT TO STASYS',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  color: const Color(0xFF001519),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_isScanning && _devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: StsysTheme.primaryOf(context),
              strokeWidth: 2,
            ),
            const SizedBox(height: 16),
            Text(
              'SEARCHING FOR DEVICES...',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                letterSpacing: 2,
                color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 48,
              color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.1),
            ),
            const SizedBox(height: 16),
            Text(
              'NO DEVICES FOUND',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure your device is powered on\nand in pairing mode',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.3),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return _DeviceCard(device: device, onTap: () => _connectDevice(device));
      },
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  final bool isConnected;
  final String? deviceName;

  const _ConnectionBadge({required this.isConnected, this.deviceName});

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? StsysTheme.cyanOf(context) : StsysTheme.mobileMutedTextOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'CONNECTED' : 'DISCONNECTED',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: color,
            ),
          ),
        ],
      ),
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
          color: StsysTheme.surfaceContainerLowOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: StsysTheme.outlineVariantOf(context).withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: StsysTheme.primaryOf(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                device.isBonded ? Icons.watch : Icons.bluetooth,
                color: StsysTheme.primaryOf(context),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name ?? 'Unknown Device',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: StsysTheme.onSurfaceOf(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.isBonded ? 'PAIRED' : 'AVAILABLE',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: device.isBonded
                          ? StsysTheme.primaryOf(context).withValues(alpha: 0.6)
                          : StsysTheme.onSurfaceOf(context).withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
