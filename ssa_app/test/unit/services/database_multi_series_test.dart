import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/services/database_helper.dart';
import 'package:ssa_app/services/database_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper helper;
  const dbFileName = 'stasys_sessions_multi_series_test.db';

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

  ShotResult shot(int series, double score) => ShotResult(
        timestamp: DateTime(2026, 10, 18, 12, series),
        totalScore: score,
        holdScore: score,
        pressScore: score,
        recoilScore: score,
        elevationScore: score,
        windageScore: score,
        travelDistance: 0.01,
        peakJerk: 1,
        firearmType: FirearmType.pistol,
        trainingMode: TrainingMode.dryFire,
        seriesNumber: series,
      );

  group('Multi-series session persistence', () {
    test('two series of one session produce a single session row', () async {
      final service = DatabaseService(dbHelper: helper);
      const id = 'SESSION_MULTI';
      final date = DateTime(2026, 10, 18);

      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 1,
        date: date,
        seriesDuration: 60,
        shots: [shot(1, 80), shot(1, 81)],
      );

      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 2,
        date: date,
        seriesDuration: 45,
        shots: [shot(2, 92)],
      );

      final sessions = await service.loadAllSessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.id, id);
      expect(sessions.single.shots, hasLength(3));
      expect(
        sessions.single.shots.map((s) => s.seriesNumber).toList(),
        [1, 1, 2],
      );
      // series_count is derived from the shots, so it matches the number of
      // chips the series picker shows.
      expect(sessions.single.seriesCount, 2);
      expect(sessions.single.seriesNumbers, [1, 2]);
      // The duration is the sum of the series.
      expect(sessions.single.duration, 105);
    });

    test('the raw data of each series is stored separately', () async {
      final service = DatabaseService(dbHelper: helper);
      const id = 'SESSION_RAW';
      final date = DateTime(2026, 10, 18);

      final series1 = List.generate(
        10,
        (i) => DataPoint(i / 100, 1.0 + i),
      );
      final series2 = List.generate(
        20,
        (i) => DataPoint(i / 100, 2.0 + i),
      );

      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 1,
        date: date,
        seriesDuration: 30,
        shots: [shot(1, 80)],
        gyroX: series1,
        gyroY: series1,
        gyroZ: series1,
        accelX: series1,
        accelY: series1,
        accelZ: series1,
      );

      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 2,
        date: date,
        seriesDuration: 30,
        shots: [shot(2, 90)],
        gyroX: series2,
        gyroY: series2,
        gyroZ: series2,
        accelX: series2,
        accelY: series2,
        accelZ: series2,
      );

      final seriesRaw = await service.getSeriesRaw(id);
      expect(seriesRaw.keys.toList(), [1, 2]);
      expect(seriesRaw[1]!['gyroX'], hasLength(10));
      expect(seriesRaw[2]!['gyroX'], hasLength(20));
      expect(seriesRaw[1]!['gyroX']!.first.y, 1.0);
      expect(seriesRaw[2]!['gyroX']!.first.y, 2.0);
    });

    test('re-saving the same series replaces its shots without duplicating',
        () async {
      final service = DatabaseService(dbHelper: helper);
      const id = 'SESSION_RESAVE';
      final date = DateTime(2026, 10, 18);

      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 1,
        date: date,
        seriesDuration: 60,
        shots: [shot(1, 80), shot(1, 81)],
      );

      // The user repeats series 1.
      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 1,
        date: date,
        seriesDuration: 60,
        shots: [shot(1, 75)],
      );

      final sessions = await service.loadAllSessions();
      expect(sessions.single.shots, hasLength(1));
      expect(sessions.single.shots.first.totalScore, 75);
      // The duration is not counted twice.
      expect(sessions.single.duration, 60);
    });

    test('a series without shots is not stored and not counted', () async {
      final service = DatabaseService(dbHelper: helper);
      const id = 'SESSION_EMPTY_SERIES';
      final date = DateTime(2026, 10, 18);

      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 1,
        date: date,
        seriesDuration: 60,
        shots: [shot(1, 80)],
      );

      // An empty series writes no shot, so it stays invisible.
      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 2,
        date: date,
        seriesDuration: 30,
        shots: const [],
      );

      final sessions = await service.loadAllSessions();
      expect(sessions.single.seriesCount, 1);
      expect(sessions.single.seriesNumbers, [1]);
    });

    test('getShotsForSeries returns only the shots of that series', () async {
      final service = DatabaseService(dbHelper: helper);
      const id = 'SESSION_SHOTS';
      final date = DateTime(2026, 10, 18);

      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 1,
        date: date,
        seriesDuration: 60,
        shots: [shot(1, 80), shot(1, 81)],
      );
      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 2,
        date: date,
        seriesDuration: 60,
        shots: [shot(2, 92)],
      );

      final series1 = await service.getShotsForSeries(id, 1);
      final series2 = await service.getShotsForSeries(id, 2);

      expect(series1, hasLength(2));
      expect(series2, hasLength(1));
      expect(series2.first.totalScore, 92);
    });

    test('getSession returns every shot of a multi-series session', () async {
      final service = DatabaseService(dbHelper: helper);
      const id = 'SESSION_GET';
      final date = DateTime(2026, 10, 18);

      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 1,
        date: date,
        seriesDuration: 60,
        shots: [shot(1, 80)],
      );
      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 2,
        date: date,
        seriesDuration: 60,
        shots: [shot(2, 92)],
      );

      final loaded = await service.getSession(id);
      expect(loaded, isNotNull);
      expect(loaded!.shots, hasLength(2));
    });

    test('deleting a session removes its series and shots', () async {
      final service = DatabaseService(dbHelper: helper);
      const id = 'SESSION_DELETE';
      final date = DateTime(2026, 10, 18);

      await service.upsertSessionWithSeries(
        sessionId: id,
        seriesNumber: 1,
        date: date,
        seriesDuration: 60,
        shots: [shot(1, 80)],
      );

      await service.deleteSession(id);

      expect(await service.getSession(id), isNull);
      expect(await service.getSeriesRaw(id), isEmpty);
    });
  });
}
