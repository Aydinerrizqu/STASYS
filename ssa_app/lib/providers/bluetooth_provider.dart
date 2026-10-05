import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/device_key_store.dart';
import '../services/stasys_protocol.dart';
import './sensor_data_provider.dart';

// ================= CONNECTION PHASE =================
enum _ConnectionPhase {
  waitingForGreeting,
  waitingForNonce,
  waitingForAuthResult,
  streaming,
  otaMode,
}

// Separate text buffer for OTA mode — unlimited, no trim, no collision
String _otaTextBuffer = '';

class BluetoothProvider extends ChangeNotifier {
  SensorDataProvider _sensorDataProvider;
  final DeviceKeyStore _deviceKeyStore;
  StreamSubscription<Uint8List>? _dataSubscription;

  BluetoothProvider({
    required SensorDataProvider sensorDataProvider,
    DeviceKeyStore? deviceKeyStore,
  })  : _sensorDataProvider = sensorDataProvider,
        _deviceKeyStore = deviceKeyStore ?? DeviceKeyStore();

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
  String? _authError;
  _ConnectionPhase _connectionPhase = _ConnectionPhase.waitingForGreeting;

  final FrameAssembler _frameAssembler = FrameAssembler();

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
  String? get authError => _authError;
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

  // ================= DUAL-MODE DATA RECEPTION =================
  void _onDataReceived(Uint8List data) {
    if (_debugRxPrinted < 3) {
      debugPrint('[RX] raw len=${data.length}');
      _debugRxPrinted++;
    }

    switch (_connectionPhase) {
      case _ConnectionPhase.waitingForGreeting:
      case _ConnectionPhase.waitingForNonce:
      case _ConnectionPhase.waitingForAuthResult:
        _handleTextData(data);
        break;
      case _ConnectionPhase.streaming:
        _handleBinaryData(data);
        break;
      case _ConnectionPhase.otaMode:
        _handleOtaData(data);
        break;
    }
  }

  // ================= TEXT-BASED AUTH (firmware v2) =================
  final LineBuffer _lineBuffer = LineBuffer();
  String _textBuffer = '';

  Future<void> _handleTextData(Uint8List data) async {
    try {
      for (final line in _lineBuffer.feed(data)) {
        switch (_connectionPhase) {
          case _ConnectionPhase.waitingForGreeting:
            final greeting = StasysProtocol.parseGreeting(line);
            _connectionPhase = _ConnectionPhase.waitingForNonce;
            _authGeneration = greeting.generation;
            break;
          case _ConnectionPhase.waitingForNonce:
            final nonce = StasysProtocol.parseNonce(line);
            final key = await _deviceKeyStore.readKey();
            if (_connection == null ||
                _connectionPhase != _ConnectionPhase.waitingForNonce) {
              return;
            }
            if (key == null) {
              await _failAuthentication('Device key not configured.');
              return;
            }
            final identity = _parseDeviceAddress(_selectedDevice!.address);
            final proof = StasysProtocol.authenticationProof(
              key: key,
              identity: identity,
              generation: _authGeneration!,
              nonce: nonce,
            );
            _sendText('PROOF $proof');
            _connectionPhase = _ConnectionPhase.waitingForAuthResult;
            break;
          case _ConnectionPhase.waitingForAuthResult:
            if (line == 'OK') {
              debugPrint('[BT] Authenticated; starting sensor stream');
              _authError = null;
              _isAuthenticated = true;
              _connectionPhase = _ConnectionPhase.streaming;
              _lineBuffer.clear();
              _textBuffer = '';
              notifyListeners();
              _sensorDataProvider.requestFullSync();
            } else {
              await _failAuthentication(
                line == 'FAIL' ? 'Device rejected authentication.' : 'Unexpected authentication response.',
              );
              return;
            }
            break;
          case _ConnectionPhase.streaming:
          case _ConnectionPhase.otaMode:
            return;
        }
      }
    } catch (error) {
      await _failAuthentication('Authentication failed: ${_readableError(error)}');
    }
  }

