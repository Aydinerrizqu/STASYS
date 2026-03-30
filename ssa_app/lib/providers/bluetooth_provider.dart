import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import './sensor_data_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
//import 'dart:isolate';

class BluetoothProvider extends ChangeNotifier {
  
  final List<int> _binaryBuffer = [];
  // Packet size: header(2) + 6 floats(24) + piezo uint16(2) + battery(1) + checksum(1) = 30 bytes
  static const int packetSize = 30;
  String _messageBuffer = '';
  static const int header1 = 0xAA;
  static const int header2 = 0xBB;

  static const String _secretKey = "12ebaf10h12fa9123z21sti";
  
  SensorDataProvider _sensorDataProvider;
  
  // Variable untuk Isolate
  // Isolate? _parserIsolate;
  // SendPort? _isolateSendPort;
  // ReceivePort? _mainReceivePort;

  // ADDED: Stream subscription untuk kontrol yang lebih baik
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
  Completer<String>? _authCompleter;
  
  // Statistics
  int _totalPacketsReceived = 0;
  int _invalidPacketsCount = 0;
  int _checksumErrorsCount = 0;
  
  // ADDED: Performance monitoring
  //DateTime? _lastPacketTime;
  int _consecutiveErrors = 0;
  // ignore: constant_identifier_names
  static const int MAX_CONSECUTIVE_ERRORS = 10;

  // Getters
  BluetoothDevice? get selectedDevice => _selectedDevice;
  BluetoothConnection? get connection => _connection;
  List<BluetoothDevice> get devicesList => List.unmodifiable(_devicesList);
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  bool get isAuthenticated => _isAuthenticated;
  int get totalPacketsReceived => _totalPacketsReceived;
  int get invalidPacketsCount => _invalidPacketsCount;
  int get checksumErrorsCount => _checksumErrorsCount;
  
  double get packetLossPercentage {
    if (_totalPacketsReceived == 0) return 0.0;
    return ((_invalidPacketsCount + _checksumErrorsCount) / _totalPacketsReceived) * 100;
  }

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
      debugPrint("Error getting bonded devices: $e");
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
      notifyListeners();
      
      BluetoothConnection conn = await BluetoothConnection.toAddress(device.address);
      _connection = conn;
      _isConnected = true;
      _isAuthenticated = false;
      
      // Reset statistics
      _totalPacketsReceived = 0;
      _invalidPacketsCount = 0;
      _checksumErrorsCount = 0;
      _consecutiveErrors = 0;
      //_lastPacketTime = null;
      
      notifyListeners();
      
      // FIXED: Gunakan StreamSubscription dengan error handling yang lebih baik
      _dataSubscription = _connection!.input!.listen(
        _onDataReceived,
        onError: (error) {
          debugPrint("❌ Stream error: $error");
          _handleConnectionError();
        },
        onDone: () {
          debugPrint("🔌 Connection closed by remote device");
          _handleDisconnection();
        },
        cancelOnError: false, // PENTING: Jangan cancel saat error
      );

      bool authSuccess = await _authenticateDevice();
      
