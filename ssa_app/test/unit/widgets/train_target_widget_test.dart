import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/models/train_preset.dart';
import 'package:ssa_app/widgets/shot_trace_geometry.dart';
import 'package:ssa_app/widgets/train_target_widget.dart';

ShotResult _shot({
  required int timestamp,
  double score = 80,
  bool withTrace = true,
}) => ShotResult(
  timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
  totalScore: score,
  holdScore: score,
  pressScore: score,
  recoilScore: score,
  elevationScore: score,
  windageScore: score,
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

final _preset = TrainPreset.all.first;

void main() {
  group('TrainTargetWidget', () {
    testWidgets('start mode shows the circular START control', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainTargetWidget(
              isActive: false,
              display: TrainTargetDisplay.start,
              preset: _preset,
            ),
          ),
        ),
      );

      expect(find.text('START'), findsOneWidget);
      expect(find.byIcon(Icons.gps_fixed), findsOneWidget);
    });

    testWidgets('start control renders without surrounding square box', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainTargetWidget(
              isActive: false,
              display: TrainTargetDisplay.start,
              preset: _preset,
            ),
          ),
        ),
      );

      expect(find.text('START'), findsOneWidget);
      expect(find.byIcon(Icons.gps_fixed), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('active trace paints one selected shot without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainTargetWidget(
              isActive: true,
              display: TrainTargetDisplay.activeTrace,
              selectedShot: _shot(timestamp: 1),
              // Extra session shots must not create additional traces.
              sessionShots: [_shot(timestamp: 2), _shot(timestamp: 3)],
              preset: _preset,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('START'), findsNothing);
    });

    testWidgets('series scatter paints a marker for every shot', (
      tester,
    ) async {
      final shots = [
        _shot(timestamp: 1),
        _shot(timestamp: 2, score: 65),
        _shot(timestamp: 3, score: 92),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainTargetWidget(
              isActive: false,
              display: TrainTargetDisplay.seriesScatter,
              scatterShots: shots,
              preset: _preset,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        TrainTargetWidget.markerPositions(shots, const Size(200, 200)),
        hasLength(shots.length),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('START'), findsNothing);
    });

    testWidgets(
      'activeTrace and seriesScatter paint at 300px without exception',
      (tester) async {
        final shot = _shot(timestamp: 9);
        await tester.binding.setSurfaceSize(const Size(400, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final display in [
          TrainTargetDisplay.activeTrace,
          TrainTargetDisplay.seriesScatter,
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox.square(
                    dimension: 300,
                    child: TrainTargetWidget(
                      isActive: true,
                      display: display,
                      selectedShot: shot,
                      scatterShots: [shot],
                      preset: _preset,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('activeTrace and seriesScatter dispatch independently', (
      tester,
    ) async {
      final shot = _shot(timestamp: 10);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainTargetWidget(
              isActive: true,
              display: TrainTargetDisplay.activeTrace,
              selectedShot: shot,
              preset: _preset,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('START'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainTargetWidget(
              isActive: true,
              display: TrainTargetDisplay.seriesScatter,
              scatterShots: [shot],
              preset: _preset,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('START'), findsNothing);
      expect(
        TrainTargetWidget.markerPositions([shot], const Size(200, 200)),
        hasLength(1),
      );
    });

    testWidgets('activeTrace with missing trace draws only target', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainTargetWidget(
              isActive: true,
              display: TrainTargetDisplay.activeTrace,
              selectedShot: _shot(timestamp: 1, withTrace: false),
              preset: _preset,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    test('marker position equals the trace endpoint used by live drawing', () {
      final shot = _shot(timestamp: 42, score: 60);
      const size = Size(300, 300);
      final trace = ShotTraceGeometry.fromShot(shot);

      // Same scaling as the painter: trace max deviation, centered canvas.
      final scaleX = size.width / 2 / trace.maxDeviation;
      final scaleY = size.height / 2 / trace.maxDeviation;
      final expected = Offset(
        size.width / 2 + trace.points.last.x * scaleX,
        size.height / 2 + trace.points.last.y * scaleY,
      );

      final marker = TrainTargetWidget.markerPositions([shot], size).single;
      expect(marker.dx, moreOrLessEquals(expected.dx, epsilon: 0.001));
      expect(marker.dy, moreOrLessEquals(expected.dy, epsilon: 0.001));
    });

    testWidgets('active trace is fully drawn at replayProgress 1.0', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainTargetWidget(
              isActive: true,
              display: TrainTargetDisplay.activeTrace,
              selectedShot: _shot(timestamp: 1),
              preset: _preset,
              replayProgress: 1.0,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // END SESSION clears the provider preset; the screen resolves the training
    // mode from the review shot snapshot and passes it explicitly. Verify the
    // target paints the dry ring treatment in that scenario (preset == null).
    testWidgets(
      'explicit dry trainingMode paints dry treatment without preset',
      (tester) async {
        final shot = _shot(timestamp: 7);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrainTargetWidget(
                isActive: false,
                display: TrainTargetDisplay.seriesScatter,
                scatterShots: [shot],
                preset: null,
                trainingMode: TrainingMode.dryFire,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('START'), findsNothing);
      },
    );

    testWidgets(
      'explicit live trainingMode paints live treatment without preset',
      (tester) async {
        final shot = _shot(timestamp: 8);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrainTargetWidget(
                isActive: false,
                display: TrainTargetDisplay.seriesScatter,
                scatterShots: [shot],
                preset: null,
                trainingMode: TrainingMode.liveFire,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('START'), findsNothing);
      },
    );

    testWidgets('active trace paints without exception at partial progress', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainTargetWidget(
              isActive: true,
              display: TrainTargetDisplay.activeTrace,
              selectedShot: _shot(timestamp: 1),
              preset: _preset,
              replayProgress: 0.4,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