  int? _authGeneration;

  List<int> _parseDeviceAddress(String address) {
    final octets = address.split(':');
    if (octets.length != 6 ||
        octets.any((octet) => !RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(octet))) {
      throw const FormatException('Invalid Bluetooth device address');
    }
    return octets.map((octet) => int.parse(octet, radix: 16)).toList();
  }

  String _readableError(Object error) {
    if (error is FormatException) return error.message.toString();
    return 'Unable to read the device key or authenticate.';
  }

  Future<void> _failAuthentication(String message) async {
    _authError = message;
    _isAuthenticated = false;
    notifyListeners();
    try {
      await disconnect();
    } catch (e) {
      debugPrint('[BT] Disconnect after auth failure error: $e');
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

  // ================= OTA MODE: PURE TEXT PARSER =================
  // No binary parsing, no buffer trim, no collision with streaming mode.
  void _handleOtaData(Uint8List data) {
    // Accumulate raw bytes into dedicated OTA buffer (unbounded)
    for (int b in data) {
      _otaTextBuffer += String.fromCharCode(b);
    }
  }

  void resetFromOtaMode() {
    _connectionPhase = _ConnectionPhase.streaming;
    _otaTextBuffer = '';
  }

  void exitOtaMode() {
    _connectionPhase = _ConnectionPhase.streaming;
    _otaTextBuffer = '';
  }

  // ================= BINARY PACKET PARSER (firmware v2 frames) =================
  void _handleBinaryData(Uint8List data) {
    // Also accumulate printable ASCII for OTA text responses during streaming
    for (int b in data) {
      if (b >= 32 && b <= 126 || b == 10 || b == 13) {
        _textBuffer += String.fromCharCode(b);
      }
    }
    // Trim text buffer to last 2048 chars to prevent unbounded growth
    if (_textBuffer.length > 2048) {
      _textBuffer = _textBuffer.substring(_textBuffer.length - 2048);
    }

    final result = _frameAssembler.feed(data);
    _checksumErrorsCount += result.checksumErrors;
    for (final frame in result.frames) {
      if (_isValidSensorData(
        frame.ax, frame.ay, frame.az, frame.gx, frame.gy, frame.gz,
      )) {
        _sensorDataProvider.updateAllData(
          ax: frame.ax,
          ay: frame.ay,
          az: frame.az,
          gx: frame.gx,
          gy: frame.gy,
          gz: frame.gz,
          battery: frame.battery,
          piezo: frame.piezo,
        );
      }
      _totalPacketsReceived++;
    }
  }

  bool _isValidSensorData(double ax, double ay, double az, double gx, double gy, double gz) {
    const double maxAccel = 100.0; // 10g — real recoil can hit 30-50 m/s²
    if (ax.abs() > maxAccel || ay.abs() > maxAccel || az.abs() > maxAccel) return false;
    const double maxGyro = 50.0; // 50 rad/s — real shots can exceed 10 rad/s
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
      _devicesList = bonded.where((d) => (d.name ?? '').toLowerCase().contains('stasys')).toList();
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
        if (!(r.device.name ?? '').toLowerCase().contains('stasys')) return;
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
    // Force disconnect any existing connection first
    await _forceDisconnect();

    _selectedDevice = device;
    _connectionPhase = _ConnectionPhase.waitingForGreeting;
    _frameAssembler.clear();
    _lineBuffer.clear();
    _textBuffer = '';
    _authError = null;
    _authGeneration = null;
    _isAuthenticated = false;
    _totalPacketsReceived = 0;
    _checksumErrorsCount = 0;
    _deviceName = device.name ?? 'STASYS';
    notifyListeners();

    const maxRetries = 3;
    const delayBetweenRetries = Duration(seconds: 2);

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        debugPrint('[BT] Retry $attempt/${maxRetries} for ${device.address}');
        // Force disconnect before retry
        await _forceDisconnect();
        await Future.delayed(delayBetweenRetries);
      }

      try {
        debugPrint('[BT] Connecting to ${device.address} (attempt ${attempt + 1})');
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

        // Wait up to 15s for auth to complete
        int waited = 0;
        while (!_isAuthenticated && waited < 15000) {
          await Future.delayed(const Duration(milliseconds: 300));
          waited += 300;
        }

        if (_isAuthenticated) {
          debugPrint('[BT] Connection and auth successful');
          return true;
        } else {
          debugPrint('[BT] Auth timeout after ${waited}ms');
          _authError = 'Authentication timed out.';
          await disconnect();
          if (attempt < maxRetries) continue;
          return false;
        }
      } catch (e) {
        debugPrint('[BT] Connection attempt ${attempt + 1} failed: $e');
        _isConnected = false;
        if (attempt < maxRetries) {
          continue;
        }

        _isAuthenticated = false;
        notifyListeners();
        return false;
      }
    }

    return false;
  }

