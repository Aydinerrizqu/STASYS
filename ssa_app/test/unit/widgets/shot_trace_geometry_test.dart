import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/widgets/shot_trace_geometry.dart';

void main() {
  test('creates one ordered path with phase boundaries', () {
    final shot = ShotResult(
      timestamp: DateTime(2026),
      totalScore: 80,
      holdScore: 80,
      pressScore: 80,
      recoilScore: 80,
      elevationScore: 80,
      windageScore: 80,
      travelDistance: 0,
      peakJerk: 0,
      firearmType: FirearmType.pistol,
      trainingMode: TrainingMode.dryFire,
      holdX: const [0, 1],
      holdY: const [0, 1],
      pressX: const [1, 2],
      pressY: const [1, 2],
      recoilX: const [2, 3],
      recoilY: const [2, 3],
    );

    final path = ShotTraceGeometry.fromShot(shot);

    expect(path.points.map((p) => p.x), [0, 1, 1, 2, 2, 3]);
    expect(path.phaseForPoint(0), ShotTracePhase.hold);
    expect(path.phaseForPoint(2), ShotTracePhase.press);
    expect(path.phaseForPoint(4), ShotTracePhase.recoil);
  });
}
