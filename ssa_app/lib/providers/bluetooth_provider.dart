import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import './sensor_data_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:async';

// ================= CONNECTION PHASE =================
// Upstream firmware uses text-based auth, then binary float packets.
enum _ConnectionPhase {
  waitingForReady,  // Waiting for "READY\n" from ESP32
  waitingForHash,   // Sent challenge, waiting for SHA256 hex response
  streaming,        // Auth succeeded, receiving 0xAA 0xBB binary packets
}

const String _secretKey = "12ebaf10h12fa9123z21sti";

class BluetoothProvider extends ChangeNotifier {

  SensorDataProvider _sensorDataProvider;
  StreamSubscription<Uint8List>? _dataSubscription;

  BluetoothProvider({required SensorDataProvider sensorDataProvider})
      : _sensorDataProvider = sensorDataProvider;

  set sensorDataProvider(SensorDataProvider provider) {
    _sensorDataProvider = provider;
  }

  BluetoothDevice? _selectedDevice;
  BluetoothConnection? _connection;
  List<BluetoothDevice> _devicesList = [];
  bool _isConnected = false;
  bool _isScanning = false;
  bool _isAuthenticated = false;
  String _deviceName = '';
  _ConnectionPhase _connectionPhase = _ConnectionPhase.waitingForReady;

  // Binary parser state
  static const int _SYNC0 = 0xAA;
  static const int _SYNC1 = 0xBB;
  // STASYS_FW packet structure (31 bytes):
  // [0-1] sync (0xAA, 0xBB)
  // [2-5] ax, [6-9] ay, [10-13] az (float, m/s²)
  // [14-17] gx, [18-21] gy, [22-25] gz (float, rad/s)
  // [26-27] piezo (uint16 ADC peak)
  // [28] battery (uint8 %)
  // [29-30] crc16 (CRC-16 CCITT over bytes 2-28)
  static const int _PACKET_SIZE = 31;
  final List<int> _binaryBuffer = [];

  // Statistics
  int _totalPacketsReceived = 0;
  int _checksumErrorsCount = 0;

  // Getters
  BluetoothDevice? get selectedDevice => _selectedDevice;
  BluetoothConnection? get connection => _connection;
  List<BluetoothDevice> get devicesList => List.unmodifiable(_devicesList);
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  bool get isAuthenticated => _isAuthenticated;
  String get connectedDeviceName => _deviceName.isNotEmpty ? _deviceName : (_selectedDevice?.name ?? 'STASYS');
  int get totalPacketsReceived => _totalPacketsReceived;
  int get invalidPacketsCount => 0;  // Not tracked in upstream protocol
  int get checksumErrorsCount => _checksumErrorsCount;
  bool get sessionActive => false;  // Upstream firmware has no session concept
  int get sessionId => 0;
  int get shotCount => 0;

  double get packetLossPercentage {
    if (_totalPacketsReceived == 0) return 0.0;
    return (_checksumErrorsCount / _totalPacketsReceived) * 100;
  }

  // ================= DEBUG =================
  static int _debugRxPrinted = 0;
  static int _debugBinaryPrinted = 0;

