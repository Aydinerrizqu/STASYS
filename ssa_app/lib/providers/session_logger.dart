// ============================================
// File: providers/session_logger.dart (Baru)
// ============================================
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/data_models.dart';

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
  }) : shots = shots ?? [];

  double get averageScore {
    if (shots.isEmpty) return 0;
    return shots.map((s) => s.totalScore).reduce((a, b) => a + b) / shots.length;
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
      'shots': shots.map((s) => s.toMap()).toList(),
    };
  }
}

// Kelas yang bertanggung jawab untuk menyimpan & memuat dari SharedPreferences
class SessionLogger {
  static const _key = 'session_logs';

  Future<void> saveSession(SessionLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final List<SessionLog> allLogs = await loadAllSessions();
    allLogs.add(log);

    // Ubah list of logs menjadi list of strings (JSON)
    List<String> stringList = allLogs.map((log) => json.encode(log.toMap())).toList();
    await prefs.setStringList(_key, stringList);
  }

  Future<List<SessionLog>> loadAllSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? stringList = prefs.getStringList(_key);

    if (stringList == null) {
      return [];
    }

    // Ubah list of strings kembali menjadi list of logs
    return stringList.map((s) => SessionLog.fromMap(json.decode(s))).toList();
  }
  
  Future<void> deleteSession(String sessionId) async {
  final prefs = await SharedPreferences.getInstance();
  final List<SessionLog> allLogs = await loadAllSessions();
  
  // Remove the session with matching ID
  allLogs.removeWhere((log) => log.id == sessionId);
  
  // Save updated list
  List<String> stringList = allLogs.map((log) => json.encode(log.toMap())).toList();
  await prefs.setStringList(_key, stringList);
  }
}
