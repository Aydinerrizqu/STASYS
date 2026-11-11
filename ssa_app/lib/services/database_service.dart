// ============================================
// File: services/database_service.dart
// ============================================
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import '../models/data_models.dart';
import '../providers/session_logger.dart';
import 'database_helper.dart';

/// Service layer for session/shots persistence with SQLite.
/// Uses binary BLOB encoding for time series and phase trace data.
class DatabaseService {
  final DatabaseHelper _dbHelper;

  /// Session metadata columns. The raw gyro/accel BLOBs are deliberately
  /// excluded: Android's SQLite cursor window can only hold ~2 MB per row,
  /// and a session row can exceed that on its own.
  static const List<String> _summaryColumns = [
    'id',
    'date',
    'duration',
    'firearm_type',
    'training_mode',
    'profile_name',
    'training_preset',
    'series_count',
  ];

  /// Size of a single BLOB chunk read. Each chunk is returned as its own
  /// row, so no row can exceed the platform cursor-window limit.
  static const int _blobChunkBytes = 256 * 1024;

  DatabaseService({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  // ==========================================
  // Encoding helpers (time series)
  // ==========================================

  /// Encode list of DataPoints to binary BLOB.
  /// Format: pointCount(int32) + [relTimestamp(float32) + value(float32)] * N
  Uint8List _encodeTimeSeries(List<DataPoint> points) {
    if (points.isEmpty) return Uint8List(0);

    final buf = ByteData(4 + points.length * 8);
    buf.setInt32(0, points.length, Endian.little);
    for (int i = 0; i < points.length; i++) {
      buf.setFloat32(4 + i * 8, points[i].x, Endian.little);
      buf.setFloat32(4 + i * 8 + 4, points[i].y, Endian.little);
    }
    return buf.buffer.asUint8List();
  }

  /// Decode binary BLOB back to list of DataPoints.
  List<DataPoint> _decodeTimeSeries(Uint8List data) {
    if (data.isEmpty) return [];
    final buf = ByteData.sublistView(data);
    final count = buf.getInt32(0, Endian.little);
    final result = <DataPoint>[];
    for (int i = 0; i < count; i++) {
      final ts = buf.getFloat32(4 + i * 8, Endian.little);
      final val = buf.getFloat32(4 + i * 8 + 4, Endian.little);
      result.add(DataPoint(ts, val));
    }
    return result;
  }

  // ==========================================
  // Encoding helpers (phase traces)
  // ==========================================

  /// Encode a list of doubles to binary BLOB.
  Uint8List _encodeDoubleList(List<double>? list) {
    if (list == null || list.isEmpty) return Uint8List(0);
    final buf = ByteData(4 + list.length * 8);
    buf.setInt32(0, list.length, Endian.little);
    for (int i = 0; i < list.length; i++) {
      buf.setFloat64(4 + i * 8, list[i], Endian.little);
    }
    return buf.buffer.asUint8List();
  }

  /// Decode binary BLOB back to list of doubles.
  List<double> _decodeDoubleList(Uint8List data) {
    if (data.isEmpty) return [];
    final buf = ByteData.sublistView(data);
    final count = buf.getInt32(0, Endian.little);
    final result = <double>[];
    for (int i = 0; i < count; i++) {
      result.add(buf.getFloat64(4 + i * 8, Endian.little));
    }
    return result;
  }

  // ==========================================
  // Session CRUD
  // ==========================================

  /// Save a complete session (with shots) to DB.
  ///
  /// Legacy entry point: every shot of [session] is written and the raw
  /// data is stored as series 1. New code should use
  /// [upsertSessionWithSeries], which keeps one raw blob per series.
  Future<void> saveSession(SessionLog session) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await _upsertSessionRow(
        txn,
        sessionId: session.id,
        date: session.date,
        firearmType: session.firearmType,
        trainingMode: session.trainingMode,
        profileName: session.profileName,
        trainingPreset: session.trainingPreset,
      );

      // Replace shot rows so re-saving the same session id (multi-series)
      // does not duplicate bullets.
      await txn.delete(
        'shots',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );

      await _insertShots(txn, session.id, session.shots);

      await _writeSeriesRaw(
        txn,
        sessionId: session.id,
        seriesNumber: 1,
        duration: session.duration,
        gyroX: session.gyroX,
        gyroY: session.gyroY,
        gyroZ: session.gyroZ,
        accelX: session.accelX,
        accelY: session.accelY,
        accelZ: session.accelZ,
      );

      final seriesCount = await _countSeries(txn, session.id);
      await txn.rawUpdate(
        'UPDATE sessions SET '
        'duration = (SELECT COALESCE(SUM(duration), 0) FROM session_series '
        'WHERE session_id = ?), '
        'series_count = ? '
        'WHERE id = ?',
        [session.id, seriesCount, session.id],
      );
    });
  }

  /// Save one series inside a session.
  ///
  /// The session row is created on the first call and updated afterwards.
  /// Shots of [seriesNumber] are replaced, so re-saving the same series never
  /// duplicates bullets. [duration] is the cumulative duration of the whole
  /// session, [seriesDuration] the duration of this series alone.
  ///
  /// The raw sensor data of the series is stored in `session_series`, which
  /// lets the offline replay reconstruct the trace of any single series.
  Future<void> upsertSessionWithSeries({
    required String sessionId,
    required int seriesNumber,
    required DateTime date,
    required double seriesDuration,
    required List<ShotResult> shots,
    FirearmType firearmType = FirearmType.pistol,
    TrainingMode trainingMode = TrainingMode.dryFire,
    String profileName = '',
    String trainingPreset = '',
    List<DataPoint> gyroX = const [],
    List<DataPoint> gyroY = const [],
    List<DataPoint> gyroZ = const [],
    List<DataPoint> accelX = const [],
    List<DataPoint> accelY = const [],
    List<DataPoint> accelZ = const [],
  }) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // The session row must exist before its shots are inserted: foreign
      // keys are enforced.
      await _upsertSessionRow(
        txn,
        sessionId: sessionId,
        date: date,
        firearmType: firearmType,
        trainingMode: trainingMode,
        profileName: profileName,
        trainingPreset: trainingPreset,
      );

      // Replace the shots of this series only — other series stay untouched.
      await txn.delete(
        'shots',
        where: 'session_id = ? AND series_number = ?',
        whereArgs: [sessionId, seriesNumber],
      );
      await _insertShots(txn, sessionId, shots);

      if (shots.isEmpty) {
        // A series without shots is not stored at all: it would only add its
        // duration to the session while staying invisible in the UI.
        await txn.delete(
          'session_series',
          where: 'session_id = ? AND series_number = ?',
          whereArgs: [sessionId, seriesNumber],
        );
      } else {
        await _writeSeriesRaw(
          txn,
          sessionId: sessionId,
          seriesNumber: seriesNumber,
          duration: seriesDuration,
          gyroX: gyroX,
          gyroY: gyroY,
          gyroZ: gyroZ,
          accelX: accelX,
          accelY: accelY,
          accelZ: accelZ,
        );
      }

      // The session duration is the sum of its series, so saving a series
      // twice never counts its duration twice. series_count is derived from
      // the stored shots, which keeps it identical to the number of series
      // the UI shows.
      final seriesCount = await _countSeries(txn, sessionId);
      await txn.rawUpdate(
        'UPDATE sessions SET '
        'duration = (SELECT COALESCE(SUM(duration), 0) FROM session_series '
        'WHERE session_id = ?), '
        'series_count = ? '
        'WHERE id = ?',
        [sessionId, seriesCount, sessionId],
      );
    });
  }

  /// Insert the session row, or update it when it already exists.
  ///
  /// An UPDATE is used instead of `INSERT OR REPLACE` on purpose: replace
  /// deletes the old row first, and `ON DELETE CASCADE` would take the
  /// shots and the raw series data with it.
  Future<void> _upsertSessionRow(
    DatabaseExecutor txn, {
    required String sessionId,
    required DateTime date,
    required FirearmType firearmType,
    required TrainingMode trainingMode,
    required String profileName,
    required String trainingPreset,
  }) async {
    final updated = await txn.update(
      'sessions',
      {
        'firearm_type': firearmType.name,
        'training_mode': trainingMode.name,
        'profile_name': profileName,
        'training_preset': trainingPreset,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    if (updated > 0) return;

    await txn.insert('sessions', {
      'id': sessionId,
      'date': date.millisecondsSinceEpoch,
      'duration': 0,
      'firearm_type': firearmType.name,
      'training_mode': trainingMode.name,
      'profile_name': profileName,
      'training_preset': trainingPreset,
      'series_count': 0,
    });
  }

  Future<void> _insertShots(
    DatabaseExecutor txn,
    String sessionId,
    List<ShotResult> shots,
  ) async {
    if (shots.isEmpty) return;
    final batch = txn.batch();
    for (final shot in shots) {
      batch.insert('shots', {
        'session_id': sessionId,
        'timestamp': shot.timestamp.millisecondsSinceEpoch,
        'total_score': shot.totalScore,
        'hold_score': shot.holdScore,
        'press_score': shot.pressScore,
        'recoil_score': shot.recoilScore,
        'elevation_score': shot.elevationScore,
        'windage_score': shot.windageScore,
        'travel_distance': shot.travelDistance,
        'peak_jerk': shot.peakJerk,
        'firearm_type': shot.firearmType.name,
        'training_mode': shot.trainingMode.name,
        'series_number': shot.seriesNumber,
        'hold_x': _encodeDoubleList(shot.holdX),
        'hold_y': _encodeDoubleList(shot.holdY),
        'press_x': _encodeDoubleList(shot.pressX),
        'press_y': _encodeDoubleList(shot.pressY),
        'recoil_x': _encodeDoubleList(shot.recoilX),
        'recoil_y': _encodeDoubleList(shot.recoilY),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Number of distinct series that own shots in this session.
  Future<int> _countSeries(DatabaseExecutor txn, String sessionId) async {
    final rows = await txn.rawQuery(
      'SELECT COUNT(DISTINCT series_number) AS count FROM shots '
      'WHERE session_id = ?',
      [sessionId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  /// Store the raw sensor data of one series.
  ///
  /// `session_series` has a UNIQUE (session_id, series_number) constraint,
  /// so the replace is scoped to this series only.
  Future<void> _writeSeriesRaw(
    DatabaseExecutor txn, {
    required String sessionId,
    required int seriesNumber,
    required double duration,
    required List<DataPoint> gyroX,
    required List<DataPoint> gyroY,
    required List<DataPoint> gyroZ,
    required List<DataPoint> accelX,
    required List<DataPoint> accelY,
    required List<DataPoint> accelZ,
  }) async {
    await txn.insert('session_series', {
      'session_id': sessionId,
      'series_number': seriesNumber,
      'duration': duration,
      'gyro_x': _encodeTimeSeries(gyroX),
      'gyro_y': _encodeTimeSeries(gyroY),
      'gyro_z': _encodeTimeSeries(gyroZ),
      'accel_x': _encodeTimeSeries(accelX),
      'accel_y': _encodeTimeSeries(accelY),
      'accel_z': _encodeTimeSeries(accelZ),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Load all sessions (sorted by date DESC) with shots.
  Future<List<SessionLog>> loadAllSessions() async {
    final db = await _dbHelper.database;
    final sessionRows = await db.query(
      'sessions',
      columns: _summaryColumns,
      orderBy: 'date DESC',
    );

    final result = <SessionLog>[];
    for (final row in sessionRows) {
      final session = await _sessionFromRow(row);
      if (session != null) {
        result.add(session);
      }
    }
    return result;
  }

  /// Load a single session by ID with its shots.
  ///
  /// The raw sensor data is deliberately not loaded here: a session can hold
  /// several series, each with its own raw data, so there is no single raw
  /// blob for the session. Use [getSeriesRaw] for that.
  Future<SessionLog?> getSession(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'sessions',
      columns: _summaryColumns,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;

    return _sessionFromRow(rows.first);
  }

  /// Load the shots of one series of a session.
  Future<List<ShotResult>> getShotsForSeries(
    String sessionId,
    int seriesNumber,
  ) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'shots',
      where: 'session_id = ? AND series_number = ?',
      whereArgs: [sessionId, seriesNumber],
      orderBy: 'timestamp ASC',
    );
    return rows.map(_shotFromRow).whereType<ShotResult>().toList();
  }

  /// Delete a session and all its shots (CASCADE).
  Future<void> deleteSession(String sessionId) async {
    final db = await _dbHelper.database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  /// Decode the raw sensor time series for a session from the DB.
  /// Returns a map with keys 'gyroX/Y/Z' and 'accelX/Y/Z'.
  /// Each value is the decoded list of data points.
  /// Returns an empty map if the session doesn't exist.
  ///
  /// Reads series 1 of the session. Falls back to the legacy BLOB columns of
  /// `sessions` when the session has no `session_series` row.
  Future<Map<String, List<DataPoint>>> decodeRawSession(
    String sessionId,
  ) async {
    final seriesRaw = await getSeriesRaw(sessionId);
    if (seriesRaw.isNotEmpty) {
      return seriesRaw[1] ?? seriesRaw.values.first;
    }
    final raw = await _readRawColumns(sessionId);
    if (raw.isEmpty) return {};
    return {
      'gyroX': raw['gyroX'] ?? const [],
      'gyroY': raw['gyroY'] ?? const [],
      'gyroZ': raw['gyroZ'] ?? const [],
      'accelX': raw['accelX'] ?? const [],
      'accelY': raw['accelY'] ?? const [],
      'accelZ': raw['accelZ'] ?? const [],
    };
  }

  /// Raw sensor data of every series of a session, keyed by series number.
  ///
  /// Sessions saved before the schema v3 migration have no `session_series`
  /// row; for those the legacy BLOB columns of `sessions` are returned as
  /// series 1 so old sessions stay replayable.
  Future<Map<int, Map<String, List<DataPoint>>>> getSeriesRaw(
    String sessionId,
  ) async {
    final db = await _dbHelper.database;

    final rows = await db.query(
      'session_series',
      columns: ['series_number'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'series_number ASC',
    );
    if (rows.isEmpty) {
      final legacy = await _readRawColumns(sessionId);
      // A legacy session without raw data owns no series data at all.
      if (!legacy.values.any((series) => series.isNotEmpty)) return {};
      return {
        1: {
          'gyroX': legacy['gyroX'] ?? const [],
          'gyroY': legacy['gyroY'] ?? const [],
          'gyroZ': legacy['gyroZ'] ?? const [],
          'accelX': legacy['accelX'] ?? const [],
          'accelY': legacy['accelY'] ?? const [],
          'accelZ': legacy['accelZ'] ?? const [],
        },
      };
    }

    final result = <int, Map<String, List<DataPoint>>>{};
    for (final row in rows) {
      final seriesNumber = (row['series_number'] as num).toInt();
      result[seriesNumber] = await _readSeriesRawColumns(
        sessionId,
        seriesNumber,
      );
    }
    return result;
  }

  // ==========================================
  // Raw sensor columns (chunked reads)
  // ==========================================

  /// Read the six raw sensor BLOBs of a session.
  ///
  /// Each BLOB is read in chunks so that a single returned row never
  /// exceeds the platform cursor-window limit (~2 MB on Android). Reading
  /// the whole row at once fails with
  /// `Row too big to fit into CursorWindow` for long sessions.
  Future<Map<String, List<DataPoint>>> _readRawColumns(String sessionId) async {
    final db = await _dbHelper.database;

    final exists = await db.rawQuery(
      'SELECT 1 FROM sessions WHERE id = ? LIMIT 1',
      [sessionId],
    );
    if (exists.isEmpty) return {};

    const columns = {
      'gyroX': 'gyro_x',
      'gyroY': 'gyro_y',
      'gyroZ': 'gyro_z',
      'accelX': 'accel_x',
      'accelY': 'accel_y',
      'accelZ': 'accel_z',
    };

    final result = <String, List<DataPoint>>{};
    for (final entry in columns.entries) {
      result[entry.key] = await _readBlobColumn(sessionId, entry.value);
    }
    return result;
  }

  /// Read the six raw sensor BLOBs of one series of a session.
  Future<Map<String, List<DataPoint>>> _readSeriesRawColumns(
    String sessionId,
    int seriesNumber,
  ) async {
    const columns = {
      'gyroX': 'gyro_x',
      'gyroY': 'gyro_y',
      'gyroZ': 'gyro_z',
      'accelX': 'accel_x',
      'accelY': 'accel_y',
      'accelZ': 'accel_z',
    };

    final result = <String, List<DataPoint>>{};
    for (final entry in columns.entries) {
      result[entry.key] = await _readSeriesBlobColumn(
        sessionId,
        seriesNumber,
        entry.value,
      );
    }
    return result;
  }

  /// Read one BLOB column in chunks and decode it into data points.
  Future<List<DataPoint>> _readBlobColumn(
    String sessionId,
    String column,
  ) async {
    final db = await _dbHelper.database;

    // Total length of the BLOB.
    final lengthRows = await db.rawQuery(
      'SELECT length($column) AS len FROM sessions WHERE id = ?',
      [sessionId],
    );
    if (lengthRows.isEmpty) return [];
    final total = (lengthRows.first['len'] as int?) ?? 0;
    if (total <= 0) return [];

    final bytes = BytesBuilder(copy: false);
    for (var offset = 0; offset < total; offset += _blobChunkBytes) {
      final chunkRows = await db.rawQuery(
        'SELECT substr($column, ?, ?) AS chunk FROM sessions WHERE id = ?',
        [offset + 1, _blobChunkBytes, sessionId],
      );
      if (chunkRows.isEmpty) break;
      final chunk = chunkRows.first['chunk'];
      if (chunk is Uint8List) {
        bytes.add(chunk);
      } else if (chunk is List<int>) {
        bytes.add(Uint8List.fromList(chunk));
      } else {
        break;
      }
    }

    return _decodeTimeSeries(bytes.toBytes());
  }

  /// Read one BLOB column of a series in chunks and decode it.
  Future<List<DataPoint>> _readSeriesBlobColumn(
    String sessionId,
    int seriesNumber,
    String column,
  ) async {
    final db = await _dbHelper.database;

    final lengthRows = await db.rawQuery(
      'SELECT length($column) AS len FROM session_series '
      'WHERE session_id = ? AND series_number = ?',
      [sessionId, seriesNumber],
    );
    if (lengthRows.isEmpty) return [];
    final total = (lengthRows.first['len'] as int?) ?? 0;
    if (total <= 0) return [];

    final bytes = BytesBuilder(copy: false);
    for (var offset = 0; offset < total; offset += _blobChunkBytes) {
      final chunkRows = await db.rawQuery(
        'SELECT substr($column, ?, ?) AS chunk FROM session_series '
        'WHERE session_id = ? AND series_number = ?',
        [offset + 1, _blobChunkBytes, sessionId, seriesNumber],
      );
      if (chunkRows.isEmpty) break;
      final chunk = chunkRows.first['chunk'];
      if (chunk is Uint8List) {
        bytes.add(chunk);
      } else if (chunk is List<int>) {
        bytes.add(Uint8List.fromList(chunk));
      } else {
        break;
      }
    }

    return _decodeTimeSeries(bytes.toBytes());
  }

  // ==========================================
  // Row → SessionLog reconstruction
  // ==========================================

  Future<SessionLog?> _sessionFromRow(Map<String, Object?> row) async {
    try {
      final sessionId = row['id'] as String;
      final shots = await _loadShotsForSession(sessionId);

      return SessionLog(
        id: sessionId,
        date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int),
        duration: (row['duration'] as num).toDouble(),
        firearmType: FirearmType.fromString(row['firearm_type'] as String),
        trainingMode: TrainingMode.fromString(row['training_mode'] as String),
        profileName: (row['profile_name'] as String?) ?? '',
        trainingPreset: (row['training_preset'] as String?) ?? '',
        seriesCount: (row['series_count'] as num?)?.toInt() ?? 0,
        gyroX: const [],
        gyroY: const [],
        gyroZ: const [],
        accelX: const [],
        accelY: const [],
        accelZ: const [],
        shots: shots,
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<ShotResult>> _loadShotsForSession(String sessionId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'shots',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );

    return rows.map(_shotFromRow).whereType<ShotResult>().toList();
  }

  ShotResult? _shotFromRow(Map<String, Object?> row) {
    try {
      return ShotResult(
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
        totalScore: (row['total_score'] as num).toDouble(),
        holdScore: (row['hold_score'] as num).toDouble(),
        pressScore: (row['press_score'] as num).toDouble(),
        recoilScore: (row['recoil_score'] as num).toDouble(),
        elevationScore: (row['elevation_score'] as num).toDouble(),
        windageScore: (row['windage_score'] as num).toDouble(),
        travelDistance: (row['travel_distance'] as num).toDouble(),
        peakJerk: (row['peak_jerk'] as num).toDouble(),
        firearmType: FirearmType.fromString(row['firearm_type'] as String),
        trainingMode: TrainingMode.fromString(row['training_mode'] as String),
        seriesNumber: (row['series_number'] as num?)?.toInt() ?? 1,
        holdX: _decodeDoubleBlob(row['hold_x']),
        holdY: _decodeDoubleBlob(row['hold_y']),
        pressX: _decodeDoubleBlob(row['press_x']),
        pressY: _decodeDoubleBlob(row['press_y']),
        recoilX: _decodeDoubleBlob(row['recoil_x']),
        recoilY: _decodeDoubleBlob(row['recoil_y']),
      );
    } catch (e) {
      return null;
    }
  }

  List<double> _decodeDoubleBlob(Object? blob) {
    if (blob == null) return [];
    if (blob is Uint8List) return _decodeDoubleList(blob);
    if (blob is List<int>) return _decodeDoubleList(Uint8List.fromList(blob));
    return [];
  }
}
