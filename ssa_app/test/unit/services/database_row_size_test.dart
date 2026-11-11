import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/providers/session_logger.dart';
import 'package:ssa_app/services/database_helper.dart';
import 'package:ssa_app/services/database_service.dart';

/// Android's SQLite cursor window can hold ~2 MB per row. Anything bigger is
/// rejected with `Row too big to fit into CursorWindow`. The limit used here
/// is deliberately smaller so the test does not need a huge fixture.
const int kMaxRowBytes = 1024 * 1024;

/// Database wrapper that rejects any row whose BLOB payload is larger than
/// [kMaxRowBytes], mimicking the platform cursor-window limit.
class _GuardedDatabase implements Database {
  _GuardedDatabase(this._inner);

  final Database _inner;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final rows = await _inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    _guard(rows);
    return rows;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final rows = await _inner.rawQuery(sql, arguments);
    _guard(rows);
    return rows;
  }

  void _guard(List<Map<String, Object?>> rows) {
    for (final row in rows) {
      var bytes = 0;
      for (final value in row.values) {
        if (value is Uint8List) bytes += value.length;
      }
      if (bytes > kMaxRowBytes) {
        throw Exception('Row too big to fit into CursorWindow');
      }
    }
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _inner.execute(sql, arguments);

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _inner.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _inner.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _inner.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => _inner.transaction<T>(action, exclusive: exclusive);

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) =>
      _inner.readTransaction<T>(action);

  @override
  String get path => _inner.path;

  @override
  Future<void> close() => _inner.close();

  @override
  bool get isOpen => _inner.isOpen;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper helper;

  /// This file owns its own SQLite file so it can run in parallel with the
  /// other database test files without locking each other out.
  const dbFileName = 'stasys_sessions_row_size_test.db';

  setUp(() async {
    helper = DatabaseHelper();
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

  group('Cursor-window row limit', () {
    /// 30 000 samples per axis = ~234 KB per axis = ~1.37 MB for the whole
    /// session row, which is over the simulated platform limit.
    List<DataPoint> rawPoints() =>
        List.generate(30000, (index) => DataPoint(index / 100, index % 7 / 7));

    SessionLog hugeSession({bool withShot = false}) => SessionLog(
      id: 'HUGE_SESSION',
      date: DateTime(2026, 10, 18),
      duration: 300,
      gyroX: rawPoints(),
      gyroY: rawPoints(),
      gyroZ: rawPoints(),
      accelX: rawPoints(),
      accelY: rawPoints(),
      accelZ: rawPoints(),
      firearmType: FirearmType.pistol,
      trainingMode: TrainingMode.dryFire,
      profileName: 'Huge Session',
      trainingPreset: 'dry-air-softgun-10',
      seriesCount: 1,
      shots: withShot
          ? [
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
            ]
          : const [],
    );

    test(
      'getSession loads a session whose raw row exceeds the row limit',
      () async {
        final db = await helper.database;
        DatabaseHelper.setDatabaseForTesting(_GuardedDatabase(db));
        final service = DatabaseService(dbHelper: helper);
        await service.saveSession(hugeSession(withShot: true));

        final loaded = await service.getSession('HUGE_SESSION');

        expect(loaded, isNotNull);
        expect(loaded!.shots, hasLength(1));
        // getSession does not read the raw BLOBs any more — the raw data is
        // read per series (see the decodeRawSession test below).
        expect(loaded.hasRawData, isFalse);
      },
    );

    test(
      'decodeRawSession reads a session whose raw row exceeds the row limit',
      () async {
        final db = await helper.database;
        DatabaseHelper.setDatabaseForTesting(_GuardedDatabase(db));
        final service = DatabaseService(dbHelper: helper);
        await service.saveSession(hugeSession());

        final raw = await service.decodeRawSession('HUGE_SESSION');

        expect(raw['gyroX'], hasLength(30000));
        expect(raw['accelZ'], hasLength(30000));
        expect(raw['gyroX']!.first.y, 0.0);
        expect(raw['gyroX']!.last.y, closeTo((29999 % 7) / 7, 1e-6));
      },
    );

    test(
      'loadAllSessions still lists a session with an oversized raw row',
      () async {
        final db = await helper.database;
        DatabaseHelper.setDatabaseForTesting(_GuardedDatabase(db));
        final service = DatabaseService(dbHelper: helper);
        await service.saveSession(hugeSession(withShot: true));

        final sessions = await service.loadAllSessions();

        expect(sessions, hasLength(1));
        expect(sessions.single.id, 'HUGE_SESSION');
        expect(sessions.single.hasRawData, isFalse);
        expect(sessions.single.shots, hasLength(1));
      },
    );
  });
}
