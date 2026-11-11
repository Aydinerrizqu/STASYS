// ============================================
// File: services/database_helper.dart
// ============================================
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Singleton database helper — manages DB lifecycle and schema.
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  /// File name of the SQLite database inside the platform database folder.
  ///
  /// `flutter test` runs test files in parallel, and two files opening the
  /// same SQLite file lock each other out (`database is locked`). Tests
  /// therefore point this at a file name unique to the test file.
  static String databaseFileName = 'stasys_sessions.db';

  factory DatabaseHelper() => _instance;

  /// Reset singleton state for testing only.
  static void resetForTesting() {
    _database = null;
  }

  /// Use a dedicated database file for testing only.
  static void setDatabaseFileNameForTesting(String fileName) {
    databaseFileName = fileName;
    _database = null;
  }

  /// Replace the active database instance for testing only.
  /// Lets a test wrap the database (e.g. to simulate platform limits).
  static void setDatabaseForTesting(Database database) {
    _database = database;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, databaseFileName);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    // Sessions table (renamed from recordings)
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

    // Shots table
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

    // Indexes
    await db.execute('CREATE INDEX idx_sessions_date ON sessions(date DESC)');
    await db.execute(
      'CREATE INDEX idx_sessions_firearm ON sessions(firearm_type)',
    );
    await db.execute('CREATE INDEX idx_shots_session ON shots(session_id)');
    await db.execute('CREATE INDEX idx_shots_score ON shots(total_score DESC)');

    await _createSessionSeriesTable(db);
  }

  /// Raw gyro/accel time series, stored per series.
  ///
  /// A training session can hold several series, so the raw data of one
  /// session is no longer a single blob — it lives here, one row per series.
  /// The UNIQUE constraint is required: without it SQLite never replaces an
  /// existing row on `INSERT OR REPLACE`, and every END SERIES would append
  /// a duplicate row.
  Future<void> _createSessionSeriesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_series (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        series_number INTEGER NOT NULL,
        duration REAL NOT NULL DEFAULT 0,
        gyro_x BLOB,
        gyro_y BLOB,
        gyro_z BLOB,
        accel_x BLOB,
        accel_y BLOB,
        accel_z BLOB,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
        UNIQUE (session_id, series_number)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_session_series '
      'ON session_series(session_id, series_number)',
    );
  }

  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE sessions ADD COLUMN profile_name TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE sessions ADD COLUMN training_preset TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN series_count INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE shots ADD COLUMN series_number INTEGER NOT NULL DEFAULT 1',
      );
    }

    if (oldVersion < 3) {
      await _createSessionSeriesTable(db);

      // Copy the raw data of legacy sessions into series 1 so old sessions
      // stay replayable. INSERT OR IGNORE keeps the migration idempotent.
      await db.execute('''
        INSERT OR IGNORE INTO session_series (
          session_id, series_number, duration,
          gyro_x, gyro_y, gyro_z, accel_x, accel_y, accel_z
        )
        SELECT id, 1, duration,
               gyro_x, gyro_y, gyro_z, accel_x, accel_y, accel_z
        FROM sessions
        WHERE gyro_x IS NOT NULL
      ''');
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
