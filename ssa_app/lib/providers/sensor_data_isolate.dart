// ============================================
// File: providers/sensor_data_isolate.dart
// MantisX-Style Shot Detection & Scoring
// ============================================
import 'dart:isolate';
import 'package:ssa_app/Utils/ring_buffer.dart';
import '../models/data_models.dart';
import 'dart:math' as math;

/// Message untuk komunikasi dengan isolate
class SensorDataMessage {
  final String type;
  final Map<String, dynamic>? data;

  SensorDataMessage(this.type, [this.data]);
}

/// Config untuk inisialisasi isolate
class SensorIsolateConfig {
  final SendPort mainSendPort;
  final int displayWindowSeconds;
  final int uiUpdateIntervalMs;

  SensorIsolateConfig({
    required this.mainSendPort,
    this.displayWindowSeconds = 5,
    this.uiUpdateIntervalMs = 50,
  });
}

// ============================================
// SCORING CONFIGURATION (MantisX-Style)
// ============================================

class ScoringConfig {
  // Detection thresholds
  static const double stabilityWindowMs = 200.0;
  static const double stabilityGyroLimit = 4.0; // rad/s threshold

  // Phase durations (in samples @ 100Hz)
  static const int holdDurationIdx = 150;  // 1.5s hold
  static const int pressDurationIdx = 30; // 0.3s press
  static const int recoilDurationIdx = 10; // 0.1s recoil
  static const int totalHistoryNeeded = holdDurationIdx + recoilDurationIdx + 10;

  // Trigger thresholds
  static const double defaultPiezoMin = 100.0;
  static const double defaultAccelThresh = 8.0;
  static const double piezoMaxLimit = 2500.0;

  // MantisX-style scoring: SOFT CURVE (more forgiving than Hardcore)
  // Score drop-off is gradual, not punishing

  // Difficulty multipliers per firearm type
  static double getDifficultyMultiplier(FirearmType type) {
    switch (type) {
      case FirearmType.pistol:
        return 1.0;    // Baseline
      case FirearmType.rifle:
        return 0.7;    // More stable platform, stricter
      case FirearmType.archery:
        return 1.3;    // High precision needed
      case FirearmType.shotgun:
        return 0.9;    // Follow-through focus
    }
  }

  // Training mode adjustments
  static double getModeMultiplier(TrainingMode mode) {
    switch (mode) {
      case TrainingMode.dryFire:
        return 1.0;  // Baseline
      case TrainingMode.liveFire:
        return 0.8;  // More forgiving due to recoil
    }
  }

  // Soft curve scoring: uses sqrt for gentle drop-off
  // Total penalty is proportional to sqrt(travel), not linear
  // This means scores are achievable for intermediate shooters
  static double calculateScore({
    required double totalTravel,
    required double peakJerk,
    required FirearmType firearmType,
    required TrainingMode trainingMode,
    required double elevTravel,
    required double windTravel,
    required List<double> holdDeltas,
    required List<double> pressDeltas,
    required List<double> recoilDeltas,
  }) {
    final difficulty = getDifficultyMultiplier(firearmType);
    final modeMult = getModeMultiplier(trainingMode);
    final baseMultiplier = difficulty * modeMult;

    // Soft curve: sqrt-based penalties
    // Travel penalty: sqrt(total_travel) * multiplier
    // This means 0.01 degrees → small penalty, 0.1 degrees → noticeable but not devastating
    final travelPenalty = math.sqrt(totalTravel) * 30.0 * baseMultiplier;

    // Jerk penalty: sqrt(peak_jerk) * multiplier
    // Single large spike is punished but not catastrophic
    final jerkPenalty = math.sqrt(peakJerk) * 25.0 * baseMultiplier;

    // Per-phase penalties (softer)
    double holdPenalty = 0;
    double pressPenalty = 0;
    double recoilPenalty = 0;

    if (holdDeltas.isNotEmpty) {
      final avgHold = holdDeltas.reduce((a, b) => a + b) / holdDeltas.length;
      holdPenalty = math.sqrt(avgHold) * 10.0 * baseMultiplier;
    }

    if (pressDeltas.isNotEmpty) {
      final avgPress = pressDeltas.reduce((a, b) => a + b) / pressDeltas.length;
      pressPenalty = math.sqrt(avgPress) * 15.0 * baseMultiplier;
    }

    if (recoilDeltas.isNotEmpty) {
      final avgRecoil = recoilDeltas.reduce((a, b) => a + b) / recoilDeltas.length;
      recoilPenalty = math.sqrt(avgRecoil) * 5.0 * baseMultiplier;
    }

    // Per-axis penalties (softer)
    final elevPenalty = math.sqrt(elevTravel) * 15.0 * baseMultiplier;
    final windPenalty = math.sqrt(windTravel) * 15.0 * baseMultiplier;

    // Combined score
    final totalPenalty =
        travelPenalty + jerkPenalty +
        holdPenalty + pressPenalty + recoilPenalty +
        elevPenalty + windPenalty;

    final rawScore = 100.0 - totalPenalty;
    final score = math.max(0.0, math.min(100.0, rawScore));

    return score;
  }

