import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/models/profile.dart';
import 'package:ssa_app/models/train_preset.dart';
import 'package:ssa_app/providers/sensor_data_provider.dart';
import 'package:ssa_app/providers/train_session_provider.dart';
import 'package:ssa_app/screens/train_screen.dart';
import 'package:ssa_app/widgets/shot_replay_controls.dart';
import 'package:ssa_app/widgets/shot_replay_panel.dart';
import 'package:ssa_app/widgets/target_replay_view.dart';
import 'package:ssa_app/widgets/train_target_widget.dart';

class _MockSensorDataProvider extends Mock implements SensorDataProvider {}

ShotResult _shot(
  int timestamp,
  double score, {
  TrainingMode mode = TrainingMode.dryFire,
}) => ShotResult(
  timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
  totalScore: score,
  holdScore: score,
  pressScore: score,
  recoilScore: score,
  elevationScore: score,
  windageScore: score,
  travelDistance: 0.1,
  peakJerk: 1,
  firearmType: FirearmType.pistol,
  trainingMode: mode,
  holdX: const [0.0, 0.001],
  holdY: const [0.0, 0.001],
  pressX: const [0.001, 0.002],
  pressY: const [0.001, 0.002],
  recoilX: const [0.002, 0.003],
  recoilY: const [0.002, 0.003],
);

Widget _app(TrainSessionProvider train, _MockSensorDataProvider sensor) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TrainSessionProvider>.value(value: train),
        ChangeNotifierProvider<SensorDataProvider>.value(value: sensor),
      ],
      child: const MaterialApp(home: TrainScreen()),
    );

