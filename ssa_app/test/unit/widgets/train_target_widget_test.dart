import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    // Rings 1-6 are painted straight onto the page background. The dark
    // shell used to hide them completely because the stroke was near-black.
    testWidgets('outer rings stay visible on the dark shell', (tester) async {
      const darkBackground = Color(0xFF0E0E0E);

      final ring = TrainTargetWidget.outerRingColorFor(Brightness.dark);
      final crosshair = TrainTargetWidget.crosshairColorFor(Brightness.dark);

      expect(
        ring.computeLuminance(),
        greaterThan(darkBackground.computeLuminance() + 0.2),
      );
      expect(
        crosshair.computeLuminance(),
        greaterThan(darkBackground.computeLuminance() + 0.2),
      );
    });

    testWidgets('outer rings stay visible on the light shell', (tester) async {
      const lightBackground = Color(0xFFFFFFFF);

      final ring = TrainTargetWidget.outerRingColorFor(Brightness.light);
      final crosshair = TrainTargetWidget.crosshairColorFor(Brightness.light);

      expect(
        ring.computeLuminance(),
        lessThan(lightBackground.computeLuminance() - 0.2),
      );
      expect(
        crosshair.computeLuminance(),
        lessThan(lightBackground.computeLuminance() - 0.2),
      );
    });

    testWidgets('target repaints when the theme brightness flips', (
      tester,
    ) async {
      Widget app(Brightness brightness) => MaterialApp(
        theme: brightness == Brightness.light
            ? ThemeData.light()
            : ThemeData.dark(),
        home: Scaffold(
          body: TrainTargetWidget(
            isActive: true,
            display: TrainTargetDisplay.activeTrace,
            selectedShot: _shot(timestamp: 1),
            preset: _preset,
          ),
        ),
      );

      await tester.pumpWidget(app(Brightness.light));
      await tester.pump();
      await tester.pumpWidget(app(Brightness.dark));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // Pixel-level check: rings 1-6 sit directly on the page background, so
    // the stroke has to contrast with it in both themes. The earlier
    // near-black stroke was invisible on the dark shell.
    group('outer ring contrast', () {
      /// Median luminance of the ring stroke sampled around the target.
      ///
      /// Every angle crosses a ring stroke, so the median ignores the ring
      /// labels and the crosshair dashes that cover only a few directions.
      Future<double> medianRingLuminance(
        WidgetTester tester, {
        required Brightness brightness,
        required Color background,
      }) async {
        const targetSize = 300.0;
        const pixelRatio = 3.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light
                ? ThemeData.light()
                : ThemeData.dark(),
            home: Scaffold(
              backgroundColor: background,
              body: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox.square(
                    dimension: targetSize,
                    child: TrainTargetWidget(
                      isActive: false,
                      // Empty scatter: paints the target rings only, so no
                      // trace or impact marker can pollute the samples.
                      display: TrainTargetDisplay.seriesScatter,
                      preset: _preset,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        // toImage and toByteData resolve on engine callbacks that never fire
        // inside the test binding's fake-async zone; runAsync lets them run.
        final capture = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: pixelRatio);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return (image, data);
        });
        expect(capture, isNotNull);
        final (image, rawData) = capture!;
        expect(rawData, isNotNull);
        final bytes = rawData!.buffer.asUint8List();

        final center = image.width / 2;
        final maxR = targetSize * 0.40 * pixelRatio;
        // Ring i is drawn at maxR * i / 10; the outer-coloured rings are
        // i = 5..10, so sample the band around i = 7 (0.7 * maxR).
        final bandCentre = maxR * 0.7;
        final samples = <double>[];

        for (var angle = 0; angle < 360; angle += 5) {
          final rad = angle * math.pi / 180;
          final dx = math.cos(rad);
          final dy = math.sin(rad);
          var best = -1.0;
          var bestLuminance = 0.0;
          for (
            var r = bandCentre - maxR * 0.06;
            r <= bandCentre + maxR * 0.06;
            r += 0.5
          ) {
            final x = (center + dx * r).round();
            final y = (center + dy * r).round();
            if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
              continue;
            }
            final offset = (y * image.width + x) * 4;
            final cr = bytes[offset];
            final cg = bytes[offset + 1];
            final cb = bytes[offset + 2];
            final distance =
                (cr - background.r).abs() +
                (cg - background.g).abs() +
                (cb - background.b).abs();
            if (distance > best) {
              best = distance;
              bestLuminance =
                  0.2126 * cr + 0.7152 * cg + 0.0722 * cb;
            }
          }
          if (best >= 0) samples.add(bestLuminance);
        }

        samples.sort();
        return samples[samples.length ~/ 2] / 255.0;
      }

      testWidgets('rings read as light strokes on the dark background', (
        tester,
      ) async {
        const darkBackground = Color(0xFF0E0E0E);
        final luminance = await medianRingLuminance(
          tester,
          brightness: Brightness.dark,
          background: darkBackground,
        );
        expect(
          luminance,
          greaterThan(0.3),
          reason: 'ring stroke must contrast with the dark background',
        );
      });

      testWidgets('rings read as dark strokes on the light background', (
        tester,
      ) async {
        const lightBackground = Color(0xFFFFFFFF);
        final luminance = await medianRingLuminance(
          tester,
          brightness: Brightness.light,
          background: lightBackground,
        );
        expect(
          luminance,
          lessThan(0.3),
          reason: 'ring stroke must contrast with the light background',
        );
      });
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