  // Phase scores
  static double calculatePhaseScore(List<double> deltas, double multiplier) {
    if (deltas.isEmpty) return 100.0;
    final total = deltas.reduce((a, b) => a + b);
    final avg = total / deltas.length;
    final penalty = math.sqrt(avg) * 15.0 * multiplier;
    return math.max(0.0, math.min(100.0, 100.0 - penalty));
  }

  // Axis scores
  static double calculateAxisScore(double travel) {
    final penalty = math.sqrt(travel) * 15.0;
    return math.max(0.0, math.min(100.0, 100.0 - penalty));
  }
}

// ============================================
// SHOT DETECTOR STATE MACHINE
// ============================================

enum ShotState { idle, arming, armed, postGather, cooldown }

class ShotDetector {
  // Settings (from provider)
  FirearmType firearmType = FirearmType.pistol;
  TrainingMode trainingMode = TrainingMode.dryFire;
  double accelThresh = ScoringConfig.defaultAccelThresh;
  double piezoThresh = ScoringConfig.defaultPiezoMin;

  // State
  ShotState state = ShotState.idle;
  double stateTimer = 0;
  int gatherCounter = 0;
  int lastTriggerPiezo = 0;

  // History buffers for trace analysis
  final List<double> _traceX = []; // Integrated gyro X (windage)
  final List<double> _traceY = []; // Integrated gyro Y (elevation)
  final List<double> _rawGx = [];
  final List<double> _rawGy = [];
  final List<double> _rawGz = [];

  // Calibration
  double offsetGx = 0;
  double offsetGy = 0;
  double offsetGz = 0;

  static const double dt = 0.01; // 100Hz = 10ms

  void calibrate(List<double> gx, List<double> gy, List<double> gz) {
    if (gx.isEmpty) return;
    offsetGx = gx.reduce((a, b) => a + b) / gx.length;
    offsetGy = gy.reduce((a, b) => a + b) / gy.length;
    offsetGz = gz.reduce((a, b) => a + b) / gz.length;
  }

