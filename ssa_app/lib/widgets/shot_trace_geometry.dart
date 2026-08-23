import '../models/data_models.dart';

/// Ordered trace points shared by the static post-shot chart and replay.
class ShotTracePoint {
  final double x;
  final double y;

  const ShotTracePoint(this.x, this.y);
}

enum ShotTracePhase { hold, press, recoil }

class ShotTracePath {
  final List<ShotTracePoint> points;
  final int holdEnd;
  final int pressEnd;

  const ShotTracePath({
    required this.points,
    required this.holdEnd,
    required this.pressEnd,
  });

  ShotTracePhase phaseForPoint(int index) {
    if (index <= holdEnd) return ShotTracePhase.hold;
    if (index <= pressEnd) return ShotTracePhase.press;
    return ShotTracePhase.recoil;
  }

  double get maxDeviation {
    var maxValue = 0.005;
    for (final point in points) {
      if (point.x.abs() > maxValue) maxValue = point.x.abs();
      if (point.y.abs() > maxValue) maxValue = point.y.abs();
    }
    return (maxValue * 1.3).clamp(0.01, double.infinity);
  }
}

class ShotTraceGeometry {
  const ShotTraceGeometry._();

  static ShotTracePath fromShot(ShotResult shot) {
    final points = <ShotTracePoint>[];
    final holdEnd = _append(points, shot.holdX, shot.holdY) - 1;
    final pressEnd = _append(points, shot.pressX, shot.pressY) - 1;
    _append(points, shot.recoilX, shot.recoilY);

    return ShotTracePath(points: points, holdEnd: holdEnd, pressEnd: pressEnd);
  }

  static int _append(
    List<ShotTracePoint> output,
    List<double>? x,
    List<double>? y,
  ) {
    if (x == null || y == null) return output.length;
    final count = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < count; i++) {
      output.add(ShotTracePoint(x[i], y[i]));
    }
    return output.length;
  }
}
