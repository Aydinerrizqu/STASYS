import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/providers/session_logger.dart';

ShotResult _shot({
  required int series,
  required DateTime timestamp,
  required double score,
}) =>
    ShotResult(
      timestamp: timestamp,
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

void main() {
  group('ShotResult.copyWith', () {
    test('stamps the series number and keeps every other value', () {
      final original = _shot(
        series: 1,
        timestamp: DateTime(2026, 11, 7, 18, 50),
        score: 80,
      );

      final stamped = original.copyWith(seriesNumber: 3);

      expect(stamped.seriesNumber, 3);
      expect(stamped.timestamp, original.timestamp);
      expect(stamped.totalScore, original.totalScore);
      expect(stamped.holdScore, original.holdScore);
      expect(stamped.pressScore, original.pressScore);
      expect(stamped.recoilScore, original.recoilScore);
      expect(stamped.elevationScore, original.elevationScore);
      expect(stamped.windageScore, original.windageScore);
      expect(stamped.firearmType, original.firearmType);
      expect(stamped.trainingMode, original.trainingMode);
    });

    test('keeps the original series number when none is given', () {
      final original = _shot(
        series: 2,
        timestamp: DateTime(2026, 11, 7, 18, 50),
        score: 80,
      );

      expect(original.copyWith().seriesNumber, 2);
    });
  });

  group('SessionLog series getters', () {
    SessionLog sessionWith(List<ShotResult> shots) => SessionLog(
          id: 'series-test',
          date: DateTime(2026, 11, 7),
          duration: 60,
          gyroX: const [],
          gyroY: const [],
          gyroZ: const [],
          accelX: const [],
          accelY: const [],
          accelZ: const [],
          shots: shots,
        );

    test('seriesNumbers lists the distinct series in ascending order', () {
      final session = sessionWith([
        _shot(series: 3, timestamp: DateTime(2026, 11, 7, 18, 52), score: 90),
        _shot(series: 1, timestamp: DateTime(2026, 11, 7, 18, 50), score: 80),
        _shot(series: 1, timestamp: DateTime(2026, 11, 7, 18, 51), score: 82),
      ]);

      expect(session.seriesNumbers, [1, 3]);
    });

    test('a series without shots is not listed', () {
      final session = sessionWith([
        _shot(series: 1, timestamp: DateTime(2026, 11, 7, 18, 50), score: 80),
        _shot(series: 3, timestamp: DateTime(2026, 11, 7, 18, 52), score: 90),
      ]);

      // Series 2 exists in the session but owns no shot, so it is hidden.
      expect(session.seriesNumbers, [1, 3]);
      expect(session.seriesNumbers.contains(2), isFalse);
    });

    test('shotsForSeries returns only the shots of that series', () {
      final session = sessionWith([
        _shot(series: 1, timestamp: DateTime(2026, 11, 7, 18, 50), score: 80),
        _shot(series: 2, timestamp: DateTime(2026, 11, 7, 18, 51), score: 90),
      ]);

      expect(session.shotsForSeries(1), hasLength(1));
      expect(session.shotsForSeries(1).first.totalScore, 80);
      expect(session.shotsForSeries(2).first.totalScore, 90);
      expect(session.shotsForSeries(9), isEmpty);
    });

    test('averageScoreForSeries averages only that series', () {
      final session = sessionWith([
        _shot(series: 1, timestamp: DateTime(2026, 11, 7, 18, 50), score: 80),
        _shot(series: 1, timestamp: DateTime(2026, 11, 7, 18, 51), score: 100),
        _shot(series: 2, timestamp: DateTime(2026, 11, 7, 18, 52), score: 50),
      ]);

      expect(session.averageScoreForSeries(1), 90);
      expect(session.averageScoreForSeries(2), 50);
      expect(session.averageScoreForSeries(9), 0);
    });
  });
}