  ShotResult? process({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required int piezo,
  }) {
    // Apply calibration
    final fixedGx = gx - offsetGx;
    final fixedGy = gy - offsetGy;
    final fixedGz = gz - offsetGz;

    // Integrate for trace (rotation angle in radians)
    // X = integral(-gz * dt), Y = integral(-gx * dt)
    final newX = (_traceX.isEmpty ? 0.0 : _traceX.last) + (-fixedGz) * dt;
    final newY = (_traceY.isEmpty ? 0.0 : _traceY.last) + (-fixedGx) * dt;

    // Keep history
    _traceX.add(newX);
    _traceY.add(newY);
    _rawGx.add(fixedGx);
    _rawGy.add(fixedGy);
    _rawGz.add(fixedGz);

    // Trim to needed length
    final maxLen = ScoringConfig.totalHistoryNeeded * 2;
    if (_traceX.length > maxLen) {
      _traceX.removeRange(0, _traceX.length - maxLen);
      _traceY.removeRange(0, _traceY.length - maxLen);
      _rawGx.removeRange(0, _rawGx.length - maxLen);
      _rawGy.removeRange(0, _rawGy.length - maxLen);
      _rawGz.removeRange(0, _rawGz.length - maxLen);
    }

    // Calculate rotation magnitude
    final rotMag = math.sqrt(fixedGx * fixedGx + fixedGy * fixedGy + fixedGz * fixedGz);

    // Calculate jerk
    final jerk = _calculateJerk(ax, ay, az);

    ShotResult? result;

    switch (state) {
      case ShotState.cooldown:
        stateTimer -= dt;
        if (stateTimer <= 0) state = ShotState.idle;
        break;

      case ShotState.idle:
        if (rotMag < ScoringConfig.stabilityGyroLimit) {
          state = ShotState.arming;
          stateTimer = 0;
        }
        break;

      case ShotState.arming:
        if (rotMag > ScoringConfig.stabilityGyroLimit) {
          state = ShotState.idle;
        } else {
          stateTimer += dt * 1000; // ms
          if (stateTimer >= ScoringConfig.stabilityWindowMs) {
            state = ShotState.armed;
          }
        }
        break;

      case ShotState.armed:
        bool triggered = false;

        if (trainingMode == TrainingMode.liveFire) {
          // Live fire: trigger on jerk/accel spike
          if (jerk > (accelThresh * 1.5)) triggered = true;
        } else {
          // Dry fire: trigger on piezo
          if (piezo >= piezoThresh && piezo <= ScoringConfig.piezoMaxLimit) {
            if (rotMag < 6.0) triggered = true; // Still relatively stable
          }
        }

        if (triggered) {
          lastTriggerPiezo = piezo;
          state = ShotState.postGather;
          gatherCounter = ScoringConfig.recoilDurationIdx;
        }

        if (rotMag > (ScoringConfig.stabilityGyroLimit * 3.0)) {
          state = ShotState.idle;
        }
        break;

      case ShotState.postGather:
        gatherCounter -= 1;
        if (gatherCounter <= 0) {
          result = _analyzeShot();
          state = ShotState.cooldown;
          stateTimer = 0.5;
        }
        break;
    }

    return result;
  }

  double _prevAx = 0, _prevAy = 0, _prevAz = 0;

  double _calculateJerk(double ax, double ay, double az) {
    final jx = ax - _prevAx;
    final jy = ay - _prevAy;
    final jz = az - _prevAz;
    _prevAx = ax;
    _prevAy = ay;
    _prevAz = az;
    return math.sqrt(jx * jx + jy * jy + jz * jz) / dt;
  }

