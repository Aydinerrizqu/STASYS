import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import './sensor_data_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:async';

// ================= AUTH STATE (UPDATED) =================
enum AuthState {
  idle,              // Not in auth mode
  waitingForChallenge, // Waiting for EVT_AUTH_CHALLENGE (0x14)
  authenticated,      // Auth successful
  failed,             // Auth failed
}

// ================= PARSER STATE MACHINE =================
enum _ParserState {
  waitSync0,
  waitSync1,
  readType,
  readLenLo,
  readLenHi,
  readPayload,
  readCrcLo,
  readCrcHi,
}

// ================= PACKET TYPES (NEW PROTOCOL) =================
const int _PKT_SYNC0 = 0xAA;
const int _PKT_SYNC1 = 0x55;

const int _PKT_TYPE_CMD_START_SESSION    = 0x01;
const int _PKT_TYPE_CMD_STOP_SESSION     = 0x02;
const int _PKT_TYPE_CMD_AUTH             = 0x06;
const int _PKT_TYPE_CMD_GET_INFO         = 0x03;
const int _PKT_TYPE_CMD_GET_CONFIG       = 0x04;
const int _PKT_TYPE_CMD_SET_CONFIG       = 0x05;
const int _PKT_TYPE_EVT_SESSION_STARTED   = 0x10;
const int _PKT_TYPE_EVT_SESSION_STOPPED   = 0x11;
const int _PKT_TYPE_EVT_SHOT_DETECTED    = 0x12;
const int _PKT_TYPE_EVT_AUTH_CHALLENGE   = 0x14;
const int _PKT_TYPE_EVT_AUTH_SUCCESS     = 0x15;
const int _PKT_TYPE_EVT_ERROR            = 0x1F;
const int _PKT_TYPE_DATA_RAW_SAMPLE      = 0x20;
const int _PKT_TYPE_RSP_INFO             = 0x81;
const int _PKT_TYPE_RSP_CONFIG           = 0x82;
const int _PKT_TYPE_RSP_ACK             = 0x83;
const int _PKT_TYPE_RSP_SHOT_STATS      = 0x85;

// ================= SECRET KEY =================
const String _secretKey = "12ebaf10h12fa9123z21sti";

class BluetoothProvider extends ChangeNotifier {

  // ================= AUTH & SESSION STATE =================
  AuthState _authState = AuthState.idle;
  bool _sessionActive = false;
  int _sessionId = 0;
  int _shotCount = 0;

  // ================= PROTOCOL DECODER STATE =================
  _ParserState _parserState = _ParserState.waitSync0;
  final List<int> _recvBuffer = [];
  int _payloadLen = 0;
  int _crcComputed = 0xFFFF;
  int _crcReceived = 0;
  int _packetType = 0;

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

  // Statistics
  int _totalPacketsReceived = 0;
  int _invalidPacketsCount = 0;
  int _checksumErrorsCount = 0;
  int _consecutiveErrors = 0;
  static const int MAX_CONSECUTIVE_ERRORS = 10;

  // Getters
  BluetoothDevice? get selectedDevice => _selectedDevice;
  BluetoothConnection? get connection => _connection;
  List<BluetoothDevice> get devicesList => List.unmodifiable(_devicesList);
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  bool get isAuthenticated => _isAuthenticated;
  String get connectedDeviceName => _deviceName.isNotEmpty ? _deviceName : (_selectedDevice?.name ?? 'STASYS');
  int get totalPacketsReceived => _totalPacketsReceived;
  int get invalidPacketsCount => _invalidPacketsCount;
  int get checksumErrorsCount => _checksumErrorsCount;
  bool get sessionActive => _sessionActive;
  int get sessionId => _sessionId;
  int get shotCount => _shotCount;

  double get packetLossPercentage {
    if (_totalPacketsReceived == 0) return 0.0;
    return ((_invalidPacketsCount + _checksumErrorsCount) / _totalPacketsReceived) * 100;
  }

  // ================= DEBUG =================
  static int _debugCrcPrinted = 0;
  static int _debugRxPrinted = 0;

