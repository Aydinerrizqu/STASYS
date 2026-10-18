import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/widgets/target_replay_view.dart';

ShotResult _shot({bool withTrace = true}) {
  return ShotResult(
    timestamp: DateTime(2026, 1, 1),
    totalScore: 80,
    holdScore: 82,
    pressScore: 78,
    recoilScore: 80,
    elevationScore: 81,
    windageScore: 79,
    travelDistance: 0.01,
    peakJerk: 1.2,
    firearmType: FirearmType.pistol,
    trainingMode: TrainingMode.dryFire,
    holdX: withTrace ? [0, 0.001] : null,
    holdY: withTrace ? [0, 0.001] : null,
    pressX: withTrace ? [0.001, 0.002] : null,
    pressY: withTrace ? [0.001, 0.002] : null,
    recoilX: withTrace ? [0.002, 0.003] : null,
    recoilY: withTrace ? [0.002, 0.003] : null,
  );
}

void main() {
  group('TargetReplayMath.pointIndexForProgress', () {
    test('returns zero for zero or one point', () {
      expect(TargetReplayMath.pointIndexForProgress(0, 0.5), 0);
      expect(TargetReplayMath.pointIndexForProgress(1, 0.5), 0);
    });

    test('clamps progress below zero and above one', () {
      expect(TargetReplayMath.pointIndexForProgress(10, -0.5), 0);
      expect(TargetReplayMath.pointIndexForProgress(10, 1.5), 9);
    });

    test('maps midpoint to the nearest point', () {
      expect(TargetReplayMath.pointIndexForProgress(11, 0.5), 5);
    });

    test('preserves in-range progress mapping', () {
      expect(TargetReplayMath.pointIndexForProgress(5, 0.25), 1);
      expect(TargetReplayMath.pointIndexForProgress(5, 0.75), 3);
    });
  });

  group('TargetReplayMath.clampProgress', () {
    test('clamps underflow and overflow while preserving in-range values', () {
      expect(TargetReplayMath.clampProgress(-0.25), 0.0);
      expect(TargetReplayMath.clampProgress(0.35), 0.35);
      expect(TargetReplayMath.clampProgress(1.25), 1.0);
    });
  });

  group('TargetReplayView', () {
    testWidgets('renders partial trace when hold phase is absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TargetReplayView(
            shot: ShotResult(
              timestamp: DateTime(2026, 1, 1),
              totalScore: 80,
              holdScore: 82,
              pressScore: 78,
              recoilScore: 80,
              elevationScore: 81,
              windageScore: 79,
              travelDistance: 0.01,
              peakJerk: 1.2,
              firearmType: FirearmType.pistol,
              trainingMode: TrainingMode.dryFire,
              holdX: <double>[],
              holdY: <double>[],
              pressX: [0.001, 0.002],
              pressY: [0.001, 0.002],
              recoilX: [0.002, 0.003],
              recoilY: [0.002, 0.003],
            ),
            shotIndex: 0,
            getScoreColor: (_) => Colors.orange,
          ),
        ),
      );

      await tester.pump();
      expect(find.text('SHOT 1'), findsOneWidget);
    });

    testWidgets('compact replay fits the train viewport without overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 390,
            child: TargetReplayView(
              compact: true,
              shot: _shot(),
              shotIndex: 0,
              getScoreColor: (_) => Colors.orange,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('SHOT 1'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('shows shot summary and playback controls', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TargetReplayView(
            shot: _shot(),
            shotIndex: 0,
            getScoreColor: (_) => Colors.orange,
          ),
        ),
      );

      expect(find.text('SHOT 1'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byTooltip('Reset'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets(
      'starts stopped at the end, then reset and play restart from start',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TargetReplayView(
              shot: _shot(),
              shotIndex: 0,
              getScoreColor: (_) => Colors.orange,
            ),
          ),
        );

        expect(tester.widget<Slider>(find.byType(Slider)).value, 1.0);
        expect(find.byTooltip('Play'), findsOneWidget);

        await tester.tap(find.byTooltip('Reset'));
        await tester.pump();
        expect(tester.widget<Slider>(find.byType(Slider)).value, 0.0);

        await tester.tap(find.byTooltip('Play'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byTooltip('Pause'), findsOneWidget);
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
          greaterThan(0),
        );
      },
    );

    testWidgets('play returns to play after replay completes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TargetReplayView(
            shot: _shot(),
            shotIndex: 0,
            getScoreColor: (_) => Colors.orange,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.byTooltip('Play'), findsOneWidget);
    });
    testWidgets('pause preserves slider progress', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TargetReplayView(
            shot: _shot(),
            shotIndex: 0,
            getScoreColor: (_) => Colors.orange,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Play'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      final pausedValue = tester.widget<Slider>(find.byType(Slider)).value;
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<Slider>(find.byType(Slider)).value, pausedValue);
    });

    testWidgets('reset returns slider to zero', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TargetReplayView(
            shot: _shot(),
            shotIndex: 0,
            getScoreColor: (_) => Colors.orange,
          ),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(0.6);
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.6);
      await tester.tap(find.byTooltip('Reset'));
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.0);
    });

    testWidgets('seek clamps slider values and updates elapsed time', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TargetReplayView(
            shot: _shot(),
            shotIndex: 0,
            getScoreColor: (_) => Colors.orange,
          ),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(-1);
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.0);
      expect(find.text('0.0s'), findsOneWidget);
      slider.onChanged!(1.5);
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 1.0);
      expect(find.text('2.5s'), findsOneWidget);
    });

    testWidgets('seek while playing keeps playback running', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TargetReplayView(
            shot: _shot(),
            shotIndex: 0,
            getScoreColor: (_) => Colors.orange,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Play'));
      await tester.pump(const Duration(milliseconds: 300));
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.2);
      await tester.pump();
      expect(find.byTooltip('Pause'), findsOneWidget);
      final value = tester.widget<Slider>(find.byType(Slider)).value;
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        greaterThan(value),
      );
    });
    testWidgets('shows fallback text while retaining target canvas', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TargetReplayView(
            shot: _shot(withTrace: false),
            shotIndex: 0,
            getScoreColor: (_) => Colors.orange,
          ),
        ),
      );

      expect(find.text('NO TRACE DATA FOR THIS SHOT'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      final play = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Play'),
          matching: find.byType(IconButton),
        ),
      );
      expect(play.onPressed, isNull);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
    });
  });
}
