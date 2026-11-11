import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/providers/session_logger.dart';
import 'package:ssa_app/services/export_service.dart';

ShotResult _shot({
  required DateTime timestamp,
  required double score,
  int seriesNumber = 1,
}) {
  return ShotResult(
    timestamp: timestamp,
    totalScore: score,
    holdScore: score - 1,
    pressScore: score - 2,
    recoilScore: score - 3,
    elevationScore: score - 4,
    windageScore: score - 5,
    travelDistance: 0.1,
    peakJerk: 1.0,
    firearmType: FirearmType.pistol,
    trainingMode: TrainingMode.dryFire,
    seriesNumber: seriesNumber,
  );
}

SessionLog _session({bool multiSeries = false}) => SessionLog(
  id: 'export-test',
  date: DateTime(2026, 11, 7, 18, 30),
  duration: 120,
  gyroX: const [],
  gyroY: const [],
  gyroZ: const [],
  accelX: const [],
  accelY: const [],
  accelZ: const [],
  firearmType: FirearmType.pistol,
  trainingMode: TrainingMode.dryFire,
  profileName: 'Export Profile',
  trainingPreset: 'dry-air-softgun-10',
  shots: [
    _shot(timestamp: DateTime(2026, 11, 7, 18, 30), score: 80),
    if (multiSeries)
      _shot(
        timestamp: DateTime(2026, 11, 7, 18, 31),
        score: 92,
        seriesNumber: 2,
      ),
  ],
);

void main() {
  group('ExportService CSV', () {
    test('writes the series number of every shot', () {
      final csv = ExportService().exportSessionsToCSV([_session(multiSeries: true)]);

      // The header carries the series column.
      expect(csv, contains('series_number'));
      // Both shots are written, each with its own series number.
      final shotRows = csv
          .split('\n')
          .where((line) => line.contains('2026-11-07 18:3'))
          .toList();
      expect(shotRows.any((row) => row.contains(',1,2026-11-07 18:30:00')), isTrue);
      expect(shotRows.any((row) => row.contains(',2,2026-11-07 18:31:00')), isTrue);
    });

    test('the session summary counts the distinct series', () {
      final csv = ExportService().exportSessionsToCSV([_session(multiSeries: true)]);

      final summaryRow = csv
          .split('\n')
          .firstWhere((line) => line.startsWith('2026-11-07 18:30:00,pistol'));
      // series_count is the number of series that own shots.
      expect(summaryRow.trim().endsWith('2'), isTrue);
    });

    test('a single-series session reports one series', () {
      final csv = ExportService().exportSessionsToCSV([_session()]);

      final summaryRow = csv
          .split('\n')
          .firstWhere((line) => line.startsWith('2026-11-07 18:30:00,pistol'));
      expect(summaryRow.trim().endsWith('1'), isTrue);
    });
  });
}
