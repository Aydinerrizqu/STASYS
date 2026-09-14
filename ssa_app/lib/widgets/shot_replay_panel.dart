import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/train_session_provider.dart';
import '../widgets/target_replay_view.dart';

/// Slide-up panel shown in TRAIN-1 when a shot is selected.
/// Wraps the existing TargetReplayView for selected-shot replay.
class ShotReplayPanel extends StatelessWidget {
  const ShotReplayPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final trainProv = context.watch<TrainSessionProvider>();
    final shots = trainProv.currentSeriesShots;
    final selectedIdx = trainProv.selectedShotIndex;

    if (shots.isEmpty) return const SizedBox.shrink();

    final shot = shots[selectedIdx ?? shots.length - 1];
    final shotIndex = selectedIdx ?? shots.length - 1;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0C0E11),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: Color(0xFF1F242C))),
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
              color: const Color(0xFF1F242C),
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
          // Replay view
          TargetReplayView(
            shot: shot,
            shotIndex: shotIndex,
            getScoreColor: _scoreColor,
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