  // ================= CRC16-CCITT =================
  int _updateCrc(int crc, int byte) {
    crc ^= byte << 8;
    for (int i = 0; i < 8; i++) {
      if ((crc & 0x8000) != 0) {
        crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
      } else {
        crc = (crc << 1) & 0xFFFF;
      }
    }
    return crc;
  }

  int _crc16Ccitt(List<int> data) {
    int crc = 0xFFFF;
    for (int byte in data) {
      crc = _updateCrc(crc, byte);
    }
    return crc;
  }

  // ================= PROTOCOL DECODER =================
  void _feedParserByte(int b) {
    switch (_parserState) {
      case _ParserState.waitSync0:
        if (b == _PKT_SYNC0) {
          _parserState = _ParserState.waitSync1;
        }
        break;

      case _ParserState.waitSync1:
        if (b == _PKT_SYNC1) {
          _parserState = _ParserState.readType;
          _recvBuffer.clear();
          _crcComputed = 0xFFFF;
        } else if (b != _PKT_SYNC0) {
          _parserState = _ParserState.waitSync0;
        }
        break;

      case _ParserState.readType:
        _packetType = b;
        _crcComputed = _updateCrc(_crcComputed, b);
        _parserState = _ParserState.readLenLo;
        break;

      case _ParserState.readLenLo:
        _payloadLen = b;
        _crcComputed = _updateCrc(_crcComputed, b);
        _parserState = _ParserState.readLenHi;
        break;

      case _ParserState.readLenHi:
        _payloadLen |= (b << 8);
        _crcComputed = _updateCrc(_crcComputed, b);
        if (_payloadLen > 64) {
          debugPrint('WARNING: payload ${_payloadLen} > 64, truncating');
          _payloadLen = 64;
        }
        _recvBuffer.clear();
        if (_payloadLen == 0) {
          _parserState = _ParserState.readCrcLo;
        } else {
          _parserState = _ParserState.readPayload;
        }
        break;

      case _ParserState.readPayload:
        _recvBuffer.add(b);
        _crcComputed = _updateCrc(_crcComputed, b);
        if (_recvBuffer.length >= _payloadLen) {
          _parserState = _ParserState.readCrcLo;
        }
        break;

      case _ParserState.readCrcLo:
        _crcReceived = b;
        _parserState = _ParserState.readCrcHi;
        break;

      case _ParserState.readCrcHi:
        _crcReceived |= (b << 8);
        if (_crcComputed == _crcReceived) {
          _handlePacket(_packetType, List<int>.from(_recvBuffer));
        } else {
          if (_debugCrcPrinted < 1) {
            List<int> allBytes = [_packetType, _payloadLen & 0xFF, (_payloadLen >> 8) & 0xFF, ..._recvBuffer, _crcReceived & 0xFF, (_crcReceived >> 8) & 0xFF];
            debugPrint('[BT] CRC FAIL: type=0x${_packetType.toRadixString(16)}, len=$_payloadLen, bytes=${allBytes.map((e)=>e.toRadixString(16).padLeft(2,"0")).join(" ")}');
            debugPrint('[BT] CRC: expected=${_crcComputed.toRadixString(16)}, got=${_crcReceived.toRadixString(16)}');
            _debugCrcPrinted++;
          }
          _checksumErrorsCount++;
        }
        _parserState = _ParserState.waitSync0;
        break;
    }
  }

  // ================= PACKET HANDLER =================
  void _handlePacket(int type, List<int> payload) {
    switch (type) {
      case _PKT_TYPE_EVT_SESSION_STARTED:
        if (payload.length >= 4) {
          ByteData bd = ByteData.sublistView(Uint8List.fromList(payload));
          _sessionId = bd.getUint32(0, Endian.little);
          _sessionActive = true;
          _shotCount = 0;
          debugPrint('[BT] Session started: $_sessionId');
          notifyListeners();
        }
        break;

      case _PKT_TYPE_EVT_SESSION_STOPPED:
        _sessionActive = false;
        debugPrint('[BT] Session stopped');
        notifyListeners();
        break;

      case _PKT_TYPE_EVT_SHOT_DETECTED:
        _handleShotFromFirmware(payload);
        break;

      case _PKT_TYPE_DATA_RAW_SAMPLE:
        _handleRawSample(payload);
        break;

      case _PKT_TYPE_EVT_AUTH_CHALLENGE:
        _handleAuthChallenge(payload);
        break;

      case _PKT_TYPE_EVT_AUTH_SUCCESS:
        _authState = AuthState.authenticated;
        _isAuthenticated = true;
        notifyListeners();
        debugPrint('[BT] Auth successful');
        break;

      case _PKT_TYPE_EVT_ERROR:
        debugPrint('[BT] Firmware error: ${String.fromCharCodes(payload)}');
        break;

      case _PKT_TYPE_RSP_INFO:
        debugPrint('[BT] Got RSP_INFO packet');
        break;

      case _PKT_TYPE_RSP_ACK:
        debugPrint('[BT] Got RSP_ACK');
        break;

      case _PKT_TYPE_RSP_CONFIG:
        _handleRspConfig(payload);
        break;

      case 0x13:  // EVT_SENSOR_HEALTH — not used in UI yet
        break;

      default:
        debugPrint('[BT] Unknown packet type: 0x${type.toRadixString(16)}');
        break;
    }
  }

