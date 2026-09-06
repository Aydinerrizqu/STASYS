import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/providers/session_logger.dart';
import 'package:ssa_app/screens/session_detail_screen.dart';

ShotResult _shot({
  required DateTime timestamp,
  required double score,
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
    holdX: const [0.0, 0.001],
    holdY: const [0.0, 0.001],
    pressX: const [0.001, 0.002],
    pressY: const [0.001, 0.002],
    recoilX: const [0.002, 0.003],
    recoilY: const [0.002, 0.003],
  );
}

SessionLog _session() {
  return SessionLog(
    id: 'layout-test',
    date: DateTime(2026, 8, 23),
    duration: 5,
    gyroX: const [],
    gyroY: const [],
    gyroZ: const [],
    accelX: const [],
    accelY: const [],
    accelZ: const [],
    shots: [
      _shot(timestamp: DateTime(2026, 8, 23, 12), score: 80),
      _shot(timestamp: DateTime(2026, 8, 23, 12, 1), score: 92),
    ],
  );
}

Widget _testApp() => MaterialApp(home: SessionDetailScreen(session: _session()));

void main() {
  group('SessionDetailScreen layout', () {
    testWidgets('defaults to TARGET and renders score without layout errors',
        (tester) async {
      await tester.pumpWidget(_testApp());
      await tester.pump();

      expect(find.text('TARGET'), findsOneWidget);
      expect(find.text('SHOT DATA'), findsOneWidget);
      expect(find.text('ANALYSIS'), findsOneWidget);
      expect(find.text('SCORE'), findsOneWidget);
      expect(find.text('MATCH TOTAL'), findsOneWidget);
      expect(find.text('92'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting the second shot updates the target score', (tester) async {
      await tester.pumpWidget(_testApp());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('shot-chip-0')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('target-score'))).data,
        '80',
      );

      await tester.tap(find.byKey(const ValueKey('shot-chip-1')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('target-score'))).data,
        '92',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SHOT DATA preserves phase scores and does not throw', (tester) async {
      await tester.pumpWidget(_testApp());
      await tester.pump();

      await tester.tap(find.text('SHOT DATA'));
      await tester.pump();

      expect(find.text('HOLD'), findsWidgets);
      expect(find.text('PRESS'), findsWidgets);
      expect(find.text('RECOIL'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ANALYSIS tab remains available without throwing', (tester) async {
      await tester.pumpWidget(_testApp());
      await tester.pump();

      await tester.tap(find.text('ANALYSIS'));
      await tester.pump();

      expect(find.text('ANALYSIS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty session shows NO SHOTS and no shot chips', (tester) async {
      SessionLog emptySession() => SessionLog(
        id: 'empty-test',
        date: DateTime(2026, 8, 23),
        duration: 5,
        gyroX: const [],
        gyroY: const [],
        gyroZ: const [],
        accelX: const [],
        accelY: const [],
        accelZ: const [],
      );
      await tester.pumpWidget(MaterialApp(
        home: SessionDetailScreen(session: emptySession()),
      ));
      await tester.pump();

      expect(find.text('NO SHOTS IN SESSION'), findsOneWidget);
      expect(find.byKey(const ValueKey('shot-chip-0')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('session swap via didUpdateWidget resets selection and trace',
        (tester) async {
      final first = _session();
      final second = _session();
      await tester.pumpWidget(MaterialApp(
        home: SessionDetailScreen(session: first),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('shot-chip-0')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('target-score'))).data,
        '80',
      );
      await tester.tap(find.text('ANALYSIS'));
      await tester.pump();

      await tester.pumpWidget(MaterialApp(
        home: SessionDetailScreen(session: second),
      ));
      await tester.pump();

      // Selection resets to the new session's last shot (score 92).
      await tester.tap(find.text('TARGET'));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('target-score'))).data,
        '92',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
