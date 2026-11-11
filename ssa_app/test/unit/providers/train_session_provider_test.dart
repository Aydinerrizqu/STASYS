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
      expect(provider.trainingSessionId, startsWith('SESSION_'));
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

    test('returnToChoices clears a ready selection and returns to choices', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);

      provider.returnToChoices();

      expect(provider.state, TrainSessionState.choices);
      expect(provider.selectedPreset, isNull);
      expect(provider.activeProfile, isNull);
      expect(provider.seriesCount, 0);
      expect(provider.trainingSessionId, isNull);
      expect(provider.currentSeriesShots, isEmpty);
      expect(provider.allSeriesShots, isEmpty);
    });

    test('returnToChoices does not interrupt an active series', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();

      provider.returnToChoices();

      expect(provider.state, TrainSessionState.activeSeries);
      expect(provider.selectedPreset, testPreset);
    });

    test('TRAIN-0 start enters TRAIN-1 with an empty series', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);

      expect(provider.state, TrainSessionState.readySeries);
      provider.startSeries();

      expect(provider.state, TrainSessionState.activeSeries);
      expect(provider.currentSeriesShots, isEmpty);
      expect(provider.seriesCount, 1);
    });

    test('startSeries is no-op when not in readySeries state', () {
      provider.startSeries(); // in choices — should be no-op
      expect(provider.state, TrainSessionState.choices);
    });

    test('END SERIES enters series review while retaining session selection',
        () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 85.0));

      provider.endSeries();

      expect(provider.state, TrainSessionState.reviewSeries);
      expect(provider.selectedPreset, testPreset);
      expect(provider.activeProfile, testProfile);
      expect(provider.seriesCount, 1);
      expect(provider.currentSeriesShots, isEmpty);
      expect(provider.allSeriesShots, hasLength(1));
    });

    test('endSeries increments series count on next startSeries', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries(); // series 1
      provider.endSeries();
      provider.confirmReview();
      provider.startSeries(); // series 2
      expect(provider.seriesCount, 2);
    });

    test('endSeries is no-op when not in activeSeries state', () {
      provider.endSeries(); // in choices — should be no-op
      expect(provider.state, TrainSessionState.choices);
    });

    test('endSession without active shots resets directly to choices', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.endSeries();
      final completed = provider.endSession();
      expect(completed, isEmpty);
      expect(provider.lastSeriesShots, isEmpty);
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

    test('each shot trigger adds one shot and selects the latest shot', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      final firstShot = _makeShot(totalScore: 70.0);
      final latestShot = _makeShot(totalScore: 85.0);

      provider.onShotDetected(firstShot);
      expect(provider.currentSeriesShots, [firstShot]);
      expect(provider.selectedShotIndex, 0);

      provider.onShotDetected(latestShot);

      expect(provider.currentSeriesShots, [firstShot, latestShot]);
      expect(provider.currentSeriesShots, hasLength(2));
      expect(provider.selectedShotIndex, 1);
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
      provider.confirmReview();

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

    test('selectShot updates the selected review shot in series and session review', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      final first = _makeShot(totalScore: 80);
      final second = _makeShot(totalScore: 90);
      provider.onShotDetected(first);
      provider.onShotDetected(second);
      provider.endSeries();

      expect(provider.selectedShotIndex, 1);
      provider.selectShot(0);
      expect(provider.selectedShotIndex, 0);
      expect(provider.lastSeriesShots[provider.selectedShotIndex!], same(first));

      provider.confirmReview();
      provider.startSeries();
      final sessionFirst = _makeShot(totalScore: 80, seriesNumber: 2);
      final sessionSecond = _makeShot(totalScore: 90, seriesNumber: 2);
      provider.onShotDetected(sessionFirst);
      provider.onShotDetected(sessionSecond);
      provider.endSession();

      expect(provider.selectedShotIndex, 1);
      provider.selectShot(0);
      expect(provider.selectedShotIndex, 0);
      expect(provider.lastSeriesShots[provider.selectedShotIndex!], same(sessionFirst));
    });

    test('selectShot is no-op when outside a populated active or review state', () {
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
        TrainSessionState.reviewSeries,
        TrainSessionState.choices,
      ]);
    });
  });

  group('TrainSessionProvider series and session review', () {
    test('END SERIES snapshots only its shots and enters series review', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      final shotA = _makeShot(totalScore: 75);
      provider.onShotDetected(shotA);

      final completed = provider.endSeries();

      expect(completed, [shotA]);
      expect(provider.state, TrainSessionState.reviewSeries);
      expect(provider.lastSeriesShots, [shotA]);
      expect(provider.activeProfile, testProfile);
      expect(provider.selectedPreset, testPreset);
    });

    test('confirming series review clears scatter and returns to ready', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 75));
      provider.endSeries();

      provider.confirmReview();

      expect(provider.state, TrainSessionState.readySeries);
      expect(provider.lastSeriesShots, isEmpty);
      expect(provider.activeProfile, testProfile);
      expect(provider.selectedPreset, testPreset);
      expect(provider.seriesCount, 1);
    });

    test('later series replaces previous scatter snapshot', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      final first = _makeShot(totalScore: 70);
      provider.onShotDetected(first);
      provider.endSeries();
      provider.confirmReview();

      provider.startSeries();
      // The shot carries the number of the running series, so the provider
      // keeps it as it is (it only stamps shots whose number is wrong).
      final second = _makeShot(totalScore: 90, seriesNumber: 2);
      provider.onShotDetected(second);
      provider.endSeries();

      expect(provider.lastSeriesShots, [second]);
    });

    test('END SESSION with active shots enters session review then choices',
        () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      final shot = _makeShot(totalScore: 90);
      provider.onShotDetected(shot);

      final completed = provider.endSession();

      expect(completed, [shot]);
      expect(provider.state, TrainSessionState.reviewSession);
      expect(provider.lastSeriesShots, [shot]);
      expect(provider.selectedPreset, isNull);
      expect(provider.activeProfile, isNull);
      expect(provider.seriesCount, 0);
      expect(provider.currentSeriesShots, isEmpty);
      expect(provider.allSeriesShots, isEmpty);
      expect(provider.selectedShotIndex, 0);
      provider.confirmReview();
      expect(provider.state, TrainSessionState.choices);
      expect(provider.lastSeriesShots, isEmpty);
    });

    test('returnToChoices from series review clears snapshot and selection',
        () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 75));
      provider.endSeries();
      expect(provider.state, TrainSessionState.reviewSeries);

      provider.returnToChoices();

      expect(provider.state, TrainSessionState.choices);
      expect(provider.lastSeriesShots, isEmpty);
      expect(provider.selectedPreset, isNull);
      expect(provider.activeProfile, isNull);
      expect(provider.seriesCount, 0);
      expect(provider.allSeriesShots, isEmpty);
    });

    test('returnToChoices from session review clears snapshot', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 90));
      provider.endSession();
      expect(provider.state, TrainSessionState.reviewSession);

      provider.returnToChoices();

      expect(provider.state, TrainSessionState.choices);
      expect(provider.lastSeriesShots, isEmpty);
    });

    test('startSeries is no-op during series review', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 85));
      provider.endSeries();
      expect(provider.state, TrainSessionState.reviewSeries);

      provider.startSeries();

      expect(provider.state, TrainSessionState.reviewSeries);
      expect(provider.seriesCount, 1);
    });

    test('shots are not accepted during series review', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 85));
      provider.endSeries();
      expect(provider.state, TrainSessionState.reviewSeries);

      provider.onShotDetected(_makeShot(totalScore: 95));
      provider.selectShot(0);

      expect(provider.currentSeriesShots, isEmpty);
      expect(provider.lastSeriesShots, hasLength(1));
      // Selecting a review shot is allowed; only new shots are rejected.
      expect(provider.selectedShotIndex, 0);
    });

    test('confirmReview is no-op outside review states', () {
      provider.confirmReview(); // choices
      expect(provider.state, TrainSessionState.choices);

      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.confirmReview(); // readySeries
      expect(provider.state, TrainSessionState.readySeries);

      provider.startSeries();
      provider.confirmReview(); // activeSeries
      expect(provider.state, TrainSessionState.activeSeries);
    });
  });

  group('TrainSessionProvider session identity and series numbering', () {
    test('every series of one session shares the same session id', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      final sessionId = provider.trainingSessionId;

      provider.startSeries();
      provider.endSeries();
      provider.confirmReview();
      provider.startSeries();

      // Series 2 belongs to the same session as series 1.
      expect(provider.trainingSessionId, sessionId);
    });

    test('the next session gets a new session id', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      final firstSessionId = provider.trainingSessionId;

      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 90));
      provider.endSession();
      provider.confirmReview();

      provider.selectPreset(preset: testPreset, profile: testProfile);

      expect(provider.trainingSessionId, isNot(firstSessionId));
    });

    test('endSession clears the session identity', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);
      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 90));

      provider.endSession();

      expect(provider.trainingSessionId, isNull);
      expect(provider.sessionStartedAt, isNull);
    });

    test('onShotDetected stamps the running series number', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);

      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 80));
      expect(provider.currentSeriesShots.first.seriesNumber, 1);

      provider.endSeries();
      provider.confirmReview();

      provider.startSeries();
      provider.onShotDetected(_makeShot(totalScore: 85));
      expect(provider.currentSeriesShots.first.seriesNumber, 2);
    });

    test('currentSeriesNumber follows the running series', () {
      provider.selectPreset(preset: testPreset, profile: testProfile);

      provider.startSeries();
      expect(provider.currentSeriesNumber, 1);

      provider.endSeries();
      provider.confirmReview();

      provider.startSeries();
      expect(provider.currentSeriesNumber, 2);
    });

    test('sessionStartedAt is set when the preset is chosen', () {
      expect(provider.sessionStartedAt, isNull);

      provider.selectPreset(preset: testPreset, profile: testProfile);

      expect(provider.sessionStartedAt, isNotNull);
    });
  });
}

ShotResult _makeShot({required double totalScore, int seriesNumber = 1}) {
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
    seriesNumber: seriesNumber,
  );
}
