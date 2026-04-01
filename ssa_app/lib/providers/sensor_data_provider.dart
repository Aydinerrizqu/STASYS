// ============================================
// File: providers/sensor_data_provider.dart (OPTIMIZED V3)
// UI Thread hanya menerima display window, full data di isolate
// ============================================
import 'package:flutter/material.dart';
import 'dart:isolate';
import 'dart:async';
import '../models/data_models.dart';
import './session_logger.dart';
import './settings_provider.dart';
import './sensor_data_isolate.dart';

class SensorDataProvider extends ChangeNotifier {
  final SessionLogger _sessionLogger;
  SettingsProvider? _settingsProvider;
  
  // Isolate components
  Isolate? _dataIsolate;
  ReceivePort? _mainReceivePort;
  SendPort? _isolateSendPort;
  Completer<void>? _isolateReadyCompleter;

  // Queue messages sent before isolate SendPort was received
  final List<SensorDataMessage> _pendingMessages = [];
  
    // Konfigurasi
  final int _displayWindowSeconds = 5;

  // Display buffers (HANYA 5 detik terakhir - immutable snapshots dari isolate)
  List<DataPoint> _gyroXData = [];
  List<DataPoint> _gyroYData = [];
  List<DataPoint> _gyroZData = [];
  List<DataPoint> _accelXData = [];
  List<DataPoint> _accelYData = [];
  List<DataPoint> _accelZData = [];

  // Session data (akan diambil dari isolate saat save)
  List<DataPoint>? _sessionGyroX;
  List<DataPoint>? _sessionGyroY;
  List<DataPoint>? _sessionGyroZ;
  List<DataPoint>? _sessionAccelX;
  List<DataPoint>? _sessionAccelY;
  List<DataPoint>? _sessionAccelZ;
  List<ShotResult> _sessionShots = [];

  // Latest shot result (for UI display)
  ShotResult? _latestShot;
  ShotResult? get latestShot => _latestShot;

  // Status
  bool _isRecording = false;
  bool _isCalibrated = false;
  bool _isCalibrating = false;
  int _batteryLevel = 100;
  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  int _calibrationSamplesCount = 0;
  final int _samplesToCollect = 50;
  
  // Performance metrics
  int _totalDataPoints = 0;
  int _uiUpdatesReceived = 0;
  double _currentStabilityScore = 100.0;
  
  // Getters
  List<DataPoint> get gyroXData => _gyroXData;
  List<DataPoint> get gyroYData => _gyroYData;
  List<DataPoint> get gyroZData => _gyroZData;
  List<DataPoint> get accelXData => _accelXData;
  List<DataPoint> get accelYData => _accelYData;
  List<DataPoint> get accelZData => _accelZData;
  
  bool get isRecording => _isRecording;
  bool get isCalibrated => _isCalibrated;
  bool get isCalibrating => _isCalibrating;
  int get batteryLevel => _batteryLevel;
  Duration get recordingDuration => _recordingDuration;
  bool get canSaveSession => !_isRecording && _sessionGyroX != null && _sessionGyroX!.isNotEmpty;
  int get calibrationSamplesCount => _calibrationSamplesCount;
  int get samplesToCollect => _samplesToCollect;
  double get stabilityScore => _currentStabilityScore;
  
  // Performance getters
  int get totalDataPoints => _totalDataPoints;
  int get uiUpdatesReceived => _uiUpdatesReceived;

  SensorDataProvider({
    required SessionLogger logger,
    SettingsProvider? settings,
  }) : _sessionLogger = logger,
       _settingsProvider = settings {
    _initializeIsolate();
  }
  
  void updateDependencies({
    required SettingsProvider settings,
    required SessionLogger logger,
  }) {
    _settingsProvider = settings;
    // Send settings to isolate
    _isolateSendPort?.send(SensorDataMessage('update_settings', {
      'firearmType': settings.firearmType.name,
      'trainingMode': settings.trainingMode.name,
    }));
  }