  // ================= AUTH CHALLENGE HANDLER =================
  void _handleAuthChallenge(List<int> payload) {
    if (payload.length < 20) return;

    // Extract session_id (4 bytes LE) + challenge (16 bytes)
    ByteData bd = ByteData.sublistView(Uint8List.fromList(payload));
    int sessionId = bd.getUint32(0, Endian.little);
    List<int> challenge = payload.sublist(4, 20);

    debugPrint('[BT] Auth challenge: session=$sessionId, challenge=${challenge.length} bytes');

    // Compute HMAC-SHA256(key, challenge + session_id_bytes)
    List<int> sessionBytes = [
      sessionId & 0xFF,
      (sessionId >> 8) & 0xFF,
      (sessionId >> 16) & 0xFF,
      (sessionId >> 24) & 0xFF,
    ];
    List<int> authInput = [...challenge, ...sessionBytes];

    var hmac = Hmac(sha256, utf8.encode(_secretKey));
    List<int> token = hmac.convert(authInput).bytes;

    // Build CMD_AUTH packet
    List<int> authPayload = [...sessionBytes, ...token];
    _sendPacket(_PKT_TYPE_CMD_AUTH, authPayload);

    _authState = AuthState.waitingForChallenge;
    debugPrint('[BT] Sent CMD_AUTH with HMAC-SHA256');
  }

  // ================= RAW SAMPLE HANDLER =================
  void _handleRawSample(List<int> payload) {
    if (payload.length < 24) {
      _invalidPacketsCount++;
      return;
    }

    ByteData bd = ByteData.sublistView(Uint8List.fromList(payload));

    // Convert raw int16 (from MPU6050) to float
    // ESP32 PktRawSample is 24 bytes (compiler-aligned):
    //   counter(4) + timestamp(4) + accel(6) + gyro(6) + piezo(2) + reserved(2)
    // Offsets in payload:
    //   0-3:   counter (uint32 LE)
    //   4-7:   timestamp_us (uint32 LE)
    //   8-9:   accel_x (int16 LE) → m/s²
    //   10-11: accel_y (int16 LE)
    //   12-13: accel_z (int16 LE)
    //   14-15: gyro_x (int16 LE) → rad/s
    //   16-17: gyro_y (int16 LE)
    //   18-19: gyro_z (int16 LE)
    //   20-21: piezo (uint16 LE)
    //   22-23: reserved
    double ax = bd.getInt16(8, Endian.little) / 8192.0 * 9.81;
    double ay = bd.getInt16(10, Endian.little) / 8192.0 * 9.81;
    double az = bd.getInt16(12, Endian.little) / 8192.0 * 9.81;
    double gx = bd.getInt16(14, Endian.little) / 65.5 * 0.0174533;
    double gy = bd.getInt16(16, Endian.little) / 65.5 * 0.0174533;
    double gz = bd.getInt16(18, Endian.little) / 65.5 * 0.0174533;
    int piezo = bd.getUint16(20, Endian.little);

    if (_isValidSensorData(ax, ay, az, gx, gy, gz)) {
      _sensorDataProvider.updateAllData(
        ax: ax, ay: ay, az: az,
        gx: gx, gy: gy, gz: gz,
        battery: _sensorDataProvider.batteryLevel,
        piezo: piezo,
      );
      _totalPacketsReceived++;
    } else {
      _invalidPacketsCount++;
    }
  }

