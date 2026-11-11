import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ssa_app/services/database_helper.dart';
import 'package:ssa_app/services/database_service.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/providers/session_logger.dart';

/// Migration test: opens a v1 database, inserts legacy rows, upgrades to v2,
/// and asserts the new columns have safe default values.
void main() {
  // Initialise sqflite_ffi for desktop test runner.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper helper;

  /// This file owns its own SQLite file so it can run in parallel with the
  /// other database test files without locking each other out.
  const dbFileName = 'stasys_sessions_migration_test.db';

  setUp(() async {
    helper = DatabaseHelper();
    // Reset singleton state so each test gets a fresh DB.
    DatabaseHelper.resetForTesting();
    DatabaseHelper.setDatabaseFileNameForTesting(dbFileName);
    final dbPath = await getDatabasesPath();
    await deleteDatabase('$dbPath/$dbFileName');
  });

  tearDown(() async {
    await helper.close();
    final dbPath = await getDatabasesPath();
    await deleteDatabase('$dbPath/$dbFileName');
  });

  group('Database migration v1 → v2', () {
    test(
      'legacy session gets empty profile, empty preset, zero series count',
      () async {
        // Open a v1 database directly (bypass DatabaseHelper).
        final dbPath = await getDatabasesPath();
        final path = '$dbPath/$dbFileName';

        final db = await openDatabase(
          path,
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              date INTEGER NOT NULL,
              duration REAL NOT NULL,
              firearm_type TEXT NOT NULL,
              training_mode TEXT NOT NULL,
              gyro_x BLOB,
              gyro_y BLOB,
              gyro_z BLOB,
              accel_x BLOB,
              accel_y BLOB,
              accel_z BLOB
            )
          ''');
            await db.execute('''
            CREATE TABLE shots (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              total_score REAL NOT NULL,
              hold_score REAL NOT NULL,
              press_score REAL NOT NULL,
              recoil_score REAL NOT NULL,
              elevation_score REAL NOT NULL,
              windage_score REAL NOT NULL,
              travel_distance REAL NOT NULL,
              peak_jerk REAL NOT NULL,
              firearm_type TEXT NOT NULL,
              training_mode TEXT NOT NULL,
              hold_x BLOB,
              hold_y BLOB,
              press_x BLOB,
              press_y BLOB,
              recoil_x BLOB,
              recoil_y BLOB,
              FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
          ''');
          },
        );

        // Insert a legacy session (no profile_name, training_preset, series_count).
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert('sessions', {
          'id': 'LEGACY_SESSION',
          'date': now,
          'duration': 60.0,
          'firearm_type': 'pistol',
          'training_mode': 'dryFire',
        });

        // Insert a legacy shot (no series_number).
        await db.insert('shots', {
          'session_id': 'LEGACY_SESSION',
          'timestamp': now,
          'total_score': 85.0,
          'hold_score': 80.0,
          'press_score': 90.0,
          'recoil_score': 85.0,
          'elevation_score': 78.0,
          'windage_score': 82.0,
          'travel_distance': 0.001,
          'peak_jerk': 5.0,
          'firearm_type': 'pistol',
          'training_mode': 'dryFire',
        });

        await db.close();

        // Now open via DatabaseHelper which triggers the v1→v2 upgrade.
        DatabaseHelper.resetForTesting();
        final service = DatabaseService(dbHelper: helper);
        final sessions = await service.loadAllSessions();

        expect(sessions, hasLength(1));
        final session = sessions.first;

        // New session columns must have safe defaults.
        expect(session.id, 'LEGACY_SESSION');
        expect(session.profileName, '');
        expect(session.trainingPreset, '');
        expect(session.seriesCount, 0);

        // New shot column must have safe default.
        expect(session.shots, hasLength(1));
        expect(session.shots.first.seriesNumber, 1);
      },
    );

    test('new session with metadata persists and loads correctly', () async {
      final service = DatabaseService(dbHelper: helper);

      final session = SessionLog(
        id: 'NEW_SESSION',
        date: DateTime.now(),
        duration: 120.0,
        gyroX: [],
        gyroY: [],
        gyroZ: [],
        accelX: [],
        accelY: [],
        accelZ: [],
        firearmType: FirearmType.rifle,
        trainingMode: TrainingMode.liveFire,
        profileName: 'Test Profile',
        trainingPreset: 'live-rifle-50',
        seriesCount: 5,
        shots: [
          ShotResult(
            timestamp: DateTime.now(),
            totalScore: 92.0,
            holdScore: 88.0,
            pressScore: 95.0,
            recoilScore: 93.0,
            elevationScore: 90.0,
            windageScore: 87.0,
            travelDistance: 0.002,
            peakJerk: 6.0,
            firearmType: FirearmType.rifle,
            trainingMode: TrainingMode.liveFire,
            seriesNumber: 3,
          ),
        ],
      );

      await service.saveSession(session);
      final loaded = await service.getSession('NEW_SESSION');

      expect(loaded, isNotNull);
      expect(loaded!.profileName, 'Test Profile');
      expect(loaded.trainingPreset, 'live-rifle-50');
      // series_count is derived from the stored shots: this session holds a
      // single series (number 3).
      expect(loaded.seriesCount, 1);
      expect(loaded.shots.first.seriesNumber, 3);
    });

    test(
      'History summary omits raw BLOBs while decodeRawSession hydrates them',
      () async {
        final service = DatabaseService(dbHelper: helper);
        final rawPoints = List.generate(
          40000,
          (index) => DataPoint(index / 100, index / 10),
        );
        final session = SessionLog(
          id: 'LARGE_RAW_SESSION',
          date: DateTime(2026, 10, 18),
          duration: 400,
          gyroX: rawPoints,
          gyroY: rawPoints,
          gyroZ: rawPoints,
          accelX: rawPoints,
          accelY: rawPoints,
          accelZ: rawPoints,
          firearmType: FirearmType.pistol,
          trainingMode: TrainingMode.dryFire,
          profileName: 'Large Session',
          trainingPreset: 'dry-air-softgun-10',
          seriesCount: 1,
          shots: [
            ShotResult(
              timestamp: DateTime(2026, 10, 18),
              totalScore: 82,
              holdScore: 81,
              pressScore: 82,
              recoilScore: 83,
              elevationScore: 80,
              windageScore: 80,
              travelDistance: 0.01,
              peakJerk: 1,
              firearmType: FirearmType.pistol,
              trainingMode: TrainingMode.dryFire,
            ),
          ],
        );
        await service.saveSession(session);

        final historySessions = await service.loadAllSessions();
        expect(historySessions, hasLength(1));
        expect(historySessions.single.id, 'LARGE_RAW_SESSION');
        expect(historySessions.single.profileName, 'Large Session');
        expect(historySessions.single.shots, hasLength(1));
        expect(historySessions.single.hasRawData, isFalse);

        // getSession does not hydrate the raw data any more: a session can
        // hold several series, each with its own raw data.
        final detailSession = await service.getSession('LARGE_RAW_SESSION');
        expect(detailSession, isNotNull);
        expect(detailSession!.hasRawData, isFalse);
        expect(detailSession.shots, hasLength(1));

        // The raw data is read per series.
        final raw = await service.decodeRawSession('LARGE_RAW_SESSION');
        expect(raw['gyroX'], hasLength(rawPoints.length));
        expect(raw['accelZ'], hasLength(rawPoints.length));

        final seriesRaw = await service.getSeriesRaw('LARGE_RAW_SESSION');
        expect(seriesRaw.keys.toList(), [1]);
        expect(seriesRaw[1]!['gyroX'], hasLength(rawPoints.length));
      },
    );

    test('missing session yields null session and empty raw map', () async {
      final service = DatabaseService(dbHelper: helper);

      expect(await service.getSession('DOES_NOT_EXIST'), isNull);
      expect(await service.decodeRawSession('DOES_NOT_EXIST'), isEmpty);
    });
  });

  group('Database migration v2 → v3', () {
    /// Open a v2 database with a legacy session that owns raw data.
    Future<void> createLegacyV2Database(String path) async {
      final db = await openDatabase(
        path,
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              date INTEGER NOT NULL,
              duration REAL NOT NULL,
              firearm_type TEXT NOT NULL,
              training_mode TEXT NOT NULL,
              profile_name TEXT NOT NULL DEFAULT '',
              training_preset TEXT NOT NULL DEFAULT '',
              series_count INTEGER NOT NULL DEFAULT 0,
              gyro_x BLOB,
              gyro_y BLOB,
              gyro_z BLOB,
              accel_x BLOB,
              accel_y BLOB,
              accel_z BLOB
            )
          ''');
          await db.execute('''
            CREATE TABLE shots (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              total_score REAL NOT NULL,
              hold_score REAL NOT NULL,
              press_score REAL NOT NULL,
              recoil_score REAL NOT NULL,
              elevation_score REAL NOT NULL,
              windage_score REAL NOT NULL,
              travel_distance REAL NOT NULL,
              peak_jerk REAL NOT NULL,
              firearm_type TEXT NOT NULL,
              training_mode TEXT NOT NULL,
              series_number INTEGER NOT NULL DEFAULT 1,
              hold_x BLOB,
              hold_y BLOB,
              press_x BLOB,
              press_y BLOB,
              recoil_x BLOB,
              recoil_y BLOB,
              FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
          ''');
        },
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      // A raw blob of 4 points, encoded the same way the service does.
      final raw = ByteData(4 + 4 * 8);
      raw.setInt32(0, 4, Endian.little);
      for (var i = 0; i < 4; i++) {
        raw.setFloat32(4 + i * 8, i / 100, Endian.little);
        raw.setFloat32(4 + i * 8 + 4, i + 1.0, Endian.little);
      }
      final blob = raw.buffer.asUint8List();

      await db.insert('sessions', {
        'id': 'V2_SESSION',
        'date': now,
        'duration': 42.0,
        'firearm_type': 'pistol',
        'training_mode': 'dryFire',
        'profile_name': 'Legacy',
        'training_preset': 'dry-air-softgun-10',
        'series_count': 1,
        'gyro_x': blob,
        'gyro_y': blob,
        'gyro_z': blob,
        'accel_x': blob,
        'accel_y': blob,
        'accel_z': blob,
      });

      await db.insert('shots', {
        'session_id': 'V2_SESSION',
        'timestamp': now,
        'total_score': 85.0,
        'hold_score': 80.0,
        'press_score': 90.0,
        'recoil_score': 85.0,
        'elevation_score': 78.0,
        'windage_score': 82.0,
        'travel_distance': 0.001,
        'peak_jerk': 5.0,
        'firearm_type': 'pistol',
        'training_mode': 'dryFire',
        'series_number': 1,
      });

      await db.close();
    }

    test('legacy raw data is copied into session_series as series 1',
        () async {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/$dbFileName';
      await deleteDatabase(path);
      await createLegacyV2Database(path);

      // Opening through DatabaseHelper triggers the v2 → v3 upgrade.
      DatabaseHelper.resetForTesting();
      final service = DatabaseService(dbHelper: helper);

      final sessions = await service.loadAllSessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.id, 'V2_SESSION');
      // The legacy shot keeps series_number = 1.
      expect(sessions.single.shots, hasLength(1));
      expect(sessions.single.shots.first.seriesNumber, 1);
      expect(sessions.single.seriesCount, 1);

      // The raw data now lives in session_series, under series number 1.
      final seriesRaw = await service.getSeriesRaw('V2_SESSION');
      expect(seriesRaw.keys.toList(), [1]);
      expect(seriesRaw[1]!['gyroX'], hasLength(4));
      expect(seriesRaw[1]!['gyroX']!.first.y, 1.0);
      expect(seriesRaw[1]!['accelZ'], hasLength(4));

      // The legacy row is not deleted.
      final legacyRaw = await service.decodeRawSession('V2_SESSION');
      expect(legacyRaw['gyroX'], hasLength(4));
    });

    test('a legacy session without raw data gets no session_series row',
        () async {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/$dbFileName';
      await deleteDatabase(path);
      await createLegacyV2Database(path);

      final db = await openDatabase(path, version: 2);
      await db.insert('sessions', {
        'id': 'V2_NO_RAW',
        'date': DateTime.now().millisecondsSinceEpoch,
        'duration': 10.0,
        'firearm_type': 'pistol',
        'training_mode': 'dryFire',
        'profile_name': '',
        'training_preset': '',
        'series_count': 0,
      });
      await db.close();

      DatabaseHelper.resetForTesting();
      final service = DatabaseService(dbHelper: helper);

      final sessions = await service.loadAllSessions();
      expect(sessions, hasLength(2));
      expect(await service.getSeriesRaw('V2_NO_RAW'), isEmpty);
    });
  });
}
