import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Playback controls for a selected shot's trace replay.
///
/// Rendered by the bottom shot log panel. The progress value drives the
/// main Train target canvas (owned by the parent), not a local graph.
class ShotReplayControls extends StatelessWidget {
  final double progress;
  final bool hasTrace;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final ValueChanged<double> onSeek;
  final VoidCallback onReset;

  const ShotReplayControls({
    super.key,
    this.progress = 1.0,
    this.hasTrace = true,
    this.isPlaying = false,
    required this.onPlay,
    required this.onPause,
    required this.onSeek,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: StsysTheme.cyanOf(context),
              size: 18,
            ),
            onPressed: hasTrace ? (isPlaying ? onPause : onPlay) : null,
            tooltip: isPlaying ? 'Pause' : 'Play',
          ),
          Expanded(
            child: Slider(
              value: progress.clamp(0.0, 1.0).toDouble(),
              activeColor: StsysTheme.cyanOf(context),
              onChanged: hasTrace ? onSeek : null,
            ),
          ),
          Text(
            '${(progress.clamp(0.0, 1.0) * 2.5).toStringAsFixed(1)}s',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.5),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.5),
              size: 16,
            ),
            onPressed: hasTrace ? onReset : null,
            tooltip: 'Reset',
          ),
        ],
      ),
    );
  }
}