  // ================= SHOT FROM FIRMWARE HANDLER =================
  void _handleShotFromFirmware(List<int> payload) {
    if (payload.length < 30) return;

    ByteData bd = ByteData.sublistView(Uint8List.fromList(payload));

    // session_id and timestamp_us available if needed for debugging
    // int sessionId = bd.getUint32(0, Endian.little);
    // int timestampUs = bd.getUint32(4, Endian.little);
    int shotNumber = bd.getUint16(8, Endian.little);
    int piezoPeak = bd.getUint16(10, Endian.little);
    int recoilAxis = bd.getInt8(24);
    int recoilSign = bd.getInt8(25);

    _shotCount++;
    debugPrint('[BT] Shot from firmware: #${shotNumber}, piezo=${piezoPeak}, axis=$recoilAxis, sign=$recoilSign');
    notifyListeners();
  }

  // ================= SEND PACKET =================
  void _sendPacket(int type, List<int> payload) {
    if (_connection == null || !_isConnected) return;

    List<int> frame = [
      _PKT_SYNC0,
      _PKT_SYNC1,
      type,
      payload.length & 0xFF,
      (payload.length >> 8) & 0xFF,
      ...payload,
    ];

    int crc = _crc16Ccitt(frame.sublist(2)); // CRC over type+len+payload
    frame.add(crc & 0xFF);
    frame.add((crc >> 8) & 0xFF);

    try {
      _connection!.output.add(Uint8List.fromList(frame));
      _connection!.output.allSent;
    } catch (e) {
      debugPrint('Error sending packet: $e');
    }
  }

  // ================= SESSION CONTROL =================
  void startSession() {
    // Allow CMD_START_SESSION to be sent even before authenticated (initial auth flow)
    // Subsequent calls during an active session can use the auth guard
    _sendPacket(_PKT_TYPE_CMD_START_SESSION, []);
    debugPrint('[BT] Sent CMD_START_SESSION');
  }

  void stopSession() {
    if (!_isAuthenticated) return;
    _sendPacket(_PKT_TYPE_CMD_STOP_SESSION, []);
    debugPrint('[BT] Sent CMD_STOP_SESSION');
  }

  // ================= CONFIG =================
  void getConfig() {
    _sendPacket(_PKT_TYPE_CMD_GET_CONFIG, []);
    debugPrint('[BT] Sent CMD_GET_CONFIG');
  }

  void _handleRspConfig(List<int> payload) {
    if (payload.length < 11) {
      debugPrint('[CFG] Response too short: ${payload.length} bytes');
      return;
    }
    int sampleRate = payload[0];
    int piezoThresh = payload[1] | (payload[2] << 8);
    int accelThresh = payload[3] | (payload[4] << 8);
    int debounceMs = payload[5] | (payload[6] << 8);
    bool ledEnabled = payload[7] != 0;
    int dataMode = payload[8];
    int streamRate = payload[9] | (payload[10] << 8);
    String deviceName = String.fromCharCodes(payload.sublist(11, 31)).replaceAll('\x00', '').trim();
    _deviceName = deviceName;

    debugPrint('[CFG] === FIRMWARE CONFIG ===');
    debugPrint('[CFG] sample_rate=$sampleRate Hz');
    debugPrint('[CFG] piezo_thresh=$piezoThresh, accel_thresh=$accelThresh');
    debugPrint('[CFG] debounce_ms=$debounceMs, led=$ledEnabled');
    debugPrint('[CFG] *** data_mode=$dataMode ***');
    debugPrint('[CFG] streaming_rate=$streamRate Hz');
    debugPrint('[CFG] device_name=$deviceName');
    debugPrint('[CFG] ========================');

    if (dataMode == 2) {
      debugPrint('[CFG] WARNING: data_mode=2 (events-only) — DATA_RAW packets will NOT be sent!');
      debugPrint('[CFG] ACTION: Call setDataMode(0) to enable raw data streaming');
    }
  }