  /// Initialize background isolate
  Future<void> _initializeIsolate() async {
    _mainReceivePort = ReceivePort();

    // CRITICAL: Attach listener BEFORE spawning isolate.
    // The isolate sends SendPort synchronously on startup.
    // If we spawn first and await, the isolate might send before listener is ready.
    _mainReceivePort!.listen(_handleIsolateMessage);
    debugPrint("[PROVIDER] Listener attached, spawning isolate...");

    final config = SensorIsolateConfig(
      mainSendPort: _mainReceivePort!.sendPort,
      displayWindowSeconds: 5, // 5 detik window
      uiUpdateIntervalMs: 50, // Update setiap 50ms = 20 FPS
    );

    _dataIsolate = await Isolate.spawn(
      SensorDataIsolate.entryPoint,
      config,
    );

    debugPrint("[PROVIDER] Isolate spawned, waiting for SendPort...");
  }
  
  /// Handle messages dari isolate
  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      debugPrint("[PROVIDER] ✅ Received SendPort from isolate! Isolate is READY.");
      _isolateSendPort = message;
      _isolateReadyCompleter?.complete();

      // Flush any queued messages
      if (_pendingMessages.isNotEmpty) {
        debugPrint("[PROVIDER] 🔄 Flushing ${_pendingMessages.length} pending message(s)...");
        for (final msg in _pendingMessages) {
          _isolateSendPort!.send(msg);
        }
        _pendingMessages.clear();
      }
      return;
    }
    
    if (message is SensorDataMessage) {
      switch (message.type) {
        case 'ui_update':
          // Isolate sends 'ui_update' — determine if full sync or diff based on data
          if (_gyroXData.isEmpty) {
            _handleFullSync(message.data!);
          } else {
            _handleDiffUpdate(message.data!);
          }
          break;
        case 'full_sync':
          _handleFullSync(message.data!);
          break;
        case 'diff_update':
          _handleDiffUpdate(message.data!);
          break;
        case 'calibration_started':
          debugPrint("[PROVIDER] Received calibration_started from isolate");
          _isCalibrating = true;
          notifyListeners();
          break;
        case 'calibration_progress':
          _calibrationSamplesCount = message.data!['count'];
          debugPrint("[PROVIDER] Calibration progress: $_calibrationSamplesCount/${message.data!['total']}");
          notifyListeners();
          break;
        case 'calibration_complete':
          debugPrint("[PROVIDER] Calibration COMPLETE!");
          _isCalibrating = false;
          _isCalibrated = true;
          notifyListeners();
          break;
        case 'session_data':
          _handleSessionData(message.data!);
          break;
        case 'shot_detected':
          _handleShotDetected(message.data!);
          break;
        case 'recording_started':
          _isRecording = true;
          _sessionShots.clear();
          notifyListeners();
          break;
        case 'recording_stopped':
          _isRecording = false;
          notifyListeners();
          break;
      }
    }
  }
  /// Handle sinkronisasi penuh dari isolate
  void _handleFullSync(Map<String, dynamic> data) {
    _gyroXData = List<DataPoint>.from(data['gyroX']);
    _gyroYData = List<DataPoint>.from(data['gyroY']);
    _gyroZData = List<DataPoint>.from(data['gyroZ']);
    _accelXData = List<DataPoint>.from(data['accelX']);
    _accelYData = List<DataPoint>.from(data['accelY']);
    _accelZData = List<DataPoint>.from(data['accelZ']);
    
    _updateCommonMetrics(data);
    notifyListeners();
  }
  // --- FUNGSI BARU: Menangani diff_update ---
  void _handleDiffUpdate(Map<String, dynamic> data) {
    final cutoffTimestamp = DateTime.now().subtract(const Duration(seconds: 5)).millisecondsSinceEpoch.toDouble();

    _gyroXData.addAll(List<DataPoint>.from(data['gyroX']));
    _gyroXData.removeWhere((p) => p.timestamp < cutoffTimestamp);
    
    _gyroYData.addAll(List<DataPoint>.from(data['gyroY']));
    _gyroYData.removeWhere((p) => p.timestamp < cutoffTimestamp);

    _gyroZData.addAll(List<DataPoint>.from(data['gyroZ']));
    _gyroZData.removeWhere((p) => p.timestamp < cutoffTimestamp);

    _accelXData.addAll(List<DataPoint>.from(data['accelX']));
    _accelXData.removeWhere((p) => p.timestamp < cutoffTimestamp);

    _accelYData.addAll(List<DataPoint>.from(data['accelY']));
    _accelYData.removeWhere((p) => p.timestamp < cutoffTimestamp);

    _accelZData.addAll(List<DataPoint>.from(data['accelZ']));
    _accelZData.removeWhere((p) => p.timestamp < cutoffTimestamp);

    _updateCommonMetrics(data);
    notifyListeners();
  }

  void _updateCommonMetrics(Map<String, dynamic> data) {
    if (data.containsKey('stability')) {
      _currentStabilityScore = data['stability'] as double;
    }
    if (data.containsKey('totalDataPoints')) {
      _totalDataPoints = data['totalDataPoints'] as int;
    }
    _uiUpdatesReceived++;
  }

  /// Update display buffers dari isolate (immutable assignment)
  // void _handleDisplayUpdate(Map<String, dynamic> data) {
  //   // KUNCI: Hanya assign reference baru ke display window (5 detik)
  //   // Ini sangat cepat karena hanya pointer assignment
  //   _gyroXData = List<DataPoint>.from(data['gyroX']);
  //   _gyroYData = List<DataPoint>.from(data['gyroY']);
  //   _gyroZData = List<DataPoint>.from(data['gyroZ']);
  //   _accelXData = List<DataPoint>.from(data['accelX']);
  //   _accelYData = List<DataPoint>.from(data['accelY']);
  //   _accelZData = List<DataPoint>.from(data['accelZ']);
    
  //   // Update metrics
  //   _currentStabilityScore = data['stability'] as double;
  //   _totalDataPoints = data['totalDataPoints'] as int;
  //   _uiUpdatesReceived++;
    
  //   // Debug log (hapus setelah debug)
  //   debugPrint("[PROVIDER] Display update - GyroX: ${_gyroXData.length} points");
    
  //   // Single notifyListeners call
  //   notifyListeners();
  // }

  /// Receive session data dari isolate
  void _handleSessionData(Map<String, dynamic> data) {
    _sessionGyroX = data['gyroX'] as List<DataPoint>;
    _sessionGyroY = data['gyroY'] as List<DataPoint>;
    _sessionGyroZ = data['gyroZ'] as List<DataPoint>;
    _sessionAccelX = data['accelX'] as List<DataPoint>;
    _sessionAccelY = data['accelY'] as List<DataPoint>;
    _sessionAccelZ = data['accelZ'] as List<DataPoint>;
    if (data.containsKey('shots')) {
      _sessionShots = (data['shots'] as List)
          .map((s) => ShotResult.fromMap(s as Map<String, dynamic>))
          .toList();
    }
  }

  /// Handle shot detection events from isolate
  void _handleShotDetected(Map<String, dynamic> data) {
    _latestShot = ShotResult.fromMap(data['shot'] as Map<String, dynamic>);
    _sessionShots.add(_latestShot!);
    notifyListeners();
  }

  /// Send settings changes to isolate
  void updateSettings() {
    if (_settingsProvider == null) return;
    _isolateSendPort?.send(SensorDataMessage('update_settings', {
      'firearmType': _settingsProvider!.firearmType.name,
      'trainingMode': _settingsProvider!.trainingMode.name,
    }));
  }

  void requestFullSync() {
    _isolateSendPort?.send(SensorDataMessage('request_full_sync'));
    debugPrint("[PROVIDER] Requesting full data sync...");
  }

  /// Send sensor data ke isolate (dipanggil dari BluetoothProvider)
  void updateAllData({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required int battery,
    int piezo = 0, // Peak piezo value from oversampling firmware
  }) {
    // Update battery di UI thread (simple state)
    // Hanya update jika perbedaan signifikan
    if ((_batteryLevel - battery).abs() >= 5) {
      _batteryLevel = battery;
    }

    // Forward ke isolate untuk processing
    if (_isolateSendPort != null) {
      _isolateSendPort!.send(SensorDataMessage('sensor_data', {
        'ax': ax,
        'ay': ay,
        'az': az,
        'gx': gx,
        'gy': gy,
        'gz': gz,
        'piezo': piezo,
        'battery': battery,
      }));
    }
  }

  void startCalibration() {
    debugPrint("[PROVIDER] startCalibration() called, _isolateSendPort: ${_isolateSendPort != null ? 'OK' : 'NULL'}");

    if (_isolateSendPort == null) {
      // Isolate not ready — queue message and it will be flushed when SendPort arrives
      debugPrint("[PROVIDER] ⚠️ Isolate not ready, queuing calibration message");
      _pendingMessages.add(SensorDataMessage('start_calibration'));
      return;
    }

    _isolateSendPort!.send(SensorDataMessage('start_calibration'));
  }
  
  void startRecording() {
    if (!_isCalibrated) return;

    _isRecording = true;
    _recordingStartTime = DateTime.now();
    _recordingDuration = Duration.zero;
    
    _isolateSendPort?.send(SensorDataMessage('start_recording'));
    
    // Timer untuk update durasi
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordingStartTime != null) {
        _recordingDuration = DateTime.now().difference(_recordingStartTime!);
      }
      notifyListeners();
    });
    
    notifyListeners();
  }
  
  void stopRecording() {
    _isRecording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    
    _isolateSendPort?.send(SensorDataMessage('stop_recording'));
    
    notifyListeners();
  }
  
  void toggleRecording() {
    if (_isRecording) {
      stopRecording();
    } else {
      startRecording();
    }
  }

  void resetTimeReference() {
    _isolateSendPort?.send(SensorDataMessage('reset'));
  }

  /// Save session - request data dari isolate dulu
  Future<void> saveCurrentSession() async {
    if (_sessionGyroX == null || _sessionGyroX!.isEmpty) {
      // Request session data dari isolate
      final completer = Completer<void>();

      // Setup one-time listener
      late StreamSubscription subscription;
      subscription = _mainReceivePort!.listen((message) {
        if (message is SensorDataMessage && message.type == 'session_data') {
          _handleSessionData(message.data!);
          subscription.cancel();
          completer.complete();
        }
      });

      _isolateSendPort?.send(SensorDataMessage('get_session_data'));

      // Timeout protection
      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          subscription.cancel();
          throw TimeoutException('Failed to get session data from isolate');
        },
      );
    }

    if (_sessionGyroX == null || _sessionGyroX!.isEmpty) {
      throw Exception('No session data available');
    }

    final sessionId = "SESSION_${DateTime.now().millisecondsSinceEpoch}";
    final firearmType = _settingsProvider?.firearmType ?? FirearmType.pistol;
    final trainingMode = _settingsProvider?.trainingMode ?? TrainingMode.dryFire;

    final log = SessionLog(
      id: sessionId,
      date: DateTime.now(),
      duration: _recordingDuration.inMilliseconds / 1000.0,
      gyroX: List.from(_sessionGyroX!),
      gyroY: List.from(_sessionGyroY!),
      gyroZ: List.from(_sessionGyroZ!),
      accelX: List.from(_sessionAccelX!),
      accelY: List.from(_sessionAccelY!),
      accelZ: List.from(_sessionAccelZ!),
      firearmType: firearmType,
      trainingMode: trainingMode,
      shots: List.from(_sessionShots),
    );

    await _sessionLogger.saveSession(log);

    // Clear session data
    _sessionGyroX = null;
    _sessionGyroY = null;
    _sessionGyroZ = null;
    _sessionAccelX = null;
    _sessionAccelY = null;
    _sessionAccelZ = null;
    _sessionShots.clear();
    _latestShot = null;

    _isolateSendPort?.send(SensorDataMessage('clear_session'));

    notifyListeners();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _isolateSendPort?.send(SensorDataMessage('reset'));
    _mainReceivePort?.close();
    _dataIsolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  
  @override
  String toString() => message;
}