  ShotResult? _analyzeShot() {
    if (_traceX.length < ScoringConfig.totalHistoryNeeded) return null;

    final fullX = List<double>.from(_traceX);
    final fullY = List<double>.from(_traceY);

    final idxRecoilEnd = fullX.length;
    final idxBreak = idxRecoilEnd - ScoringConfig.recoilDurationIdx;
    final idxPressStart = idxBreak - ScoringConfig.pressDurationIdx;
    final idxHoldStart = idxBreak - ScoringConfig.holdDurationIdx;

    if (idxHoldStart < 0) return null;

    // Reference point at break
    final breakX = fullX[idxBreak];
    final breakY = fullY[idxBreak];

    // Normalized segments
    final holdX = fullX.sublist(idxHoldStart, idxPressStart).map((v) => v - breakX).toList();
    final holdY = fullY.sublist(idxHoldStart, idxPressStart).map((v) => v - breakY).toList();
    final pressX = fullX.sublist(idxPressStart, idxBreak + 1).map((v) => v - breakX).toList();
    final pressY = fullY.sublist(idxPressStart, idxBreak + 1).map((v) => v - breakY).toList();
    final recoilX = fullX.sublist(idxBreak, idxRecoilEnd).map((v) => v - breakX).toList();
    final recoilY = fullY.sublist(idxBreak, idxRecoilEnd).map((v) => v - breakY).toList();

    // Calculate total travel for press phase
    double totalTravel = 0;
    double peakJerk = 0;
    double elevTravel = 0;
    double windTravel = 0;

    final allDeltas = <double>[];
    for (int i = 1; i < pressX.length; i++) {
      final dx = pressX[i] - pressX[i - 1];
      final dy = pressY[i] - pressY[i - 1];
      final dist = math.sqrt(dx * dx + dy * dy);
      allDeltas.add(dist);
      totalTravel += dist;
      if (dist > peakJerk) peakJerk = dist;
    }

    // Elevation = integrated Y (up/down)
    for (int i = 1; i < pressY.length; i++) {
      final d = (pressY[i] - pressY[i - 1]).abs();
      elevTravel += d;
    }

    // Windage = integrated X (left/right)
    for (int i = 1; i < pressX.length; i++) {
      final d = (pressX[i] - pressX[i - 1]).abs();
      windTravel += d;
    }

    // Phase deltas
    final holdDeltas = _getDeltas(holdX, holdY);
    final recoilDeltas = _getDeltas(recoilX, recoilY);

    // Calculate all scores
    final multiplier = ScoringConfig.getDifficultyMultiplier(firearmType) *
        ScoringConfig.getModeMultiplier(trainingMode);

    final totalScore = ScoringConfig.calculateScore(
      totalTravel: totalTravel,
      peakJerk: peakJerk,
      firearmType: firearmType,
      trainingMode: trainingMode,
      elevTravel: elevTravel,
      windTravel: windTravel,
      holdDeltas: holdDeltas,
      pressDeltas: allDeltas,
      recoilDeltas: recoilDeltas,
    );

    final holdScore = ScoringConfig.calculatePhaseScore(holdDeltas, multiplier);
    final pressScore = ScoringConfig.calculatePhaseScore(allDeltas, multiplier);
    final recoilScore = ScoringConfig.calculatePhaseScore(recoilDeltas, multiplier);
    final elevScore = ScoringConfig.calculateAxisScore(elevTravel);
    final windScore = ScoringConfig.calculateAxisScore(windTravel);

    return ShotResult(
      timestamp: DateTime.now(),
      totalScore: totalScore,
      holdScore: holdScore,
      pressScore: pressScore,
      recoilScore: recoilScore,
      elevationScore: elevScore,
      windageScore: windScore,
      travelDistance: totalTravel,
      peakJerk: peakJerk,
      firearmType: firearmType,
      trainingMode: trainingMode,
    );
  }

  List<double> _getDeltas(List<double> x, List<double> y) {
    final deltas = <double>[];
    for (int i = 1; i < x.length; i++) {
      final dx = x[i] - x[i - 1];
      final dy = y[i] - y[i - 1];
      deltas.add(math.sqrt(dx * dx + dy * dy));
    }
    return deltas;
  }
}

// ============================================
// SENSOR DATA ISOLATE
// ============================================

class SensorDataIsolate {
  static const int _assumedDataRateHz = 100;

  // Ring buffers
  late RingBuffer<DataPoint> _fullGyroX;
  late RingBuffer<DataPoint> _fullGyroY;
  late RingBuffer<DataPoint> _fullGyroZ;
  late RingBuffer<DataPoint> _fullAccelX;
  late RingBuffer<DataPoint> _fullAccelY;
  late RingBuffer<DataPoint> _fullAccelZ;

