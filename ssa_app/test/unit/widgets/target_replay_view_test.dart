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
    testWidgets('shows shot summary and playback controls', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: TargetReplayView(
          shot: _shot(),
          shotIndex: 0,
          getScoreColor: (_) => Colors.orange,
        ),
      ));

      expect(find.text('SHOT 1'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byTooltip('Reset'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('shows fallback and disables controls without trace',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: TargetReplayView(
          shot: _shot(withTrace: false),
          shotIndex: 0,
          getScoreColor: (_) => Colors.orange,
        ),
      ));

      expect(find.text('NO TRACE DATA FOR THIS SHOT'), findsOneWidget);
      final play = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('Play'),
        matching: find.byType(IconButton),
      ));
      expect(play.onPressed, isNull);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
    });
  });
}
