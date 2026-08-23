import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/providers/session_logger.dart';
import 'package:ssa_app/screens/session_detail_screen.dart';

void main() {
  group('SessionDetailScreen layout', () {
  testWidgets('renders a saved session with a selected shot without layout errors',
      (tester) async {
    final shot = ShotResult(
      timestamp: DateTime(2026, 8, 23, 12),
      totalScore: 80,
      holdScore: 80,
      pressScore: 80,
      recoilScore: 80,
      elevationScore: 80,
      windageScore: 80,
      travelDistance: 0.1,
      peakJerk: 1.0,
      firearmType: FirearmType.pistol,
      trainingMode: TrainingMode.dryFire,
      holdX: const [0.0, 0.001],
      holdY: const [0.0, 0.001],
      pressX: const [0.001, 0.002],
      pressY: const [0.001, 0.002],
      recoilX: const [0.002, 0.003],
      recoilY: const [0.002, 0.003],
    );
    final session = SessionLog(
      id: 'layout-test',
      date: DateTime(2026, 8, 23),
      duration: 5,
      gyroX: const [],
      gyroY: const [],
      gyroZ: const [],
      accelX: const [],
      accelY: const [],
      accelZ: const [],
      shots: [shot],
    );

    await tester.pumpWidget(
      MaterialApp(home: SessionDetailScreen(session: session)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
  });
}