  // Diff buffers
  final List<DataPoint> _newGyroX = [];
  final List<DataPoint> _newGyroY = [];
  final List<DataPoint> _newGyroZ = [];
  final List<DataPoint> _newAccelX = [];
  final List<DataPoint> _newAccelY = [];
  final List<DataPoint> _newAccelZ = [];

  // Session buffers
  final List<DataPoint> _sessionGyroX = [];
  final List<DataPoint> _sessionGyroY = [];
  final List<DataPoint> _sessionGyroZ = [];
  final List<DataPoint> _sessionAccelX = [];
  final List<DataPoint> _sessionAccelY = [];
  final List<DataPoint> _sessionAccelZ = [];

  // Shot detector
  final ShotDetector _shotDetector = ShotDetector();

  // Settings
  FirearmType _firearmType = FirearmType.pistol;
  TrainingMode _trainingMode = TrainingMode.dryFire;

  // State
  late SendPort _mainSendPort;
  late int _uiUpdateIntervalMs;
  late int _displayWindowSeconds;
  int _lastUiUpdateMs = 0;

  bool _isRecording = false;
  bool _isCalibrating = false;
  int _calibrationSamplesCount = 0;
  final int _samplesToCollect = 50;

  double _offsetGyroX = 0.0;
  double _offsetGyroY = 0.0;
  double _offsetGyroZ = 0.0;

  late DateTime _baseTime;

  // Shot storage for session
  final List<ShotResult> _sessionShots = [];

  // Performance tracking
  int _dataPointsReceived = 0;
  int _uiUpdatesSkipped = 0;

  // Calibrated flag
  bool _isCalibrated = false;

  static void entryPoint(SensorIsolateConfig config) {
    final isolate = SensorDataIsolate._internal(config);

    final receivePort = ReceivePort();
    config.mainSendPort.send(SensorDataMessage('send_port', {'port': receivePort.sendPort}));

    receivePort.listen((message) {
      if (message is SensorDataMessage) {
        isolate._handleMessage(message);
      }
    });
  }

  SensorDataIsolate._internal(SensorIsolateConfig config) {
    _mainSendPort = config.mainSendPort;
    _uiUpdateIntervalMs = config.uiUpdateIntervalMs;
    _displayWindowSeconds = config.displayWindowSeconds;
    _baseTime = DateTime.now();

    final bufferSize = _displayWindowSeconds * _assumedDataRateHz;
    _fullGyroX = RingBuffer<DataPoint>(bufferSize);
    _fullGyroY = RingBuffer<DataPoint>(bufferSize);
    _fullGyroZ = RingBuffer<DataPoint>(bufferSize);
    _fullAccelX = RingBuffer<DataPoint>(bufferSize);
    _fullAccelY = RingBuffer<DataPoint>(bufferSize);
    _fullAccelZ = RingBuffer<DataPoint>(bufferSize);
  }

  void _handleMessage(SensorDataMessage message) {
    try {
      switch (message.type) {
        case 'sensor_data':
          if (message.data != null) _processSensorData(message.data!);
          break;
        case 'start_calibration':
          _startCalibration();
          break;
        case 'start_recording':
          _startRecording();
          break;
        case 'stop_recording':
          _stopRecording();
          break;
        case 'reset':
          _reset();
          break;
        case 'get_session_data':
          _sendSessionData();
          break;
        case 'clear_session':
          _clearSessionData();
          break;
        case 'request_full_sync':
          _sendFullSync();
          break;
        case 'update_settings':
          _updateSettings(message.data!);
          break;
      }
    } catch (e) {
      // Silently catch errors to keep isolate alive
    }
  }

  void _updateSettings(Map<String, dynamic> data) {
    if (data.containsKey('firearmType')) {
      _firearmType = FirearmType.fromString(data['firearmType']);
      _shotDetector.firearmType = _firearmType;
    }
    if (data.containsKey('trainingMode')) {
      _trainingMode = TrainingMode.fromString(data['trainingMode']);
      _shotDetector.trainingMode = _trainingMode;
    }
  }

