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

  setUp(() async {
    helper = DatabaseHelper();
    // Reset singleton state so each test gets a fresh DB.
    DatabaseHelper.resetForTesting();
    final dbPath = await getDatabasesPath();
    await deleteDatabase('$dbPath/stasys_sessions.db');
  });

  tearDown(() async {
    await helper.close();
  });

  group('Database migration v1 → v2', () {
    test(
      'legacy session gets empty profile, empty preset, zero series count',
      () async {
        // Open a v1 database directly (bypass DatabaseHelper).
        final dbPath = await getDatabasesPath();
        final path = '$dbPath/stasys_sessions.db';

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
      expect(loaded.seriesCount, 5);
      expect(loaded.shots.first.seriesNumber, 3);
    });
  });
}
