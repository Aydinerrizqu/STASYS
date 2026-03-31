// ============================================
// File: screens/connection_page.dart
// STASYS Connection Splash Screen
// ============================================
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../providers/bluetooth_provider.dart';
import '../theme/app_theme.dart';
import 'main_shell.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isScanning = false;
  String _statusText = 'Connect Your Device';
  String _deviceStatus = 'Looking for STASYS...';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initBluetooth();
    });
  }

  void _initBluetooth() {
    final btProvider = context.read<BluetoothProvider>();
    btProvider.initializeBluetooth(context: context);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _statusText = 'Scanning...';
      _deviceStatus = 'Looking for STASYS devices';
    });

    final btProvider = context.read<BluetoothProvider>();
    await btProvider.startScan(context: context);

    setState(() {
      _isScanning = false;
      _statusText = 'Connect Your Device';
      _deviceStatus = 'Select a device to connect';
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _statusText = 'Connecting...';
      _deviceStatus = 'Establishing connection...';
    });

    final btProvider = context.read<BluetoothProvider>();
    final success = await btProvider.connectToDevice(device);

    if (success && mounted) {
      _statusText = 'Connected!';
      _deviceStatus = 'STASYS device connected';
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      }
    } else if (mounted) {
      setState(() {
        _statusText = 'Connection Failed';
        _deviceStatus = 'Could not connect to device';
      });
    }
  }

  void _showDeviceList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DeviceListSheet(
        onConnect: _connectToDevice,
        onScan: _startScan,
      ),
    );
  }

  void _exploreApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const MainShell(isDemoMode: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Consumer<BluetoothProvider>(
          builder: (context, btProvider, child) {
            // Auto-navigate if connected
            if (btProvider.isConnected && btProvider.selectedDevice != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainShell()),
                );
              });
            }

            return Stack(
              children: [
                // Background gradient overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.2,
                        colors: [
                          AppTheme.primary.withValues(alpha: 0.05),
                          AppTheme.background,
                        ],
                      ),
                    ),
                  ),
                ),

                // Main content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),

                      // Logo / Brand
                      _buildLogo(),

                      const SizedBox(height: 16),

                      // Brand text
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withValues(alpha: 0.7),
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          'STASYS',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 4,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Shooter Stability Analysis System',
                        style: AppTheme.subtitle.copyWith(
                          color: AppTheme.textSecondary.withValues(alpha: 0.7),
                          letterSpacing: 1,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const Spacer(flex: 1),

                      // Bluetooth wave animation
                      _buildBluetoothAnimation(),

                      const SizedBox(height: 40),

                      // Status text
                      Text(
                        _statusText,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        _deviceStatus,
                        style: AppTheme.subtitle,
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 32),

                      // Connect button
                      if (!btProvider.isConnected) ...[
                        _buildConnectButton(btProvider),
                        const SizedBox(height: 16),
                        _buildScanButton(),
                      ],

                      // Connected state
                      if (btProvider.isConnected) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: AppTheme.success.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bluetooth_connected,
                                color: AppTheme.success,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                btProvider.selectedDevice?.name ?? 'STASYS',
                                style: TextStyle(
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Entering app...',
                          style: AppTheme.subtitle,
                        ),
                      ],

                      const Spacer(flex: 2),

                      // Explore App button (bottom right)
                      _buildExploreButton(),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surface,
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.15 * _pulseAnimation.value),
                blurRadius: 30 * _pulseAnimation.value,
                spreadRadius: 5 * _pulseAnimation.value,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.track_changes,
              size: 48,
              color: AppTheme.primary.withValues(alpha: 0.8 + 0.2 * _pulseAnimation.value),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBluetoothAnimation() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return SizedBox(
          width: 200,
          height: 80,
          child: CustomPaint(
            painter: _BluetoothWavePainter(
              progress: _pulseAnimation.value,
              color: AppTheme.primary,
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectButton(BluetoothProvider btProvider) {
    return GestureDetector(
      onTap: _showDeviceList,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth, color: AppTheme.background, size: 22),
            SizedBox(width: 10),
            Text(
              'Connect Device',
              style: TextStyle(
                color: AppTheme.background,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanButton() {
    return TextButton.icon(
      onPressed: _startScan,
      icon: _isScanning
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.textSecondary,
              ),
            )
          : const Icon(Icons.refresh, size: 16),
      label: Text(_isScanning ? 'Scanning...' : 'Scan for Devices'),
    );
  }

  Widget _buildExploreButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _exploreApp,
        child: Text(
          'Explore App  →',
          style: TextStyle(
            color: AppTheme.textSecondary.withValues(alpha: 0.6),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ============================================
// Bluetooth Wave Custom Painter
// ============================================
class _BluetoothWavePainter extends CustomPainter {
  final double progress;
  final Color color;

  _BluetoothWavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final waveProgress = (progress + i * 0.2) % 1.0;
      final opacity = (1.0 - waveProgress) * 0.4;
      final radius = waveProgress * maxRadius;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(center, radius, paint);
    }

    // Center Bluetooth icon
    final iconPaint = Paint()
      ..color = color.withValues(alpha: 0.6 + progress * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final cx = center.dx;
    final cy = center.dy;

    // Draw simple bluetooth B shape approximation
    canvas.drawLine(Offset(cx - 10, cy - 15), Offset(cx + 10, cy + 15), iconPaint);
    canvas.drawLine(Offset(cx + 10, cy + 15), Offset(cx - 10, cy + 15), iconPaint);
    canvas.drawLine(Offset(cx - 10, cy - 15), Offset(cx - 10, cy + 15), iconPaint);

    // Arrow heads
    canvas.drawLine(Offset(cx - 10, cy - 15), Offset(cx - 5, cy - 10), iconPaint);
    canvas.drawLine(Offset(cx - 10, cy - 15), Offset(cx - 3, cy - 15), iconPaint);
    canvas.drawLine(Offset(cx + 10, cy + 15), Offset(cx + 5, cy + 10), iconPaint);
    canvas.drawLine(Offset(cx + 10, cy + 15), Offset(cx + 3, cy + 15), iconPaint);
  }

  @override
  bool shouldRepaint(covariant _BluetoothWavePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// ============================================
// Device List Bottom Sheet
// ============================================
class _DeviceListSheet extends StatelessWidget {
  final Future<void> Function(BluetoothDevice) onConnect;
  final VoidCallback onScan;

  const _DeviceListSheet({
    required this.onConnect,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothProvider>(
      builder: (context, btProvider, child) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
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
              const SizedBox(height: 20),

              if (btProvider.isScanning)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (btProvider.devicesList.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 48,
                        color: AppTheme.textTertiary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No devices found',
                        style: AppTheme.subtitle,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Make sure your STASYS device is powered on\nand in pairing mode (LED blinking)',
                        style: TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: AppTheme.warning, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'First time? Pair STASYS in your phone\'s Bluetooth Settings first, then it will appear here.',
                                style: TextStyle(color: AppTheme.warning, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35,
                  ),
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
                              color: isSTASYS
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
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
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: isSTASYS
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
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
                            onConnect(device);
                          },
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 16),

              // Scan button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: btProvider.isScanning ? null : onScan,
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

              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }
}
