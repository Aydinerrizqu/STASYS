// ============================================
// File: providers/session_logger.dart
// ============================================
import 'dart:developer' as developer;
import '../models/data_models.dart';
import '../services/database_service.dart';

// Model untuk satu sesi latihan yang disimpan
class SessionLog {
  final String id;
  final DateTime date;
  final double duration; // dalam detik
  final List<DataPoint> gyroX;
  final List<DataPoint> gyroY;
  final List<DataPoint> gyroZ;
  final List<DataPoint> accelX;
  final List<DataPoint> accelY;
  final List<DataPoint> accelZ;
  final FirearmType firearmType;
  final TrainingMode trainingMode;
  final List<ShotResult> shots;
  final String profileName;
  final String trainingPreset;
  final int seriesCount;

  SessionLog({
    required this.id,
    required this.date,
    required this.duration,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    this.firearmType = FirearmType.pistol,
    this.trainingMode = TrainingMode.dryFire,
    List<ShotResult>? shots,
    this.profileName = '',
    this.trainingPreset = '',
    this.seriesCount = 0,
  }) : shots = shots ?? [];

  bool get hasRawData =>
      gyroX.isNotEmpty &&
      gyroY.isNotEmpty &&
      gyroZ.isNotEmpty &&
      accelX.isNotEmpty &&
      accelY.isNotEmpty &&
      accelZ.isNotEmpty;

  double get averageScore {
    if (shots.isEmpty) return 0;
    return shots.map((s) => s.totalScore).reduce((a, b) => a + b) /
        shots.length;
  }

  double get averageStability {
    if (shots.isEmpty) return 0;
    return shots.map((s) => s.holdScore).reduce((a, b) => a + b) / shots.length;
  }

  double get bestScore {
    if (shots.isEmpty) return 0;
    return shots.map((s) => s.totalScore).reduce((a, b) => a > b ? a : b);
  }

  double get worstScore {
    if (shots.isEmpty) return 0;
    return shots.map((s) => s.totalScore).reduce((a, b) => a < b ? a : b);
  }

  factory SessionLog.fromMap(Map<String, dynamic> map) {
    return SessionLog(
      id: map['id'],
      date: DateTime.parse(map['date']),
      duration: (map['duration'] as num).toDouble(),
      gyroX: (map['gyroX'] as List? ?? [])
          .where((p) => p != null)
          .map((p) => DataPoint.fromMap(p as Map<String, dynamic>))
          .toList(),
      gyroY: (map['gyroY'] as List? ?? [])
          .where((p) => p != null)
          .map((p) => DataPoint.fromMap(p as Map<String, dynamic>))
          .toList(),
      gyroZ: (map['gyroZ'] as List? ?? [])
          .where((p) => p != null)
          .map((p) => DataPoint.fromMap(p as Map<String, dynamic>))
          .toList(),
      accelX: (map['accelX'] as List? ?? [])
          .where((p) => p != null)
          .map((p) => DataPoint.fromMap(p as Map<String, dynamic>))
          .toList(),
      accelY: (map['accelY'] as List? ?? [])
          .where((p) => p != null)
          .map((p) => DataPoint.fromMap(p as Map<String, dynamic>))
          .toList(),
      accelZ: (map['accelZ'] as List? ?? [])
          .where((p) => p != null)
          .map((p) => DataPoint.fromMap(p as Map<String, dynamic>))
          .toList(),
      firearmType: FirearmType.fromString(map['firearmType'] ?? 'pistol'),
      trainingMode: TrainingMode.fromString(map['trainingMode'] ?? 'dryFire'),
      shots: (map['shots'] as List? ?? [])
          .where((s) => s != null)
          .map((s) => ShotResult.fromMap(s as Map<String, dynamic>))
          .toList(),
      profileName: map['profileName'] ?? '',
      trainingPreset: map['trainingPreset'] ?? '',
      seriesCount: (map['seriesCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'duration': duration,
      'gyroX': gyroX.map((p) => p.toMap()).toList(),
      'gyroY': gyroY.map((p) => p.toMap()).toList(),
      'gyroZ': gyroZ.map((p) => p.toMap()).toList(),
      'accelX': accelX.map((p) => p.toMap()).toList(),
      'accelY': accelY.map((p) => p.toMap()).toList(),
      'accelZ': accelZ.map((p) => p.toMap()).toList(),
      'firearmType': firearmType.name,
      'trainingMode': trainingMode.name,
      'profileName': profileName,
      'trainingPreset': trainingPreset,
      'seriesCount': seriesCount,
      'shots': shots.map((s) => s.toMap()).toList(),
    };
  }
}

// Kelas yang bertanggung jawab untuk menyimpan & memuat dari SQLite
class SessionLogger {
  final DatabaseService _db;

  SessionLogger({DatabaseService? db}) : _db = db ?? DatabaseService();

  Future<void> saveSession(
    SessionLog log, {
    String? profileName,
    String? trainingPreset,
    int? seriesCount,
  }) async {
    final session =
        (profileName == null && trainingPreset == null && seriesCount == null)
        ? log
        : SessionLog(
            id: log.id,
            date: log.date,
            duration: log.duration,
            gyroX: log.gyroX,
            gyroY: log.gyroY,
            gyroZ: log.gyroZ,
            accelX: log.accelX,
            accelY: log.accelY,
            accelZ: log.accelZ,
            firearmType: log.firearmType,
            trainingMode: log.trainingMode,
            shots: log.shots,
            profileName: profileName ?? log.profileName,
            trainingPreset: trainingPreset ?? log.trainingPreset,
            seriesCount: seriesCount ?? log.seriesCount,
          );
    try {
      await _db.saveSession(session);
      developer.log('Session saved successfully: ${session.id}');
    } catch (e, stack) {
      developer.log(
        'Failed to save session: ${session.id}',
        name: 'SessionLogger',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<List<SessionLog>> loadAllSessions() async {
    return await _db.loadAllSessions();
  }

  Future<void> deleteSession(String sessionId) async {
    await _db.deleteSession(sessionId);
  }
}