  // ================= DUAL-MODE DATA RECEPTION =================
  void _onDataReceived(Uint8List data) {
    if (_debugRxPrinted < 3) {
      debugPrint('[RX] raw len=${data.length}: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      _debugRxPrinted++;
    }

    switch (_connectionPhase) {
      case _ConnectionPhase.waitingForReady:
      case _ConnectionPhase.waitingForHash:
        _handleTextData(data);
        break;
      case _ConnectionPhase.streaming:
        _handleBinaryData(data);
        break;
    }
  }

  // ================= TEXT-BASED AUTH (upstream firmware) =================
  String _textBuffer = '';

  void _handleTextData(Uint8List data) {
    _textBuffer += String.fromCharCodes(data);

    while (_textBuffer.contains('\n')) {
      int nlIndex = _textBuffer.indexOf('\n');
      String line = _textBuffer.substring(0, nlIndex).trim();
      _textBuffer = _textBuffer.substring(nlIndex + 1);

      if (line.isEmpty) continue;

      if (_connectionPhase == _ConnectionPhase.waitingForReady) {
        if (line == 'READY') {
          debugPrint('[BT] Received READY, sending auth challenge...');
          _sendText('AUTH_CHALLENGE');
          _connectionPhase = _ConnectionPhase.waitingForHash;
        }
      } else if (_connectionPhase == _ConnectionPhase.waitingForHash) {
        if (line.length == 64) {
          debugPrint('[BT] Received hash response (${line.length} chars)');
          String toHash = 'AUTH_CHALLENGE' + _secretKey;
          String computedHash = sha256.convert(utf8.encode(toHash)).toString();
          if (line.toLowerCase() == computedHash.toLowerCase()) {
            debugPrint('[BT] Auth verified, switching to streaming mode');
            _isAuthenticated = true;
            _connectionPhase = _ConnectionPhase.streaming;
            _textBuffer = '';
            notifyListeners();
            _sensorDataProvider.requestFullSync();
          } else {
            debugPrint('[BT] Auth FAILED: expected=$computedHash, got=$line');
          }
        }
      }
    }
  }

  void _sendText(String text) {
    if (_connection == null || !_isConnected) return;
    try {
      _connection!.output.add(Uint8List.fromList('$text\n'.codeUnits));
      _connection!.output.allSent;
    } catch (e) {
      debugPrint('Error sending text: $e');
    }
  }

  // ================= BINARY PACKET PARSER (34-byte float packets) =================
  void _handleBinaryData(Uint8List data) {
    for (int b in data) {
      _binaryBuffer.add(b);

      if (_binaryBuffer.length == 1) {
        if (b != _SYNC0) {
          _binaryBuffer.clear();
          _binaryBuffer.add(b);
        }
      } else if (_binaryBuffer.length == 2) {
        if (b != _SYNC1) {
          _binaryBuffer.clear();
          if (b == _SYNC0) {
            _binaryBuffer.add(b);
          }
        }
      }
      if (_binaryBuffer.length == _PACKET_SIZE) {
        if (_binaryBuffer[0] == _SYNC0 && _binaryBuffer[1] == _SYNC1) {
          if (_verifyCrc16(_binaryBuffer)) {
            _parseBinaryPacket(_binaryBuffer);
            _totalPacketsReceived++;
          } else {
            _checksumErrorsCount++;
            if (_debugBinaryPrinted < 3) {
              // Compute CRC-16 for debugging
              int crc = 0xFFFF;
              for (int i = 2; i < 29; i++) {
                crc ^= _binaryBuffer[i] << 8;
                for (int j = 0; j < 8; j++) {
                  if ((crc & 0x8000) != 0) {
                    crc = (crc << 1) ^ 0x1021;
                  } else {
                    crc <<= 1;
                  }
                }
              }
              crc &= 0xFFFF;
              int receivedCrc = (_binaryBuffer[30] << 8) | _binaryBuffer[29];
              debugPrint('[BT] CRC16 fail: got=$receivedCrc.toRadixString(16), expected=$crc.toRadixString(16), bytes=${_binaryBuffer.sublist(2, 29).map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
              _debugBinaryPrinted++;
            }
          }
        }
        _binaryBuffer.clear();
      }
    }
  }

  bool _verifyCrc16(List<int> buf) {
    // CRC-16 CCITT over bytes 2-28 (27 bytes: floats + piezo + battery)
    // Initial: 0xFFFF, Polynomial: 0x1021
    int crc = 0xFFFF;
    for (int i = 2; i < 29; i++) {
      crc ^= buf[i] << 8;
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x8000) != 0) {
          crc = (crc << 1) ^ 0x1021;
        } else {
          crc <<= 1;
        }
      }
    }
    crc &= 0xFFFF;