  void setDataMode(int mode) {
    // Build CMD_SET_CONFIG payload (11+ bytes)
    List<int> cfgPayload = [
      100,        // sample_rate_hz (keep current)
      0, 0,       // piezo_threshold placeholder
      0, 0,       // accel_threshold placeholder
      0, 0,       // debounce_ms placeholder
      1,          // led_enabled
      mode,       // data_mode — THE KEY
      0, 0,       // streaming_rate placeholder
      ...utf8.encode('STASYS'),
      ...List.filled(20 - 'STASYS'.length, 0),
    ];
    _sendPacket(_PKT_TYPE_CMD_SET_CONFIG, cfgPayload);
    debugPrint('[BT] Sent CMD_SET_CONFIG with data_mode=$mode');
  }

  // ================= DATA RECEPTION =================
  void _onDataReceived(Uint8List data) {
    _consecutiveErrors = 0;

    // Debug: print raw received bytes (first 3 chunks only)
    if (_debugRxPrinted < 3) {
      debugPrint('[RX] raw len=${data.length}: ${data.map((e)=>e.toRadixString(16).padLeft(2,"0")).join(" ")}');
      _debugRxPrinted++;
    }

    // Feed all bytes to protocol decoder
    for (int b in data) {
      _feedParserByte(b);
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
      _authState = AuthState.idle;
      _sessionActive = false;
      _parserState = _ParserState.waitSync0;
      _recvBuffer.clear();
      _isAuthenticated = false;
      _totalPacketsReceived = 0;
      _invalidPacketsCount = 0;
      _checksumErrorsCount = 0;
      _consecutiveErrors = 0;
      notifyListeners();

      BluetoothConnection conn = await BluetoothConnection.toAddress(device.address);
      _connection = conn;
      _isConnected = true;
      notifyListeners();

      _dataSubscription = _connection!.input!.listen(
        _onDataReceived,
        onError: (error) {
          debugPrint('Stream error: $error');
          _handleConnectionError();
        },
        onDone: () {
          debugPrint('Connection closed by remote device');
          _handleDisconnection();
        },
        cancelOnError: false,
      );

      // Wait for auth challenge from firmware
      debugPrint('[BT] Waiting for auth challenge from ESP32...');
      bool authSuccess = await _waitForAuth();

      if (authSuccess) {
        _isAuthenticated = true;
        notifyListeners();
        debugPrint('Authentication successful');
        _sensorDataProvider.requestFullSync();
        return true;
      } else {
        debugPrint('Authentication failed');
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

  Future<bool> _waitForAuth() async {
    // New protocol: send CMD_START_SESSION to trigger firmware AUTH_CHALLENGE flow
    // Firmware sends PKT_TYPE_EVT_AUTH_CHALLENGE (0x14) after START_SESSION received
    await Future.delayed(const Duration(milliseconds: 500));
    // App sends CMD_START_SESSION to trigger firmware auth challenge
    startSession();  // This sends PKT_TYPE_CMD_START_SESSION → firmware sends AUTH_CHALLENGE → app computes HMAC → sends AUTH → firmware sends AUTH_SUCCESS
    // But _waitForAuth just waits for authenticated state — the actual challenge/response happens in _handlePacket callback
    await Future.delayed(const Duration(milliseconds: 300));
    // Fetch config after session start to check data_mode
    getConfig();
    await Future.delayed(const Duration(seconds: 4));
    return _authState == AuthState.authenticated;
  }

  void _handleConnectionError() {
    _consecutiveErrors++;
    if (_consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
      debugPrint('Too many consecutive errors, disconnecting...');
      disconnect();
    }
  }

  void _handleDisconnection() {
    _isConnected = false;
    _isAuthenticated = false;
    _sessionActive = false;
    _connection = null;
    _selectedDevice = null;
    _parserState = _ParserState.waitSync0;
    _recvBuffer.clear();
    _authState = AuthState.idle;
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
      _sessionActive = false;
      _connection = null;
      _selectedDevice = null;

      debugPrint('=== CONNECTION STATISTICS ===');
      debugPrint('Total packets: $_totalPacketsReceived');
      debugPrint('Invalid packets: $_invalidPacketsCount');
      debugPrint('Checksum errors: $_checksumErrorsCount');
      debugPrint('Packet loss: ${packetLossPercentage.toStringAsFixed(2)}%');

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
