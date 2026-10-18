import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/train_session_provider.dart';
import '../theme/app_theme.dart';
import 'shot_replay_controls.dart';

/// Bottom panel shown when shots exist in TRAIN-1 or review.
///
/// Contains the shot chips and playback controls. Playback progress is owned
/// by the parent (TrainScreen session view) and drives the main target canvas;
/// this panel intentionally has no graph of its own.
class ShotReplayPanel extends StatelessWidget {
  final double progress;
  final bool isPlaying;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onReset;

  const ShotReplayPanel({
    super.key,
    this.progress = 1.0,
    this.isPlaying = false,
    this.onPlay,
    this.onPause,
    this.onSeek,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final trainProv = context.watch<TrainSessionProvider>();
    // During review the active series is empty; the panel replays the
    // just-completed series snapshot instead.
    final isReview =
        trainProv.state == TrainSessionState.reviewSeries ||
        trainProv.state == TrainSessionState.reviewSession;
    final shots = isReview
        ? trainProv.lastSeriesShots
        : trainProv.currentSeriesShots;
    final selectedIdx = trainProv.selectedShotIndex;

    if (shots.isEmpty) return const SizedBox.shrink();

    final shot = shots[selectedIdx ?? shots.length - 1];
    final shotIndex = selectedIdx ?? shots.length - 1;
    final hasTrace =
        (shot.holdX?.isNotEmpty ?? false) ||
        (shot.pressX?.isNotEmpty ?? false) ||
        (shot.recoilX?.isNotEmpty ?? false);

    return Container(
      decoration: BoxDecoration(
        color: StsysTheme.mobileBackgroundOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: StsysTheme.mobileBorderOf(context))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: StsysTheme.mobileBorderOf(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Shot chips (horizontal scroll)
          if (shots.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: shots.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final s = shots[i];
                    final isSelected = i == shotIndex;
                    final color = _scoreColor(s.totalScore);
                    return GestureDetector(
                      onTap: () => trainProv.selectShot(i),
                      child: Container(
                        width: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.25)
                              : color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? color
                                : color.withValues(alpha: 0.3),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: color,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          // Selected shot score summary (compact form of the old replay card)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 0),
            child: Row(
              children: [
                Text(
                  'SHOT ${shotIndex + 1}',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: StsysTheme.onSurfaceOf(context),
                  ),
                ),
                const Spacer(),
                Text(
                  shot.totalScore.toInt().toString(),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _scoreColor(shot.totalScore),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'HOLD ${shot.holdScore.toInt()}'
                    ' · PRESS ${shot.pressScore.toInt()}'
                    ' · RECOIL ${shot.recoilScore.toInt()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: StsysTheme.onSurfaceOf(context).withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Playback controls (drive the main target canvas)
          ShotReplayControls(
            progress: progress,
            hasTrace: hasTrace,
            isPlaying: isPlaying,
            onPlay: onPlay ?? () {},
            onPause: onPause ?? () {},
            onSeek: onSeek ?? (_) {},
            onReset: onReset ?? () {},
          ),
        ],
      ),
    );
  }

  static Color _scoreColor(double score) {
    if (score >= 80) return const Color(0xFF39D98A);
    if (score >= 60) return const Color(0xFF00D8FF);
    return const Color(0xFFFF5252);
  }
}