  /// Forcefully close any existing connection and clear state
  Future<void> _forceDisconnect() async {
    try {
      if (_dataSubscription != null) {
        await _dataSubscription!.cancel();
        _dataSubscription = null;
      }
      if (_connection != null) {
        await _connection!.close();
        _connection = null;
      }
      _isConnected = false;
      _isAuthenticated = false;
      _connectionPhase = _ConnectionPhase.waitingForGreeting;
      _textBuffer = '';
      _lineBuffer.clear();
      _frameAssembler.clear();
      debugPrint('[BT] Force disconnect completed');
    } catch (e) {
      debugPrint('[BT] Force disconnect error: $e');
    }
  }

  void _handleDisconnection() {
    if (!_isAuthenticated && _authError == null) {
      _authError = 'Connection closed before authentication completed.';
    }
    _isConnected = false;
    _isAuthenticated = false;
    _connectionPhase = _ConnectionPhase.waitingForGreeting;
    _connection = null;
    _selectedDevice = null;
    _lineBuffer.clear();
    _frameAssembler.clear();
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
      _connectionPhase = _ConnectionPhase.waitingForGreeting;
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

  // ================= OTA (Over-The-Air Firmware Update) =================

  /// Sends OTA_START:size=N and waits for OTA_READY response.
  Future<String> sendOtaStart(int totalSize) async {
    if (_connection == null || !_isConnected) return 'ERROR:not_connected';
    // CRITICAL: Clear buffer BEFORE switching phase to prevent RangeError
    _otaTextBuffer = '';
    _connectionPhase = _ConnectionPhase.otaMode;
    try {
      _connection!.output.add(Uint8List.fromList('OTA_START:size=$totalSize\n'.codeUnits));
      await _connection!.output.allSent;
      return await _waitForOtaResponse(timeoutMs: 5000);
    } catch (e) {
      resetFromOtaMode();
      return 'ERROR:$e';
    }
  }

  void _exitOtaMode() {
    _connectionPhase = _ConnectionPhase.streaming;
    _otaTextBuffer = '';
  }

    /// Sends one OTA chunk as base64-encoded data. Returns 'OTA_ACK:seq=N' on success.
  Future<String> sendOtaChunk(int seq, Uint8List chunkData) async {
    if (_connection == null || !_isConnected) return 'OTA_NAK:seq=$seq:err';
    try {
      // Send the chunk immediately (no flow control wait)
      final base64Data = base64.encode(chunkData);
      final cmd = 'OTA_DATA:seq=$seq:base64=$base64Data\n';
      _connection!.output.add(Uint8List.fromList(cmd.codeUnits));
      await _connection!.output.allSent;

      // Wait for ACK
      return await _waitForOtaResponse(timeoutMs: 5000);
    } catch (e) {
      print('[OTA] sendOtaChunk($seq) exception: $e');
      return 'OTA_NAK:seq=$seq:err';
    }
  }

  /// Sends OTA_FINISH with SHA256 hash and waits for OTA_COMPLETE.
  Future<String> sendOtaFinish(String sha256) async {
    if (_connection == null || !_isConnected) return 'ERROR:not_connected';
    try {
      _connection!.output.add(Uint8List.fromList('OTA_FINISH:sha256=$sha256\n'.codeUnits));
      await _connection!.output.allSent;
      final response = await _waitForOtaResponse(timeoutMs: 10000);
      // Exit OTA mode after finish (success or fail)
      _exitOtaMode();
      return response;
    } catch (e) {
      _exitOtaMode();
      return 'ERROR:$e';
    }
  }

  /// Sends REBOOT command.
  Future<void> sendRebootCommand() async {
    if (_connection == null || !_isConnected) return;
    try {
      _connection!.output.add(Uint8List.fromList('REBOOT\n'.codeUnits));
      await _connection!.output.allSent;
    } catch (_) {}
  }

  /// Queries firmware version from ESP32.
  Future<String?> getFirmwareVersion() async {
    if (_connection == null || !_isConnected) return null;
    try {
      _connection!.output.add(Uint8List.fromList('GET_VERSION\n'.codeUnits));
      await _connection!.output.allSent;
      final response = await _waitForOtaResponse(timeoutMs: 3000);
      if (response.startsWith('VERSION=')) {
        return response.substring(8).trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Internal: waits for an OTA text response from the accumulated _otaTextBuffer (in OTA mode) or _textBuffer (in streaming mode).
  /// Polls buffer for OTA response patterns.
  Future<String> _waitForOtaResponse({required int timeoutMs}) async {
    int waited = 0;
    while (waited < timeoutMs) {
      await Future.delayed(const Duration(milliseconds: 50));
      waited += 50;

      // Use dedicated OTA buffer if in OTA mode, otherwise use shared _textBuffer
      String buffer = _connectionPhase == _ConnectionPhase.otaMode ? _otaTextBuffer : _textBuffer;

      // Check buffer for OTA response patterns
      if (buffer.contains('VERSION=') ||
          buffer.contains('OTA_READY') ||
          buffer.contains('OTA_ACK:') ||
          buffer.contains('OTA_NAK:') ||
          buffer.contains('OTA_COMPLETE') ||
          buffer.contains('OTA_ERR:') ||
          buffer.contains('OTA_ABORTED') ||
          buffer.contains('OTA_TIMEOUT')) {
        // Find the last newline-delimited line that matches OTA patterns
        String searchFor = '';
        if (buffer.contains('VERSION=')) {
          searchFor = 'VERSION=';
        } else if (buffer.contains('OTA_COMPLETE')) {
          searchFor = 'OTA_COMPLETE';
        } else if (buffer.contains('OTA_READY')) {
          searchFor = 'OTA_READY';
        } else if (buffer.contains('OTA_ERR:')) {
          searchFor = 'OTA_ERR:';
        } else if (buffer.contains('OTA_ACK:')) {
          searchFor = 'OTA_ACK:';
        } else if (buffer.contains('OTA_NAK:')) {
          searchFor = 'OTA_NAK:';
        } else if (buffer.contains('OTA_ABORTED')) {
          searchFor = 'OTA_ABORTED';
        } else if (buffer.contains('OTA_TIMEOUT')) {
          searchFor = 'OTA_TIMEOUT';
        }

        int idx = buffer.lastIndexOf(searchFor);
        if (idx >= 0) {
          int endIdx = buffer.indexOf('\n', idx);
          if (endIdx < 0) {
            endIdx = buffer.length;
          }
          String line = buffer.substring(idx, endIdx).trim();
          // Clear up to this point to prevent accumulation
          if (_connectionPhase == _ConnectionPhase.otaMode) {
            _otaTextBuffer = buffer.substring(endIdx + 1);
          } else {
            _textBuffer = buffer.substring(endIdx + 1);
          }
          return line;
        }
      }
    }
    throw Exception('BT response timeout');
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