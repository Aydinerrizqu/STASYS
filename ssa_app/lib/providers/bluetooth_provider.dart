import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'dart:async';
import './sensor_data_provider.dart';

// =============================================================================
// STSYS32 — BLE Provider for Seeed XIAO nRF52840 Sense
// Migrated from BT Classic (flutter_bluetooth_serial) to BLE (flutter_blue_plus)
// Hardware: Seeed XIAO nRF52840 Sense + LSM6DS3 + PDM Mic + BLE
// =============================================================================

// BLE Service and Characteristic UUIDs (from Firmware_STSYS32_XIAO/include/config.h)
const String _serviceUuid = '19B10000-E8F2-537E-4F6C-D104768A1214';
const String _traceCharUuid = '19B10001-E8F2-537E-4F6C-D104768A1214'; // Device→App: raw 6-DoF @ 100Hz
const String _aimTraceCharUuid = '19B10005-E8F2-537E-4F6C-D104768A1214'; // Device→App: aim deviation @ 20Hz
const String _scoreCharUuid = '19B10002-E8F2-537E-4F6C-D104768A1214'; // Device→App: shot score
const String _stabilityCharUuid = '19B10006-E8F2-537E-4F6C-D104768A1214'; // Device→App: stability metrics
const String _drawCharUuid = '19B10003-E8F2-537E-4F6C-D104768A1214'; // Device→App: draw stroke metrics
const String _cmdCharUuid = '19B10004-E8F2-537E-4F6C-D104768A1214'; // App→Device: commands

// BLE Command Values (from Firmware_STSYS32_XIAO/src/IMU.cpp)
const int _cmdPistol = 0x01;
const int _cmdRifle = 0x02;
const int _cmdReset = 0x10;
const int _cmdSleep = 0x20;

// =============================================================================
// Shot Phase (from Firmware_STSYS32_XIAO/include/data.h)
// =============================================================================
enum ShotPhase { blue = 0, yellow = 1, red = 2 }

// =============================================================================
// BLE Packet Structs (packed, matching firmware data.h)
// =============================================================================

/// BleTraceSample — 20 bytes (from firmware data.h)
/// Raw 6-DoF IMU data streamed at up to 100Hz
class BleTraceSample {
  final double gx; // rad/s (stored as int16 * 10.0)
  final double gy;
  final double gz;
  final double ax; // m/s² (stored as int16 * 1000.0)
  final double ay;
  final double az;
  final ShotPhase phase;

  BleTraceSample._({
    required this.gx,
    required this.gy,
    required this.gz,
    required this.ax,
    required this.ay,
    required this.az,
    required this.phase,
  });

  factory BleTraceSample.fromBytes(Uint8List data) {
    final bd = ByteData.sublistView(data);
    return BleTraceSample._(
      gx: bd.getInt16(0, Endian.little) / 10.0,
      gy: bd.getInt16(2, Endian.little) / 10.0,
      gz: bd.getInt16(4, Endian.little) / 10.0,
      ax: bd.getInt16(6, Endian.little) / 1000.0,
      ay: bd.getInt16(8, Endian.little) / 1000.0,
      az: bd.getInt16(10, Endian.little) / 1000.0,
      phase: ShotPhase.values[data[12]],
    );
  }
}

/// BleAimTrace — 6 bytes (from firmware data.h)
/// Aim deviation streamed at 20Hz
class BleAimTrace {
  final double dPitch; // degrees (stored as int16 * 100)
  final double dRoll; // degrees (stored as int16 * 100)
  final ShotPhase phase;
  final int sampleIdx;

  BleAimTrace._({
    required this.dPitch,
    required this.dRoll,
    required this.phase,
    required this.sampleIdx,
  });

  factory BleAimTrace.fromBytes(Uint8List data) {
    final bd = ByteData.sublistView(data);
    return BleAimTrace._(
      dPitch: bd.getInt16(0, Endian.little) / 100.0,
      dRoll: bd.getInt16(2, Endian.little) / 100.0,
      phase: ShotPhase.values[data[4]],
      sampleIdx: data[5],
    );
  }
}

/// StabilityScore — 10 bytes (from firmware data.h)
class BleStabilityScore {
  final int score; // 0-100
  final double rmsDeviationDeg;
  final double maxDeviationDeg;
  final double stdDevPitchDeg;
  final double stdDevRollDeg;

