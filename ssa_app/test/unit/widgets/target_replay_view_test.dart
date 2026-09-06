import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/widgets/target_replay_view.dart';

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
}
