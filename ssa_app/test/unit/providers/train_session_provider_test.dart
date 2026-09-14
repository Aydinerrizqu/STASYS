import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/train_preset.dart';
import 'package:ssa_app/models/profile.dart';
import 'package:ssa_app/providers/train_session_provider.dart';
import 'package:ssa_app/models/data_models.dart';

void main() {
  late TrainSessionProvider provider;
  late Profile testProfile;
  late TrainPreset testPreset;

  setUp(() {
    provider = TrainSessionProvider();
    testProfile = Profile('Test Shooter');
    testPreset = TrainPreset.all[0]; // dry-air-softgun-10
  });

  group('TrainSessionProvider state machine', () {
    test('initial state is choices', () {
      expect(provider.state, TrainSessionState.choices);
    });

    test('selectPreset transitions from choices to readySeries', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      expect(provider.state, TrainSessionState.readySeries);
      expect(provider.selectedPreset, testPreset);
      expect(provider.activeProfile, testProfile);
    });

    test('selectPreset is no-op when not in choices state', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      expect(provider.state, TrainSessionState.readySeries);

      final otherPreset = TrainPreset.all[1];
      provider.selectPreset(preset: otherPreset, profile: Profile('Other'));
      // Should stay on same preset — no transition from readySeries
      expect(provider.selectedPreset, testPreset);
      expect(provider.state, TrainSessionState.readySeries);
    });

    test('startSeries transitions from readySeries to activeSeries', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      expect(provider.state, TrainSessionState.activeSeries);
      expect(provider.seriesCount, 1);
      expect(provider.currentSeriesShots, isEmpty);
    });

    test('startSeries is no-op when not in readySeries state', () {
      provider.startSeries(); // in choices — should be no-op
      expect(provider.state, TrainSessionState.choices);
    });

    test('endSeries transitions from activeSeries back to readySeries', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.endSeries();
      expect(provider.state, TrainSessionState.readySeries);
    });

    test('endSeries increments series count on next startSeries', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries(); // series 1
      provider.endSeries();
      provider.startSeries(); // series 2
      expect(provider.seriesCount, 2);
    });

    test('endSeries is no-op when not in activeSeries state', () {
      provider.endSeries(); // in choices — should be no-op
      expect(provider.state, TrainSessionState.choices);
    });

    test('endSession transitions from readySeries to choices', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.endSeries();
      provider.endSession();
      expect(provider.state, TrainSessionState.choices);
      expect(provider.selectedPreset, isNull);
      expect(provider.activeProfile, isNull);
      expect(provider.seriesCount, 0);
    });

    test('endSession from activeSeries ends current series then resets', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      // endSession while active — should close series and reset
      provider.endSession();
      expect(provider.state, TrainSessionState.choices);
      expect(provider.seriesCount, 0);
    });

    test('endSession is no-op when in choices state', () {
      provider.endSession();
      expect(provider.state, TrainSessionState.choices);
    });

    test('onShotDetected adds shot to current series when active', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();

      final shot = _makeShot(totalScore: 85.0);
      provider.onShotDetected(shot);

      expect(provider.currentSeriesShots.length, 1);
      expect(provider.currentSeriesShots.first.totalScore, 85.0);
    });

    test('onShotDetected is no-op when not in activeSeries', () {
      final shot = _makeShot(totalScore: 85.0);
      provider.onShotDetected(shot);
      expect(provider.currentSeriesShots, isEmpty);
    });

    test('allSeriesShots accumulates across series', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);

      // Series 1
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 80.0));
      provider.onShotDetected(_makeShot(totalScore: 90.0));
      provider.endSeries();

      // Series 2
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 70.0));
      provider.endSeries();

      expect(provider.allSeriesShots.length, 3);
      expect(provider.seriesCount, 2);
    });

    test('selectShot sets selectedShotIndex', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 80.0));
      provider.onShotDetected(_makeShot(totalScore: 90.0));

      provider.selectShot(1);
      expect(provider.selectedShotIndex, 1);
    });

    test('selectShot clamps to valid range', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 80.0));

      provider.selectShot(-1);
      expect(provider.selectedShotIndex, 0);

      provider.selectShot(99);
      expect(provider.selectedShotIndex, 0);
    });

    test('selectShot is no-op when not in activeSeries', () {
      provider.selectShot(0);
      expect(provider.selectedShotIndex, isNull);
    });

    test('notifies listeners on state transitions', () {
      final notifications = <TrainSessionState>[];
      provider.addListener(() => notifications.add(provider.state));

      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.endSeries();
      provider.endSession();

      expect(notifications, [
        TrainSessionState.readySeries,
        TrainSessionState.activeSeries,
        TrainSessionState.readySeries,
        TrainSessionState.choices,
      ]);
    });
  });
}

ShotResult _makeShot({required double totalScore}) {
  return ShotResult(
    timestamp: DateTime.now(),
    totalScore: totalScore,
    holdScore: 80.0,
    pressScore: 75.0,
    recoilScore: 70.0,
    elevationScore: 85.0,
    windageScore: 80.0,
    travelDistance: 0.02,
    peakJerk: 5.0,
    firearmType: FirearmType.pistol,
    trainingMode: TrainingMode.dryFire,
  );
}
