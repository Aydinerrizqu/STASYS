import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';
import '../widgets/device_key_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showDeviceList = false;
  bool _isScanning = false;
  List<BluetoothDevice> _devices = [];
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySubscription;

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

    try {
      final bondedDevices = await bt.getBondedDevices();
      if (mounted) {
        setState(
          () => _devices.addAll(
            bondedDevices.where(
              (d) => (d.name ?? '').toLowerCase().contains('stasys'),
            ),
          ),
        );
      }
    } catch (_) {}

    _discoverySubscription = bt.startDiscovery().listen(
      (result) {
        if (mounted) {
          setState(() {
            if (_devices.indexWhere((d) => d.address == result.device.address) <
                    0 &&
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
    await btProvider.connectToDevice(device);
    if (mounted) setState(() => _showDeviceList = false);
  }

  void _disconnect() {
    context.read<BluetoothProvider>().disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StsysTheme.mobileBackgroundOf(context),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),

            // Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Bluetooth Section
                  _buildSectionHeader('BLUETOOTH'),
                  _buildBluetoothSection(),
                  const SizedBox(height: 24),

                  // Firmware Update Section
                  _buildSectionHeader('FIRMWARE UPDATE'),
                  _buildFirmwareUpdateSection(),
                  const SizedBox(height: 24),

                  // Theme
                  _buildSectionHeader('THEME'),
                  _buildThemeSection(),
                  const SizedBox(height: 24),

                  // Trace Window
                  _buildSectionHeader('TRACE WINDOW'),
                  _buildTraceWindowSection(),
                  const SizedBox(height: 24),

                  // Target Distance
                  _buildSectionHeader('TARGET DISTANCE'),
                  _buildTargetDistanceSection(),
                  const SizedBox(height: 24),

                  // Firearm Type
                  _buildSectionHeader('FIREARM TYPE'),
                  _buildFirearmTypeSection(),
                  const SizedBox(height: 24),

                  // Training Mode
                  _buildSectionHeader('TRAINING MODE'),
                  _buildTrainingModeSection(),
                  const SizedBox(height: 24),
                  const DeviceKeySection(),
                  const SizedBox(height: 100),
                ],
              ),
            ),

            // Device scan overlay
            if (_showDeviceList) _buildDeviceScanOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: StsysTheme.mobileHeaderOf(context, StsysTheme.mobileHeaderSettings),
        border: Border(bottom: BorderSide(color: StsysTheme.mobileBorderOf(context))),
      ),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) {
              return StsysTheme.brandGradient.createShader(bounds);
            },
            child: const Text(
              'STASYS',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              if (!settings.isDemoMode) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: StsysTheme.cyanOf(context).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: StsysTheme.cyanOf(context).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.science_outlined,
                      size: 12,
                      color: StsysTheme.cyanOf(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'DEMO',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: StsysTheme.cyanOf(context),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const Spacer(),
          Consumer<BluetoothProvider>(
            builder: (context, bt, _) {
              return StatusBadge(
                isConnected: bt.isConnected,
                deviceName: bt.isConnected ? bt.connectedDeviceName : null,
                mutedDisconnected: true,
              );
            },
          ),
          const SizedBox(width: 8),
          Consumer<SensorDataProvider>(
            builder: (context, sensor, _) {
              return _BatteryIndicator(level: sensor.batteryLevel);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: StsysTheme.cyanOf(context),
        ),
      ),
    );
  }

  Widget _buildBluetoothSection() {
    return Consumer<BluetoothProvider>(
      builder: (context, btProvider, _) {
        final isConnected = btProvider.isConnected;
        final isAuth = btProvider.isAuthenticated;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: StsysTheme.surfaceContainerLowOf(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Status row
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isAuth
                          ? const Color(0xFF4CAF50)
                          : isConnected
                          ? StsysTheme.cyanOf(context)
                          : StsysTheme.mobileMutedTextOf(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAuth
                              ? 'CONNECTED'
                              : isConnected
                              ? 'CONNECTING...'
                              : 'NOT CONNECTED',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isAuth
                                ? const Color(0xFF4CAF50)
                                : isConnected
                                ? StsysTheme.cyanOf(context)
                                : StsysTheme.mobileMutedTextOf(context),
                          ),
                        ),
                        if (isConnected)
                          Text(
                            btProvider.connectedDeviceName,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              color: StsysTheme.onSurfaceOf(context).withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final settings = context.read<SettingsProvider>();
                        if (settings.isDemoMode) {
                          // Demo mode: redirect to connection screen
                          context.go('/connection');
                          return;
                        }
                        if (_showDeviceList) {
                          setState(() => _showDeviceList = false);
                          _stopScan();
                        } else {
                          setState(() => _showDeviceList = true);
                          _startScan();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: StsysTheme.brandGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _showDeviceList
                                  ? Icons.close
                                  : Icons.bluetooth_searching,
                              color: StsysTheme.onPrimaryOf(context),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isScanning
                                  ? 'SCANNING...'
                                  : _showDeviceList
                                  ? 'CLOSE'
                                  : 'SCAN DEVICES',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                color: StsysTheme.onPrimaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (isConnected) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _disconnect,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: StsysTheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: StsysTheme.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'DISCONNECT',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: StsysTheme.error,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFirmwareUpdateSection() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: StsysTheme.surfaceContainerLowOf(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B3D).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.system_update_alt,
                  color: Color(0xFFFF6B3D),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto-update firmware',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: StsysTheme.onSurfaceOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Langsung update tanpa bertanya',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: settings.autoUpdateFirmware,
                activeTrackColor: const Color(0xFFFF6B3D),
                onChanged: (v) => settings.setAutoUpdateFirmware(v),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeSection() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final selectedColor = colorScheme.surfaceContainerHighest;
        final selectedTextColor = colorScheme.onSurface;
        final unselectedColor = colorScheme.surface;
        final unselectedTextColor = colorScheme.onSurfaceVariant;

        Widget option({
          required ThemeMode mode,
          required String label,
          required IconData icon,
        }) {
          final isSelected = settings.themeMode == mode;
          return Expanded(
            child: Semantics(
              button: true,
              selected: isSelected,
              label: '$label theme',
              child: InkWell(
                onTap: () => settings.setThemeMode(mode),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? selectedColor : unselectedColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? StsysTheme.cyanOf(context)
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: isSelected
                            ? selectedTextColor
                            : unselectedTextColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? selectedTextColor
                              : unselectedTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Row(
          children: [
            option(
              mode: ThemeMode.dark,
              label: 'Dark',
              icon: Icons.dark_mode_outlined,
            ),
            const SizedBox(width: 8),
            option(
              mode: ThemeMode.light,
              label: 'Light',
              icon: Icons.light_mode_outlined,
            ),
          ],
        );
      },
    );
  }

  Widget _buildTraceWindowSection() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: StsysTheme.surfaceContainerLowOf(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(
                'Duration: ${settings.maxSamples * 0.5}s - ${settings.maxSamples}s',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: StsysTheme.onSurfaceOf(context),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 150,
                child: Slider(
                  value: settings.maxSamples.toDouble(),
                  min: 2,
                  max: 10,
                  divisions: 8,
                  activeColor: StsysTheme.cyanOf(context),
                  inactiveColor: StsysTheme.surfaceContainerHighestOf(context),
                  onChanged: (v) {
                    settings.updateMaxSamples(v.round());
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTargetDistanceSection() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: StsysTheme.surfaceContainerLowOf(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(
                'Distance: ${settings.targetDistanceM.toStringAsFixed(1)} m',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: StsysTheme.onSurfaceOf(context),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 150,
                child: Slider(
                  value: settings.targetDistanceM,
                  min: 5.0,
                  max: 25.0,
                  divisions: 20,
                  activeColor: StsysTheme.cyanOf(context),
                  inactiveColor: StsysTheme.surfaceContainerHighestOf(context),
                  onChanged: (v) {
                    settings.updateTargetDistanceM(v);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFirearmTypeSection() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FirearmType.values.map((type) {
            final isSelected = settings.firearmType == type;
            return GestureDetector(
              onTap: () => settings.updateFirearmType(type),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected ? StsysTheme.brandGradient : null,
                  color: isSelected ? null : StsysTheme.surfaceContainerLowOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? null
                      : Border.all(
                          color: StsysTheme.outlineVariantOf(context).withValues(
                            alpha: 0.2,
                          ),
                        ),
                ),
                child: Text(
                  type.displayName.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: isSelected
                        ? StsysTheme.onPrimaryOf(context)
                        : StsysTheme.onSurfaceOf(context).withValues(alpha: 0.7),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTrainingModeSection() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TrainingMode.values.map((mode) {
            final isSelected = settings.trainingMode == mode;
            return GestureDetector(
              onTap: () => settings.updateTrainingMode(mode),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected ? StsysTheme.brandGradient : null,
                  color: isSelected ? null : StsysTheme.surfaceContainerLowOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? null
                      : Border.all(
                          color: StsysTheme.outlineVariantOf(context).withValues(
                            alpha: 0.2,
                          ),
                        ),
                ),
                child: Text(
                  mode.displayName.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: isSelected
                        ? StsysTheme.onPrimaryOf(context)
                        : StsysTheme.onSurfaceOf(context).withValues(alpha: 0.7),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDeviceScanOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: StsysTheme.surfaceContainerHighOf(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'AVAILABLE DEVICES',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: StsysTheme.cyanOf(context),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      _stopScan();
                      setState(() => _showDeviceList = false);
                    },
                    child: Icon(
                      Icons.close,
                      color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.5),
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: _isScanning
                        ? Column(
                            children: [
                              CircularProgressIndicator(
                                color: StsysTheme.cyanOf(context),
                                strokeWidth: 2,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'SEARCHING...',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  letterSpacing: 2,
                                  color: StsysTheme.onSurfaceOf(context).withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'No devices found',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: StsysTheme.onSurfaceOf(context).withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return GestureDetector(
                        onTap: () => _connectDevice(device),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: StsysTheme.surfaceContainerLowOf(context),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                device.isBonded ? Icons.watch : Icons.bluetooth,
                                color: StsysTheme.cyanOf(context),
                                size: 18,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device.name ?? 'Unknown',
                                      style: TextStyle(
                                        fontFamily: 'Manrope',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: StsysTheme.onSurfaceOf(context),
                                      ),
                                    ),
                                    Text(
                                      device.isBonded ? 'PAIRED' : 'AVAILABLE',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 9,
                                        letterSpacing: 1.5,
                                        color: device.isBonded
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.6)
                                            : StsysTheme.onSurfaceOf(context).withValues(
                                                alpha: 0.3,
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: StsysTheme.onSurfaceOf(context).withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// Battery Indicator
// ============================================
class _BatteryIndicator extends StatelessWidget {
  final int level;
  const _BatteryIndicator({required this.level});

  IconData get _icon {
    if (level >= 80) return Icons.battery_full;
    if (level >= 60) return Icons.battery_5_bar;
    if (level >= 40) return Icons.battery_4_bar;
    if (level >= 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color get _color {
    if (level >= 60) return const Color(0xFF4CAF50);
    if (level >= 20) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon, color: _color, size: 18),
        const SizedBox(width: 2),
        Text(
          '$level%',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _color,
          ),
        ),
      ],
    );
  }
}