void main() {
  late TrainSessionProvider train;
  late _MockSensorDataProvider sensor;

  setUp(() {
    train = TrainSessionProvider();
    sensor = _MockSensorDataProvider();
    when(() => sensor.addListener(any())).thenReturn(null);
    when(() => sensor.removeListener(any())).thenReturn(null);
    when(() => sensor.latestShot).thenReturn(null);
    when(() => sensor.isRecording).thenReturn(false);
    when(() => sensor.batteryLevel).thenReturn(100);
    when(() => sensor.startRecording()).thenReturn(null);
    when(() => sensor.stopRecording()).thenReturn(null);
    when(
      () => sensor.saveCurrentSession(
        shots: any(named: 'shots'),
        profileName: any(named: 'profileName'),
        trainingPreset: any(named: 'trainingPreset'),
        seriesCount: any(named: 'seriesCount'),
        firearmType: any(named: 'firearmType'),
        trainingMode: any(named: 'trainingMode'),
      ),
    ).thenAnswer((_) async {});
  });

  testWidgets('series review shows only OK and confirm returns to START', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    train.selectPreset(preset: TrainPreset.all.first, profile: Profile('Test'));
    train.startSeries();
    train.onShotDetected(_shot(1, 80));
    train.endSeries();

    await tester.pumpWidget(_app(train, sensor));
    await tester.pumpAndSettle();

    expect(find.text('SERIES REVIEW'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.byType(ShotReplayControls), findsOneWidget);
    expect(find.byType(TargetReplayView), findsNothing);
    final idleTarget = tester.widget<TrainTargetWidget>(
      find.byType(TrainTargetWidget),
    );
    expect(idleTarget.display, TrainTargetDisplay.seriesScatter);
    expect(idleTarget.replayProgress, 1.0);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump(const Duration(milliseconds: 500));
    final playingTarget = tester.widget<TrainTargetWidget>(
      find.byType(TrainTargetWidget),
    );
    expect(playingTarget.replayProgress, lessThan(1.0));
    expect(playingTarget.display, TrainTargetDisplay.activeTrace);
    expect(find.text('END SERIES'), findsNothing);
    expect(find.text('END SESSION'), findsNothing);
    expect(find.text('START'), findsNothing);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(train.state, TrainSessionState.readySeries);
    expect(find.text('START'), findsOneWidget);
  });

  testWidgets(
    'active target uses the selected shot and replay remains visible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      train.selectPreset(
        preset: TrainPreset.all.first,
        profile: Profile('Test'),
      );
      train.startSeries();
      final first = _shot(1, 80);
      final selected = _shot(2, 90);
      train.onShotDetected(first);
      train.onShotDetected(selected);
      train.selectShot(0);

      await tester.pumpWidget(_app(train, sensor));
      await tester.pumpAndSettle();

      final target = tester.widget<TrainTargetWidget>(
        find.byType(TrainTargetWidget),
      );
      expect(target.display, TrainTargetDisplay.activeTrace);
      expect(target.selectedShot, same(first));
      expect(find.text('END SERIES'), findsOneWidget);
      expect(find.text('SHOT LOG / REPLAY'), findsOneWidget);
      expect(find.byType(TargetReplayView), findsNothing);
      expect(find.byType(ShotReplayControls), findsOneWidget);
    },
  );

  testWidgets('active target with shots fits a 320x568 viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    train.selectPreset(preset: TrainPreset.all.first, profile: Profile('Test'));
    train.startSeries();
    train.onShotDetected(_shot(1, 80));

    await tester.pumpWidget(_app(train, sensor));
    await tester.pumpAndSettle();

    expect(find.text('END SERIES'), findsOneWidget);
    expect(find.text('SHOT LOG / REPLAY'), findsOneWidget);
    expect(find.byType(ShotReplayPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active layout with multiple shots fits a 320x568 viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    train.selectPreset(preset: TrainPreset.all.first, profile: Profile('Test'));
    train.startSeries();
    train.onShotDetected(_shot(1, 80));
    train.onShotDetected(_shot(2, 90));

    await tester.pumpWidget(_app(train, sensor));
    await tester.pumpAndSettle();

    expect(find.text('END SERIES'), findsOneWidget);
    expect(find.text('SHOT LOG / REPLAY'), findsOneWidget);
    expect(find.byType(ShotReplayPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session review chip tap updates selected shot and replay', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    train.selectPreset(preset: TrainPreset.all.first, profile: Profile('Test'));
    train.startSeries();
    final first = _shot(1, 80);
    train.onShotDetected(first);
    train.onShotDetected(_shot(2, 90));
    train.endSession();

    await tester.pumpWidget(_app(train, sensor));
    await tester.pumpAndSettle();

    expect(find.text('SESSION REVIEW'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('END SERIES'), findsNothing);
    expect(find.text('END SESSION'), findsNothing);
    expect(find.text('SHOT 2  90'), findsOneWidget);
    expect(find.byType(ShotReplayPanel), findsOneWidget);

    final target = tester.widget<TrainTargetWidget>(
      find.byType(TrainTargetWidget),
    );
    expect(target.selectedShot, isNot(same(first)));

    await tester.tap(find.text('SHOT 1  80'));
    await tester.pumpAndSettle();

    expect(train.selectedShotIndex, 0);
    final updated = tester.widget<TrainTargetWidget>(
      find.byType(TrainTargetWidget),
    );
    expect(updated.selectedShot, same(first));
  });

  testWidgets('shot log chip tap updates the target selected shot', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    train.selectPreset(preset: TrainPreset.all.first, profile: Profile('Test'));
    train.startSeries();
    final first = _shot(1, 80);
    final second = _shot(2, 90);
    train.onShotDetected(first);
    train.onShotDetected(second);

    await tester.pumpWidget(_app(train, sensor));
    await tester.pumpAndSettle();

    final target = tester.widget<TrainTargetWidget>(
      find.byType(TrainTargetWidget),
    );
    expect(target.selectedShot, same(second));

    await tester.tap(find.text('SHOT 1  80'));
    await tester.pumpAndSettle();

    final updated = tester.widget<TrainTargetWidget>(
      find.byType(TrainTargetWidget),
    );
    expect(updated.selectedShot, same(first));
    expect(train.selectedShotIndex, 0);
  });

  testWidgets('END SERIES disables further taps while the save is pending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final saveGate = Completer<void>();
    when(
      () => sensor.saveCurrentSession(
        shots: any(named: 'shots'),
        profileName: any(named: 'profileName'),
        trainingPreset: any(named: 'trainingPreset'),
        seriesCount: any(named: 'seriesCount'),
        firearmType: any(named: 'firearmType'),
        trainingMode: any(named: 'trainingMode'),
      ),
    ).thenAnswer((_) => saveGate.future);

    train.selectPreset(preset: TrainPreset.all.first, profile: Profile('Test'));
    train.startSeries();
    train.onShotDetected(_shot(1, 80));

    await tester.pumpWidget(_app(train, sensor));
    await tester.pumpAndSettle();

    await tester.tap(find.text('END SERIES'));
    await tester.pump();

    // Save pending: controls hidden, state still active.
    expect(find.text('END SERIES'), findsNothing);
    expect(find.text('END SESSION'), findsNothing);
    expect(train.state, TrainSessionState.activeSeries);

    saveGate.complete();
    await tester.pumpAndSettle();

    expect(train.state, TrainSessionState.reviewSeries);
    verify(
      () => sensor.saveCurrentSession(
        shots: any(named: 'shots'),
        profileName: any(named: 'profileName'),
        trainingPreset: any(named: 'trainingPreset'),
        seriesCount: any(named: 'seriesCount'),
        firearmType: any(named: 'firearmType'),
        trainingMode: any(named: 'trainingMode'),
      ),
    ).called(1);
  });

  testWidgets(
    'active dry session shows a full-bleed light band behind the target',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      train.selectPreset(
        preset: TrainPreset.all.first,
        profile: Profile('Test'),
      );
      train.startSeries();

      await tester.pumpWidget(_app(train, sensor));
      await tester.pumpAndSettle();

      final target = tester.widget<TrainTargetWidget>(
        find.byType(TrainTargetWidget),
      );
      expect(target.display, TrainTargetDisplay.activeTrace);

      final band = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.byType(TrainTargetWidget),
              matching: find.byType(Container),
            ),
          )
          .firstWhere(
            (c) => c.color == const Color(0xFFF3F4F2),
            orElse: () => Container(),
          );
      expect(band.color, const Color(0xFFF3F4F2));

      final targetSize = tester.getSize(find.byType(TrainTargetWidget));
      expect(targetSize, const Size.square(300));

      final bandSize = tester.getSize(
        find.ancestor(
          of: find.byType(TrainTargetWidget),
          matching: find.byWidget(band),
        ),
      );
      expect(bandSize.width, 390);
    },
  );

  testWidgets('live session band uses the light background color', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    train.selectPreset(preset: TrainPreset.all[1], profile: Profile('Test'));
    train.startSeries();

    await tester.pumpWidget(_app(train, sensor));
    await tester.pumpAndSettle();

    final band = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.byType(TrainTargetWidget),
            matching: find.byType(Container),
          ),
        )
        .firstWhere(
          (c) => c.color == const Color(0xFFF3F4F2),
          orElse: () => Container(),
        );
    expect(band.color, const Color(0xFFF3F4F2));
  });

  testWidgets('TRAIN-0 START remains boxless', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    train.selectPreset(preset: TrainPreset.all.first, profile: Profile('Test'));

    await tester.pumpWidget(_app(train, sensor));
    await tester.pumpAndSettle();

    expect(find.text('START'), findsOneWidget);
    final target = tester.widget<TrainTargetWidget>(
      find.byType(TrainTargetWidget),
    );
    expect(target.display, TrainTargetDisplay.start);

    final band = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.byType(TrainTargetWidget),
            matching: find.byType(Container),
          ),
        )
        .firstWhere(
          (c) => c.color == const Color(0xFFF3F4F2),
          orElse: () => Container(),
        );
    expect(band.color, isNull);
  });

  testWidgets(
    'session review keeps the unified light band for live shots after preset is cleared',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Live shot snapshot after END SESSION: review still shows the full-bleed
      // light band once the preset is cleared.
      train.selectPreset(
        preset: TrainPreset.all.first,
        profile: Profile('Test'),
      );
      train.startSeries();
      train.onShotDetected(_shot(1, 80, mode: TrainingMode.liveFire));
      train.endSession();

      await tester.pumpWidget(_app(train, sensor));
      await tester.pumpAndSettle();

      expect(find.text('SESSION REVIEW'), findsOneWidget);
      expect(train.selectedPreset, isNull);

      final band = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.byType(TrainTargetWidget),
              matching: find.byType(Container),
            ),
          )
          .firstWhere(
            (c) => c.color == const Color(0xFFF3F4F2),
            orElse: () => Container(),
          );
      expect(band.color, const Color(0xFFF3F4F2));

      final bandSize = tester.getSize(
        find.ancestor(
          of: find.byType(TrainTargetWidget),
          matching: find.byWidget(band),
        ),
      );
      expect(bandSize.width, 390);
    },
  );

  testWidgets(
    'session review keeps the unified light band for dry shots after preset is cleared',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Dry shot snapshot after END SESSION: review still shows the full-bleed
      // light band once the preset is cleared.
      train.selectPreset(preset: TrainPreset.all[1], profile: Profile('Test'));
      train.startSeries();
      train.onShotDetected(_shot(1, 80, mode: TrainingMode.dryFire));
      train.endSession();

      await tester.pumpWidget(_app(train, sensor));
      await tester.pumpAndSettle();

      expect(find.text('SESSION REVIEW'), findsOneWidget);
      expect(train.selectedPreset, isNull);

      final band = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.byType(TrainTargetWidget),
              matching: find.byType(Container),
            ),
          )
          .firstWhere(
            (c) => c.color == const Color(0xFFF3F4F2),
            orElse: () => Container(),
          );
      expect(band.color, const Color(0xFFF3F4F2));

      final bandSize = tester.getSize(
        find.ancestor(
          of: find.byType(TrainTargetWidget),
          matching: find.byWidget(band),
        ),
      );
      expect(bandSize.width, 390);
    },
  );
}