    int receivedCrc = (buf[30] << 8) | buf[29];
    return crc == receivedCrc;
  }

  void _parseBinaryPacket(List<int> buf) {
    ByteData bd = ByteData.sublistView(Uint8List.fromList(buf));

    // [0-1] sync, [2-5] ax, [6-9] ay, [10-13] az, [14-17] gx, [18-21] gy, [22-25] gz, [26-27] piezo, [28] battery, [29-30] crc16
    double ax = bd.getFloat32(2, Endian.little);
    double ay = bd.getFloat32(6, Endian.little);
    double az = bd.getFloat32(10, Endian.little);
    double gx = bd.getFloat32(14, Endian.little);
    double gy = bd.getFloat32(18, Endian.little);
    double gz = bd.getFloat32(22, Endian.little);
    int piezo = bd.getUint16(26, Endian.little);
    int battery = buf[28];

    if (_isValidSensorData(ax, ay, az, gx, gy, gz)) {
      _sensorDataProvider.updateAllData(
        ax: ax, ay: ay, az: az,
        gx: gx, gy: gy, gz: gz,
        battery: battery,
        piezo: piezo,
      );
    }
  }

  bool _isValidSensorData(double ax, double ay, double az, double gx, double gy, double gz) {
    const double maxAccel = 25.0;
    if (ax.abs() > maxAccel || ay.abs() > maxAccel || az.abs() > maxAccel) return false;
    const double maxGyro = 10.0;
    if (gx.abs() > maxGyro || gy.abs() > maxGyro || gz.abs() > maxGyro) return false;
    if (ax.isNaN || ay.isNaN || az.isNaN || gx.isNaN || gy.isNaN || gz.isNaN) return false;
    if (ax.isInfinite || ay.isInfinite || az.isInfinite || gx.isInfinite || gy.isInfinite || gz.isInfinite) return false;
    return true;
  }

  // ================= BLUETOOTH LIFECYCLE =================
  Future<void> initializeBluetooth() async {
    bool permissionGranted = await _requestBluetoothPermissions();
    if (permissionGranted) {
      await getBondedDevices();
    }
  }

  Future<bool> _requestBluetoothPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  Future<void> getBondedDevices() async {
    try {
      List<BluetoothDevice> bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      _devicesList = bonded;
      notifyListeners();
    } catch (e) {
      debugPrint('Error getting bonded devices: $e');
    }
  }

  Future<void> startScan() async {
    bool permissionGranted = await _requestBluetoothPermissions();
    if (!permissionGranted) return;

    _isScanning = true;
    _devicesList.clear();
    notifyListeners();

    try {
      FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
        final existingIndex = _devicesList.indexWhere((d) => d.address == r.device.address);
        if (existingIndex >= 0) {
          _devicesList[existingIndex] = r.device;
        } else {
          _devicesList.add(r.device);
        }
        notifyListeners();
      }).onDone(() {
        _isScanning = false;
        notifyListeners();
      });
    } catch (e) {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    if (_isConnected) {
      await disconnect();
    }

    try {
      _selectedDevice = device;
      _connectionPhase = _ConnectionPhase.waitingForReady;
      _binaryBuffer.clear();
      _textBuffer = '';
      _isAuthenticated = false;
      _totalPacketsReceived = 0;
      _checksumErrorsCount = 0;
      _deviceName = device.name ?? 'STASYS';
      notifyListeners();

      BluetoothConnection conn = await BluetoothConnection.toAddress(device.address);
      _connection = conn;
      _isConnected = true;
      notifyListeners();

      _dataSubscription = _connection!.input!.listen(
        _onDataReceived,
        onError: (error) {
          debugPrint('Stream error: $error');
          disconnect();
        },
        onDone: () {
          debugPrint('Connection closed by remote device');
          _handleDisconnection();
        },
        cancelOnError: false,
      );

      // Wait up to 10s for auth to complete
      int waited = 0;
      while (!_isAuthenticated && waited < 10000) {
        await Future.delayed(const Duration(milliseconds: 200));
        waited += 200;
      }

      if (_isAuthenticated) {
        debugPrint('[BT] Connection and auth successful');
        return true;
      } else {
        debugPrint('[BT] Auth timeout');
        await disconnect();
        return false;
      }
    } catch (e) {
      debugPrint('Connection error: $e');
      _isConnected = false;
      _isAuthenticated = false;
      notifyListeners();
      return false;
    }
  }

  void _handleDisconnection() {
    _isConnected = false;
    _isAuthenticated = false;
    _connectionPhase = _ConnectionPhase.waitingForReady;
    _connection = null;
    _selectedDevice = null;
    _binaryBuffer.clear();
    _textBuffer = '';
    _sensorDataProvider.resetTimeReference();
    notifyListeners();
  }

  Future<void> sendDataToESP32(String data) async {
    if (_connection != null && _isConnected) {
      try {
        _connection!.output.add(Uint8List.fromList(data.codeUnits));
        await _connection!.output.allSent;
      } catch (e) {
        debugPrint('Error sending data: $e');
      }
    }
  }

  Future<void> disconnect() async {
    if (_dataSubscription != null) {
      await _dataSubscription!.cancel();
      _dataSubscription = null;
    }

    if (_connection != null) {
      await _connection!.close();
      _isConnected = false;
      _isAuthenticated = false;
      _connectionPhase = _ConnectionPhase.waitingForReady;
      _connection = null;
      _selectedDevice = null;

      debugPrint('=== CONNECTION STATISTICS ===');
      debugPrint('Total packets: $_totalPacketsReceived');
      debugPrint('Checksum errors: $_checksumErrorsCount');
      debugPrint('Packet loss: ${packetLossPercentage.toStringAsFixed(2)}%');

      _sensorDataProvider.resetTimeReference();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _dataSubscription = null;
    _connection?.dispose();
    _connection = null;
    super.dispose();
  }
}