  BleStabilityScore._({
    required this.score,
    required this.rmsDeviationDeg,
    required this.maxDeviationDeg,
    required this.stdDevPitchDeg,
    required this.stdDevRollDeg,
  });

  factory BleStabilityScore.fromBytes(Uint8List data) {
    final bd = ByteData.sublistView(data);
    return BleStabilityScore._(
      score: data[0],
      rmsDeviationDeg: bd.getInt16(1, Endian.little) / 100.0,
      maxDeviationDeg: bd.getInt16(3, Endian.little) / 100.0,
      stdDevPitchDeg: bd.getInt16(5, Endian.little) / 100.0,
      stdDevRollDeg: bd.getInt16(7, Endian.little) / 100.0,
    );
  }
}

/// DrawMetrics — 20 bytes (from firmware data.h)
class BleDrawMetrics {
  final int gripTimeMs;
  final int pullTimeMs;
  final int rotationTimeMs;
  final int acquisitionTimeMs;
  final int totalTimeMs;

  BleDrawMetrics._({
    required this.gripTimeMs,
    required this.pullTimeMs,
    required this.rotationTimeMs,
    required this.acquisitionTimeMs,
    required this.totalTimeMs,
  });

  factory BleDrawMetrics.fromBytes(Uint8List data) {
    final bd = ByteData.sublistView(data);
    return BleDrawMetrics._(
      gripTimeMs: bd.getUint32(0, Endian.little),
      pullTimeMs: bd.getUint32(4, Endian.little),
      rotationTimeMs: bd.getUint32(8, Endian.little),
      acquisitionTimeMs: bd.getUint32(12, Endian.little),
      totalTimeMs: bd.getUint32(16, Endian.little),
    );
  }
}

/// ShotScore — variable size (from firmware data.h)
/// Note: This is parsed from scoreChar which uses variable-length struct
class BleShotScore {
  final double deviationDeg;
  final int scorePercent; // 0-100
  final bool isLiveFire;
  // RecoilMetrics fields
  final double muzzleRiseDeg;
  final int recoveryTimeMs;
  final double recoilAngleDeg;
  final double recoilWidthDeg;

  BleShotScore._({
    required this.deviationDeg,
    required this.scorePercent,
    required this.isLiveFire,
    required this.muzzleRiseDeg,
    required this.recoveryTimeMs,
    required this.recoilAngleDeg,
    required this.recoilWidthDeg,
  });

  factory BleShotScore.fromBytes(Uint8List data) {
    final bd = ByteData.sublistView(data);
    // Layout: deviationDeg(float4) + scorePercent(uint8) + isLiveFire(bool1) +
    //         recoil.padding(3) + muzzleRiseDeg(float4) + recoveryTimeMs(uint32) +
    //         recoilAngleDeg(float4) + recoilWidthDeg(float4)
    // Total: 4 + 1 + 1(padded) + 4 + 4 + 4 + 4 = ~22 bytes minimum
    // Firmware sends sizeof(ShotScore) which includes RecoilMetrics struct
    double dev = 0;
    int score = 0;
    bool live = false;
    if (data.length >= 6) {
      dev = bd.getFloat32(0, Endian.little);
      score = data[4];
      live = data[5] != 0;
    }
    double rise = 0;
    int recov = 0;
    double angle = 0;
    double width = 0;
    if (data.length >= 22) {
      rise = bd.getFloat32(9, Endian.little);
      recov = bd.getUint32(13, Endian.little);
      angle = bd.getFloat32(17, Endian.little);
      width = bd.getFloat32(21, Endian.little);
    }
    return BleShotScore._(
      deviationDeg: dev,
      scorePercent: score,
      isLiveFire: live,
      muzzleRiseDeg: rise,
      recoveryTimeMs: recov,
      recoilAngleDeg: angle,
      recoilWidthDeg: width,
    );
  }
}

// =============================================================================
// BluetoothProvider — BLE GATT Provider
// =============================================================================
class BluetoothProvider extends ChangeNotifier {

  SensorDataProvider _sensorDataProvider;

  BluetoothProvider({required SensorDataProvider sensorDataProvider})
      : _sensorDataProvider = sensorDataProvider;

  set sensorDataProvider(SensorDataProvider provider) {
    _sensorDataProvider = provider;
  }

  // Device state
  BluetoothDevice? _connectedDevice;
  List<ScanResult> _devicesList = [];
  bool _isConnected = false;
  bool _isScanning = false;
  bool _isRifleMode = false;
  String _deviceName = 'STASYS-1';