      if (authSuccess) {
        _isAuthenticated = true;
        notifyListeners();
        debugPrint("✅ Authentication successful");
        // Memicu pengambilan data awal untuk grafik
        _sensorDataProvider.requestFullSync();  
        return true;
      } else {
        debugPrint("❌ Authentication failed");
        await disconnect();
        return false;
      }
    } catch (e) {
      debugPrint("❌ Connection error: $e");
      _isConnected = false;
      _isAuthenticated = false;
      notifyListeners();
      return false;
    }
  }

  // ADDED: Handle connection errors gracefully
  void _handleConnectionError() {
    _consecutiveErrors++;
    if (_consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
      debugPrint("⚠️ Too many consecutive errors, disconnecting...");
      disconnect();
    }
  }

  void _handleDisconnection() {
    _isConnected = false;
    _isAuthenticated = false;
    _connection = null;
    _selectedDevice = null;
    _sensorDataProvider.resetTimeReference();
    notifyListeners();
  }

  void _onDataReceived(Uint8List data) {
    // Reset consecutive errors on successful data receipt
    _consecutiveErrors = 0;
    
    // MODE 1: AUTH (Text-based)
    if (!_isAuthenticated) {
      try {
        String incoming = utf8.decode(data);
        _messageBuffer += incoming;

        if (_messageBuffer.contains('\n')) {
          List<String> lines = _messageBuffer.split('\n');
          _messageBuffer = lines.last; 
          
          for (int i = 0; i < lines.length - 1; i++) {
            String command = lines[i].trim();
            if (command.isNotEmpty) {
              debugPrint("[BT-AUTH] Received: $command");
              _authCompleter?.complete(command);
            }
          }
        }
      } catch (e) {
        debugPrint("Error parsing auth string: $e");
      }
      return;
    }

    // MODE 2: BINARY DATA
    _binaryBuffer.addAll(data);

    // OPTIMIZATION: Process multiple packets at once
    int packetsProcessed = 0;
    // ignore: constant_identifier_names
    const int MAX_PACKETS_PER_CYCLE = 5; // Limit untuk mencegah blocking

    while (_binaryBuffer.length >= packetSize && packetsProcessed < MAX_PACKETS_PER_CYCLE) {
      // Validate header
      if (_binaryBuffer[0] != header1 || _binaryBuffer[1] != header2) {
        // Try to find next valid header
        bool foundHeader = false;
        for (int i = 1; i < _binaryBuffer.length - 1; i++) {
          if (_binaryBuffer[i] == header1 && _binaryBuffer[i + 1] == header2) {
            debugPrint("⚠️ Resync: Removed $i invalid bytes");
            _binaryBuffer.removeRange(0, i);
            foundHeader = true;
            _invalidPacketsCount++;
            break;
          }
        }
        
        if (!foundHeader) {
          // No valid header found, clear buffer
          _binaryBuffer.clear();
          _invalidPacketsCount++;
          break;
        }
        continue;
      }

      // Extract packet
      List<int> packetBytes = _binaryBuffer.sublist(0, packetSize);
      
      // Validate checksum
      if (!_validateChecksum(packetBytes)) {
        debugPrint("⚠️ Checksum error");
        _binaryBuffer.removeRange(0, packetSize);
        _checksumErrorsCount++;
        continue;
      }
      
      ByteData byteData = ByteData.sublistView(Uint8List.fromList(packetBytes));

      try {
        double ax = byteData.getFloat32(2, Endian.little);
        double ay = byteData.getFloat32(6, Endian.little);
        double az = byteData.getFloat32(10, Endian.little);
        
        double gx = byteData.getFloat32(14, Endian.little);
        double gy = byteData.getFloat32(18, Endian.little);
        double gz = byteData.getFloat32(22, Endian.little);
        
        int piezo = byteData.getUint16(26, Endian.little);
        int battery = byteData.getUint8(28);

        // Validate sensor data
        if (_isValidSensorData(ax, ay, az, gx, gy, gz)) {
          _sensorDataProvider.updateAllData(
            ax: ax, ay: ay, az: az,
            gx: gx, gy: gy, gz: gz,
            battery: battery,
            piezo: piezo,
          );
          _totalPacketsReceived++;
        } else {
          debugPrint("⚠️ Invalid sensor data range");
          _invalidPacketsCount++;
        }
      } catch (e) {
        debugPrint("❌ Parse error: $e");
        _invalidPacketsCount++;
      }

      _binaryBuffer.removeRange(0, packetSize);
      packetsProcessed++;
    }
    
    // ADDED: Warning if buffer is growing (indicates processing bottleneck)
    if (_binaryBuffer.length > packetSize * 10) {
      debugPrint("⚠️ Buffer overflow: ${_binaryBuffer.length} bytes (${_binaryBuffer.length ~/ packetSize} packets)");
      // Emergency clear old data
      final keepSize = packetSize * 5;
      if (_binaryBuffer.length > keepSize) {
        _binaryBuffer.removeRange(0, _binaryBuffer.length - keepSize);
      }
    }
  }
  
  bool _validateChecksum(List<int> packet) {
    if (packet.length != packetSize) return false;
    
    int calculatedChecksum = 0;
    for (int i = 2; i < packetSize - 1; i++) {
      calculatedChecksum ^= packet[i];
    }
    
    int receivedChecksum = packet[packetSize - 1];
    return calculatedChecksum == receivedChecksum;
  }
  
  bool _isValidSensorData(double ax, double ay, double az, double gx, double gy, double gz) {
    const double maxAccel = 25.0;
    if (ax.abs() > maxAccel || ay.abs() > maxAccel || az.abs() > maxAccel) {
      return false;
    }
    
    const double maxGyro = 10.0; // 500dps * 0.01745 ≈ 8.73 rad/s, add margin
    if (gx.abs() > maxGyro || gy.abs() > maxGyro || gz.abs() > maxGyro) {
      return false;
    }
    
    if (ax.isNaN || ay.isNaN || az.isNaN || gx.isNaN || gy.isNaN || gz.isNaN) {
      return false;
    }
    if (ax.isInfinite || ay.isInfinite || az.isInfinite || 
        gx.isInfinite || gy.isInfinite || gz.isInfinite) {
      return false;
    }
    
    return true;
  }
  
  Future<bool> _authenticateDevice() async {
    if (_connection == null) return false;

    try {
      _authCompleter = Completer<String>();

      debugPrint("🔐 Waiting for ESP32...");
      await Future.delayed(const Duration(seconds: 2));

      String challenge = _generateRandomString(16);
      debugPrint("🔐 Sending challenge: '$challenge'");
      await sendDataToESP32("$challenge\n");

      String espResponse = await _authCompleter!.future.timeout(
        const Duration(seconds: 10), 
        onTimeout: () {
          throw TimeoutException("Authentication timeout");
        }
      );

      debugPrint("🔐 Response hash: '$espResponse'");

      String toHash = challenge + _secretKey;
      var bytes = utf8.encode(toHash);
      var digest = sha256.convert(bytes);
      String expectedResponse = digest.toString();

      debugPrint("🔐 Expected hash: '$expectedResponse'");

      bool isMatch = espResponse == expectedResponse;
      debugPrint("🔐 Match: ${isMatch ? 'YES ✓' : 'NO ✗'}");

      if (isMatch) {
        debugPrint("🔐 Sending AUTH_SUCCESS");
        await sendDataToESP32("AUTH_SUCCESS\n");

        _isAuthenticated = true;
        _binaryBuffer.clear();
        _messageBuffer = "";
        notifyListeners();
      }

      return isMatch;
    } catch (e) {
      debugPrint("🔐 Auth failed: $e");
      return false;
    } finally {
      _authCompleter = null;
    }
  }

  String _generateRandomString(int len) {
    var r = Random();
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    return List.generate(len, (index) => chars[r.nextInt(chars.length)]).join();
  }
  
  Future<void> sendDataToESP32(String data) async {
    if (_connection != null && _isConnected) {
      try {
        _connection!.output.add(Uint8List.fromList(data.codeUnits));
        await _connection!.output.allSent;
      } catch (e) {
        debugPrint("Error sending data: $e");
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
      _connection = null;
      _selectedDevice = null;
      
      debugPrint("=== CONNECTION STATISTICS ===");
      debugPrint("Total packets: $_totalPacketsReceived");
      debugPrint("Invalid packets: $_invalidPacketsCount");
      debugPrint("Checksum errors: $_checksumErrorsCount");
      debugPrint("Packet loss: ${packetLossPercentage.toStringAsFixed(2)}%");
      
      _sensorDataProvider.resetTimeReference();
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _dataSubscription?.cancel();
    _connection?.dispose();
    super.dispose();
  }
}