  void _processSensorData(Map<String, dynamic> data) {
    final ax = (data['ax'] as num).toDouble();
    final ay = (data['ay'] as num).toDouble();
    final az = (data['az'] as num).toDouble();
    final gx = (data['gx'] as num).toDouble();
    final gy = (data['gy'] as num).toDouble();
    final gz = (data['gz'] as num).toDouble();
    final piezo = (data['piezo'] as num?)?.toInt() ?? 0;

    // Calibration
    if (_isCalibrating) {
      _offsetGyroX += gx;
      _offsetGyroY += gy;
      _offsetGyroZ += gz;
      _calibrationSamplesCount++;

      if (_calibrationSamplesCount >= _samplesToCollect) {
        _offsetGyroX /= _samplesToCollect;
        _offsetGyroY /= _samplesToCollect;
        _offsetGyroZ /= _samplesToCollect;

        _shotDetector.offsetGx = _offsetGyroX;
        _shotDetector.offsetGy = _offsetGyroY;
        _shotDetector.offsetGz = _offsetGyroZ;
        _shotDetector.calibrate(
          _buildCalibrationList(_offsetGyroX),
          _buildCalibrationList(_offsetGyroY),
          _buildCalibrationList(_offsetGyroZ),
        );

        _isCalibrating = false;
        _isCalibrated = true;

        _mainSendPort.send(SensorDataMessage('calibration_complete', {
          'offsetGyroX': _offsetGyroX,
          'offsetGyroY': _offsetGyroY,
          'offsetGyroZ': _offsetGyroZ,
        }));
      }
      return;
    }

    // Apply offset
    final fixedGx = gx - _offsetGyroX;
    final fixedGy = gy - _offsetGyroY;
    final fixedGz = gz - _offsetGyroZ;

    final timestamp = DateTime.now().millisecondsSinceEpoch.toDouble();

    // DataPoints
    final dpAx = DataPoint.fromTimestamp(timestamp: timestamp, value: ax);
    final dpAy = DataPoint.fromTimestamp(timestamp: timestamp, value: ay);
    final dpAz = DataPoint.fromTimestamp(timestamp: timestamp, value: az);
    final dpGx = DataPoint.fromTimestamp(timestamp: timestamp, value: fixedGx);
    final dpGy = DataPoint.fromTimestamp(timestamp: timestamp, value: fixedGy);
    final dpGz = DataPoint.fromTimestamp(timestamp: timestamp, value: fixedGz);

    // Add to buffers
    _newAccelX.add(dpAx);
    _newAccelY.add(dpAy);
    _newAccelZ.add(dpAz);
    _newGyroX.add(dpGx);
    _newGyroY.add(dpGy);
    _newGyroZ.add(dpGz);

    _fullAccelX.add(dpAx);
    _fullAccelY.add(dpAy);
    _fullAccelZ.add(dpAz);
    _fullGyroX.add(dpGx);
    _fullGyroY.add(dpGy);
    _fullGyroZ.add(dpGz);

    if (_isRecording) {
      _sessionAccelX.add(dpAx);
      _sessionAccelY.add(dpAy);
      _sessionAccelZ.add(dpAz);
      _sessionGyroX.add(dpGx);
      _sessionGyroY.add(dpGy);
      _sessionGyroZ.add(dpGz);
    }

    // Shot detection
    final shotResult = _shotDetector.process(
      ax: ax, ay: ay, az: az,
      gx: fixedGx, gy: fixedGy, gz: fixedGz,
      piezo: piezo,
    );

    if (shotResult != null) {
      _sessionShots.add(shotResult);
      _mainSendPort.send(SensorDataMessage('shot_detected', {
        'shot': shotResult.toMap(),
      }));
    }

    _dataPointsReceived++;

    // Throttled UI update
    final currentMs = DateTime.now().millisecondsSinceEpoch;
    if (currentMs - _lastUiUpdateMs >= _uiUpdateIntervalMs) {
      _lastUiUpdateMs = currentMs;
      _sendThrottledUpdate();
    } else {
      _uiUpdatesSkipped++;
    }
  }