  // GATT characteristics
  BluetoothCharacteristic? _traceChar;
  BluetoothCharacteristic? _aimTraceChar;
  BluetoothCharacteristic? _scoreChar;
  BluetoothCharacteristic? _stabilityChar;
  BluetoothCharacteristic? _drawChar;
  BluetoothCharacteristic? _cmdChar;

  // Statistics
  int _totalNotificationsReceived = 0;
  int _invalidNotificationsCount = 0;
  int _shotCount = 0;
  DateTime? _sessionStartTime;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  List<StreamSubscription<List<int>>> _charSubscriptions = [];

  // Getters
  BluetoothDevice? get connectedDevice => _connectedDevice;
  List<ScanResult> get devicesList => List.unmodifiable(_devicesList);
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  bool get isRifleMode => _isRifleMode;
  String get connectedDeviceName => _deviceName;
  int get totalNotificationsReceived => _totalNotificationsReceived;
  int get invalidNotificationsCount => _invalidNotificationsCount;
  int get shotCount => _shotCount;
  DateTime? get sessionStartTime => _sessionStartTime;

  double get packetLossPercentage {
    if (_totalNotificationsReceived == 0) return 0.0;
    return (_invalidNotificationsCount / _totalNotificationsReceived) * 100;
  }

  // =============================================================================
  // BLE INITIALIZATION
  // =============================================================================
  Future<bool> initializeBluetooth() async {
    bool permitted = await _requestBluetoothPermissions();
    if (!permitted) return false;

    // Turn Bluetooth on if off
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState.firstWhere((s) => s == BluetoothAdapterState.on);
    }
    return true;
  }

  Future<bool> _requestBluetoothPermissions() async {
    // Request BLE permissions on Android 12+
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  // =============================================================================
  // BLE SCANNING
  // =============================================================================
  Future<void> startScan() async {
    bool permitted = await initializeBluetooth();
    if (!permitted) return;

    _isScanning = true;
    _devicesList.clear();
    notifyListeners();

    // Start BLE scan for STSYS service UUID
    await FlutterBluePlus.startScan(
      withServices: [Guid(_serviceUuid)],
      timeout: const Duration(seconds: 12),
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        // Deduplicate by device address
        final existingIdx = _devicesList.indexWhere(
          (r) => r.device.remoteId.str == result.device.remoteId.str,
        );
        if (existingIdx >= 0) {
          _devicesList[existingIdx] = result;
        } else {
          _devicesList.add(result);
        }
      }
      notifyListeners();
    }, onError: (e) {
      debugPrint('[BLE-SCAN] Error: $e');
    });

    // Auto-stop after timeout
    Future.delayed(const Duration(seconds: 12), () {
      if (_isScanning) {
        stopScan();
      }
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
    notifyListeners();
  }

  // =============================================================================
  // BLE CONNECT
  // =============================================================================
  Future<bool> connectToDevice(BluetoothDevice device) async {
    if (_isConnected) {
      await disconnect();
    }

    try {
      _connectedDevice = device;
      _deviceName = device.platformName.isNotEmpty ? device.platformName : 'STASYS-1';
      _totalNotificationsReceived = 0;
      _invalidNotificationsCount = 0;
      _shotCount = 0;
      _sessionStartTime = DateTime.now();
      notifyListeners();

      // Connect with timeout
      await device.connect(timeout: const Duration(seconds: 15));

      // Discover services
      List<BluetoothService> services = await device.discoverServices();

      // Find STSYS service
      BluetoothService? stasysService;
      for (final svc in services) {
        if (svc.uuid.str.toUpperCase().contains(_serviceUuid.toUpperCase().replaceAll('-', ''))) {
          stasysService = svc;
          break;
        }
      }

      if (stasysService == null) {
        debugPrint('[BLE] STSYS service not found on device');
        await device.disconnect();
        _connectedDevice = null;
        notifyListeners();
        return false;
      }

      // Find all characteristics
      _traceChar = _findChar(stasysService, _traceCharUuid);
      _aimTraceChar = _findChar(stasysService, _aimTraceCharUuid);
      _scoreChar = _findChar(stasysService, _scoreCharUuid);
      _stabilityChar = _findChar(stasysService, _stabilityCharUuid);
      _drawChar = _findChar(stasysService, _drawCharUuid);
      _cmdChar = _findChar(stasysService, _cmdCharUuid);

      debugPrint('[BLE] Characteristics found:');
      debugPrint('  traceChar: ${_traceChar != null}');
      debugPrint('  aimTraceChar: ${_aimTraceChar != null}');
      debugPrint('  scoreChar: ${_scoreChar != null}');
      debugPrint('  stabilityChar: ${_stabilityChar != null}');
      debugPrint('  drawChar: ${_drawChar != null}');
      debugPrint('  cmdChar: ${_cmdChar != null}');

      // Subscribe to notifications
      await _subscribeToCharacteristics();

      // Listen for disconnection
      device.connectionState.listen((BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      _isConnected = true;
      notifyListeners();
      debugPrint('[BLE] Connected to $_deviceName');
      return true;

    } catch (e) {
      debugPrint('[BLE] Connection error: $e');
      _isConnected = false;
      _connectedDevice = null;
      notifyListeners();
      return false;
    }
  }

  BluetoothCharacteristic? _findChar(BluetoothService svc, String uuid) {
    for (final c in svc.characteristics) {
      if (c.uuid.str.toUpperCase().replaceAll('-', '').endsWith(
          uuid.toUpperCase().replaceAll('-', ''))) {
        return c;
      }
    }
    return null;
  }

  Future<void> _subscribeToCharacteristics() async {
    // Cancel any existing subscriptions
    for (final sub in _charSubscriptions) {
      await sub.cancel();
    }
    _charSubscriptions.clear();

    // Subscribe to traceChar (raw 6-DoF @ 100Hz)
    if (_traceChar != null) {
      await _traceChar!.setNotifyValue(true);
      _charSubscriptions.add(
        _traceChar!.lastValueStream.listen((data) => _onTraceData(data)),
      );
    }

    // Subscribe to aimTraceChar (dPitch/dRoll @ 20Hz)
    if (_aimTraceChar != null) {
      await _aimTraceChar!.setNotifyValue(true);
      _charSubscriptions.add(
        _aimTraceChar!.lastValueStream.listen((data) => _onAimTraceData(data)),
      );
    }

    // Subscribe to scoreChar (shot score)
    if (_scoreChar != null) {
      await _scoreChar!.setNotifyValue(true);
      _charSubscriptions.add(
        _scoreChar!.lastValueStream.listen((data) => _onScoreData(data)),
      );
    }

    // Subscribe to stabilityChar (stability metrics)
    if (_stabilityChar != null) {
      await _stabilityChar!.setNotifyValue(true);
      _charSubscriptions.add(
        _stabilityChar!.lastValueStream.listen((data) => _onStabilityData(data)),
      );
    }

    // Subscribe to drawChar (draw stroke metrics)
    if (_drawChar != null) {
      await _drawChar!.setNotifyValue(true);
      _charSubscriptions.add(
        _drawChar!.lastValueStream.listen((data) => _onDrawData(data)),
      );
    }
  }

  // =============================================================================
  // BLE DATA HANDLERS
  // =============================================================================
  void _onTraceData(Uint8List data) {
    _totalNotificationsReceived++;
    if (data.length < 20) {
      _invalidNotificationsCount++;
      return;
    }

    try {
      final sample = BleTraceSample.fromBytes(data);

      // Validate ranges (similar to old _isValidSensorData)
      if (sample.ax.abs() > 250.0 || sample.ay.abs() > 250.0 || sample.az.abs() > 250.0) {
        _invalidNotificationsCount++;
        return;
      }
      if (sample.gx.abs() > 100.0 || sample.gy.abs() > 100.0 || sample.gz.abs() > 100.0) {
        _invalidNotificationsCount++;
        return;
      }

      // Send to sensor data provider
      // Note: BLE firmware sends accel in m/s² (raw) and gyro in rad/s
      // SensorDataProvider expects: ax/ay/az in m/s², gx/gy/gz in rad/s
      _sensorDataProvider.updateAllData(
        ax: sample.ax,
        ay: sample.ay,
        az: sample.az,
        gx: sample.gx,
        gy: sample.gy,
        gz: sample.gz,
        battery: _sensorDataProvider.batteryLevel,
        piezo: 0, // No piezo in BLE version — PDM mic handles shot detection
      );

    } catch (e) {
      debugPrint('[BLE-TRACE] Parse error: $e');
      _invalidNotificationsCount++;
    }
  }

  void _onAimTraceData(Uint8List data) {
    if (data.length < 6) return;
    try {
      final aim = BleAimTrace.fromBytes(data);
      // Aim deviation data is available for the live trace widget
      // The trace widget uses gx/gy/gz from traceChar; aim deviation
      // can be used for enhanced display
      debugPrint('[BLE-AIM] dPitch=${aim.dPitch.toStringAsFixed(2)} deg, dRoll=${aim.dRoll.toStringAsFixed(2)} deg');
    } catch (e) {
      debugPrint('[BLE-AIM] Parse error: $e');
    }
  }

  void _onScoreData(Uint8List data) {
    if (data.isEmpty) return;
    try {
      final score = BleShotScore.fromBytes(data);
      _shotCount++;
      debugPrint('[BLE-SCORE] Shot #$_shotCount: ${score.scorePercent}% | '
          '${score.deviationDeg.toStringAsFixed(3)} deg | '
          'live=${score.isLiveFire} | rise=${score.muzzleRiseDeg.toStringAsFixed(1)} deg');
      notifyListeners();
    } catch (e) {
      debugPrint('[BLE-SCORE] Parse error: $e');
    }
  }

  void _onStabilityData(Uint8List data) {
    if (data.length < 10) return;
    try {
      final stability = BleStabilityScore.fromBytes(data);
      debugPrint('[BLE-STABILITY] Score: ${stability.score} | '
          'RMS: ${stability.rmsDeviationDeg.toStringAsFixed(3)} deg');
    } catch (e) {
      debugPrint('[BLE-STABILITY] Parse error: $e');
    }
  }

  void _onDrawData(Uint8List data) {
    if (data.length < 20) return;
    try {
      final draw = BleDrawMetrics.fromBytes(data);
      debugPrint('[BLE-DRAW] Total: ${draw.totalTimeMs}ms | '
          'grip=${draw.gripTimeMs} pull=${draw.pullTimeMs} '
          'rot=${draw.rotationTimeMs} acq=${draw.acquisitionTimeMs}');
      notifyListeners();
    } catch (e) {
      debugPrint('[BLE-DRAW] Parse error: $e');
    }
  }

  // =============================================================================
  // BLE COMMANDS
  // =============================================================================
  Future<void> sendCommand(int cmd) async {
    if (_cmdChar == null || !_isConnected) return;
    try {
      await _cmdChar!.write(Uint8List.fromList([cmd]), withoutResponse: true);
      debugPrint('[BLE-CMD] Sent command: 0x${cmd.toRadixString(16)}');
    } catch (e) {
      debugPrint('[BLE-CMD] Write error: $e');
    }
  }

  void setModePistol() {
    _isRifleMode = false;
    sendCommand(_cmdPistol);
    notifyListeners();
  }

  void setModeRifle() {
    _isRifleMode = true;
    sendCommand(_cmdRifle);
    notifyListeners();
  }

  void resetSession() {
    _shotCount = 0;
    _sessionStartTime = DateTime.now();
    sendCommand(_cmdReset);
    notifyListeners();
  }

  void enterDeepSleep() {
    sendCommand(_cmdSleep);
  }

  // =============================================================================
  // DISCONNECTION
  // =============================================================================
  Future<void> disconnect() async {
    // Cancel all characteristic subscriptions
    for (final sub in _charSubscriptions) {
      await sub.cancel();
    }
    _charSubscriptions.clear();

    // Disconnect
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        debugPrint('[BLE] Disconnect error: $e');
      }
    }

    _handleDisconnection();
  }

  void _handleDisconnection() {
    _isConnected = false;
    _connectedDevice = null;
    _traceChar = null;
    _aimTraceChar = null;
    _scoreChar = null;
    _stabilityChar = null;
    _drawChar = null;
    _cmdChar = null;
    _sensorDataProvider.resetTimeReference();
    notifyListeners();
  }

  // =============================================================================
  // SESSION CONTROL
  // =============================================================================
  // Note: BLE firmware starts streaming automatically on connection
  // No explicit START_SESSION command needed
  void startSession() {
    resetSession();
    debugPrint('[BLE] Session started');
    notifyListeners();
  }

  void stopSession() {
    debugPrint('[BLE] Session stopped. Shots: $_shotCount');
    debugPrint('=== CONNECTION STATISTICS ===');
    debugPrint('Total notifications: $_totalNotificationsReceived');
    debugPrint('Invalid notifications: $_invalidNotificationsCount');
    debugPrint('Packet loss: ${packetLossPercentage.toStringAsFixed(2)}%');
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _charSubscriptions) {
      sub.cancel();
    }
    _scanSubscription?.cancel();
    super.dispose();
  }
}
