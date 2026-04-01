import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import './sensor_data_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'dart:async';
import 'dart:convert';

// ================= AUTH STATE MACHINE =================
enum AuthState {
  idle,           // Not in auth mode
  waitingForHash, // READY received, waiting for hash response
  done,           // Auth successful
  failed,         // Auth failed
}

class BluetoothProvider extends ChangeNotifier {

  AuthState _authState = AuthState.idle;
  Completer<String>? _authCompleter;
  String? _lastChallenge;

  // ================= PACKET PARSING =================
  final List<int> _binaryBuffer = [];
  // Packet size: header(2) + 6 floats(24) + piezo uint16(2) + battery(1) + checksum(1) = 30 bytes
  static const int packetSize = 30;
  String _messageBuffer = '';
  static const int header1 = 0xAA;
  static const int header2 = 0xBB;

  static const String _secretKey = "12ebaf10h12fa9123z21sti";

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
      // Reset all state for fresh connection
      _selectedDevice = device;
      _authState = AuthState.idle;
      _authCompleter = null;
      _messageBuffer = '';
      _binaryBuffer.clear();
      _isAuthenticated = false;
      notifyListeners();

      BluetoothConnection conn = await BluetoothConnection.toAddress(device.address);
      _connection = conn;
      _isConnected = true;

      // Reset statistics
      _totalPacketsReceived = 0;
      _invalidPacketsCount = 0;
      _checksumErrorsCount = 0;
      _consecutiveErrors = 0;
      
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
    _binaryBuffer.clear();
    _messageBuffer = '';
    _authCompleter = null;
    _authState = AuthState.idle;
    _sensorDataProvider.resetTimeReference();
    notifyListeners();
  }

  void _onDataReceived(Uint8List data) {
    _consecutiveErrors = 0;

    // MODE 1: AUTH (Text-based, state machine)
    // ESP32 sends: "READY" → "2.0-OVERSAMPLE" → [challenge] → hash(64 hex chars)
    if (!_isAuthenticated && _authState != AuthState.done && _authState != AuthState.failed) {
      try {
        String incoming = utf8.decode(data, allowMalformed: true);
        _messageBuffer += incoming;

        while (_messageBuffer.contains('\n')) {
          int newlineIdx = _messageBuffer.indexOf('\n');
          String line = _messageBuffer.substring(0, newlineIdx).trim();
          _messageBuffer = _messageBuffer.substring(newlineIdx + 1);

          if (line.isEmpty) continue;
          debugPrint("[BT-AUTH] Received: $line");

          // State machine: only act on expected lines
          switch (_authState) {
            case AuthState.idle:
              // Waiting for "READY" from ESP32
              if (line == "READY") {
                debugPrint("[BT-AUTH] Got READY, waiting for version...");
                _authState = AuthState.waitingForHash;
              }
              break;

            case AuthState.waitingForHash:
              // After READY/version, ESP32 sends hash (64 hex chars)
              // OR it might send "READY" again if it restarted
              if (line == "READY") {
                debugPrint("[BT-AUTH] Got READY again, staying in hash wait...");
                // Still in waitingForHash state — ESP32 will send hash
              } else if (line.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(line)) {
                // This is the hash response — complete the future
                debugPrint("[BT-AUTH] Got hash response!");
                if (_authCompleter != null && !_authCompleter!.isCompleted) {
                  _authCompleter!.complete(line);
                }
                _authState = AuthState.done;
              } else {
                // Version string or unexpected — stay in hash wait
                debugPrint("[BT-AUTH] Version/info line, still waiting for hash...");
              }
              break;

            case AuthState.done:
            case AuthState.failed:
              break;
          }
        }
      } catch (e) {
        debugPrint("Error parsing auth string: $e");
      }
      return;
    }

    // MODE 2: BINARY DATA
    _binaryBuffer.addAll(data);

    // Process ALL available packets — no limit per cycle.
    // Bluetooth data rate is 100Hz, _onDataReceived fires frequently enough
    // that limiting to 5 packets causes buffer overflow at ~4+ calls/sec.

    while (_binaryBuffer.length >= packetSize) {
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
      // Reset auth state and wait for ESP32 to send "READY"
      _authState = AuthState.idle;
      _authCompleter = Completer<String>();
      _messageBuffer = '';
      _binaryBuffer.clear();

      debugPrint("🔐 Waiting for ESP32 to send READY...");

      // Wait for ESP32 "READY" (state machine will catch it in _onDataReceived)
      await Future.delayed(const Duration(seconds: 3));

      // Check if we received READY
      if (_authState != AuthState.waitingForHash) {
        debugPrint("🔐 Did not receive READY from ESP32 in time");
        _authState = AuthState.failed;
        return false;
      }

      // Send challenge
      String challenge = _generateRandomString(16);
      _lastChallenge = challenge;
      debugPrint("🔐 Sending challenge: '$challenge'");
      await sendDataToESP32("$challenge\n");

      // Wait for hash response
      String espResponse = await _authCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint("🔐 Auth timeout — no hash received");
          return 'TIMEOUT';
        },
      );

      if (espResponse == 'TIMEOUT') {
        _authState = AuthState.failed;
        return false;
      }

      debugPrint("🔐 Response hash: '$espResponse'");

      // Verify hash locally: SHA256(challenge + secretKey)
      String toHash = challenge + _secretKey;
      var bytes = utf8.encode(toHash);
      var digest = sha256.convert(bytes);
      String expectedHash = digest.toString();

      debugPrint("🔐 Expected hash: '$expectedHash'");

      bool isMatch = espResponse == expectedHash;
      debugPrint("🔐 Match: ${isMatch ? 'YES' : 'NO'}");

      if (isMatch) {
        debugPrint("🔐 Sending AUTH_SUCCESS");
        await sendDataToESP32("AUTH_SUCCESS\n");

        _isAuthenticated = true;
        _authState = AuthState.done;
        _binaryBuffer.clear();
        _messageBuffer = '';
        notifyListeners();
        debugPrint("✅ Authentication successful!");
      } else {
        _authState = AuthState.failed;
        debugPrint("❌ Hash mismatch — authentication failed");
      }

      return isMatch;
    } catch (e) {
      debugPrint("🔐 Auth failed: $e");
      _authState = AuthState.failed;
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