import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/widgets/shot_trace_geometry.dart';

ShotResult _shot(List<double> holdX) => ShotResult(
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
  holdX: holdX,
  holdY: List<double>.filled(holdX.length, 0),
  pressX: const [2, 3],
  pressY: const [0, 0],
  recoilX: const [4, 5],
  recoilY: const [0, 0],
);

void main() {
  test('each selected shot produces its own trace path', () {
    final first = ShotTraceGeometry.fromShot(_shot(const [0, 1]));
    final second = ShotTraceGeometry.fromShot(_shot(const [10, 11]));

    expect(first.points.first.x, 0);
    expect(second.points.first.x, 10);
    expect(first.points, isNot(equals(second.points)));
  });
}
