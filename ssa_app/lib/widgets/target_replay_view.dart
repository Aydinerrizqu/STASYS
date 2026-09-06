class TargetReplayMath {
  const TargetReplayMath._();

  static int pointIndexForProgress(int pointCount, double progress) {
    if (pointCount <= 1) return 0;
    final clamped = progress.clamp(0.0, 1.0);
    return (clamped * (pointCount - 1)).round();
  }

  static double clampProgress(double progress) =>
      progress.clamp(0.0, 1.0).toDouble();
}