  List<double> _buildCalibrationList(double value) {
    return [value];
  }

  void _sendThrottledUpdate() {
    if (_newGyroX.isEmpty) return;

    _mainSendPort.send(SensorDataMessage('ui_update', {
      'gyroX': List<DataPoint>.from(_newGyroX),
      'gyroY': List<DataPoint>.from(_newGyroY),
      'gyroZ': List<DataPoint>.from(_newGyroZ),
      'accelX': List<DataPoint>.from(_newAccelX),
      'accelY': List<DataPoint>.from(_newAccelY),
      'accelZ': List<DataPoint>.from(_newAccelZ),
    }));

    _newGyroX.clear();
    _newGyroY.clear();
    _newGyroZ.clear();
    _newAccelX.clear();
    _newAccelY.clear();
    _newAccelZ.clear();
  }

  void _sendFullSync() {
    _mainSendPort.send(SensorDataMessage('ui_update', {
      'gyroX': _fullGyroX.toList(),
      'gyroY': _fullGyroY.toList(),
      'gyroZ': _fullGyroZ.toList(),
      'accelX': _fullAccelX.toList(),
      'accelY': _fullAccelY.toList(),
      'accelZ': _fullAccelZ.toList(),
    }));
  }

  void _startCalibration() {
    _isCalibrating = true;
    _calibrationSamplesCount = 0;
    _offsetGyroX = 0.0;
    _offsetGyroY = 0.0;
    _offsetGyroZ = 0.0;
    _mainSendPort.send(SensorDataMessage('calibration_started'));
  }

  void _startRecording() {
    _isRecording = true;
    _sessionShots.clear();
    _clearSessionData();
    _mainSendPort.send(SensorDataMessage('recording_started'));
  }

  void _stopRecording() {
    _isRecording = false;
    _mainSendPort.send(SensorDataMessage('recording_stopped'));
  }

  void _reset() {
    _baseTime = DateTime.now();

    final bufferSize = _displayWindowSeconds * _assumedDataRateHz;
    _fullGyroX = RingBuffer<DataPoint>(bufferSize);
    _fullGyroY = RingBuffer<DataPoint>(bufferSize);
    _fullGyroZ = RingBuffer<DataPoint>(bufferSize);
    _fullAccelX = RingBuffer<DataPoint>(bufferSize);
    _fullAccelY = RingBuffer<DataPoint>(bufferSize);
    _fullAccelZ = RingBuffer<DataPoint>(bufferSize);

    _newGyroX.clear();
    _newGyroY.clear();
    _newGyroZ.clear();
    _newAccelX.clear();
    _newAccelY.clear();
    _newAccelZ.clear();
    _clearSessionData();

    _dataPointsReceived = 0;
    _uiUpdatesSkipped = 0;

    _mainSendPort.send(SensorDataMessage('reset_complete'));
  }

  void _sendSessionData() {
    _mainSendPort.send(SensorDataMessage('session_data', {
      'gyroX': List<DataPoint>.from(_sessionGyroX),
      'gyroY': List<DataPoint>.from(_sessionGyroY),
      'gyroZ': List<DataPoint>.from(_sessionGyroZ),
      'accelX': List<DataPoint>.from(_sessionAccelX),
      'accelY': List<DataPoint>.from(_sessionAccelY),
      'accelZ': List<DataPoint>.from(_sessionAccelZ),
      'shots': _sessionShots.map((s) => s.toMap()).toList(),
    }));
  }

  void _clearSessionData() {
    _sessionGyroX.clear();
    _sessionGyroY.clear();
    _sessionGyroZ.clear();
    _sessionAccelX.clear();
    _sessionAccelY.clear();
    _sessionAccelZ.clear();
    _sessionShots.clear();
  }
}
