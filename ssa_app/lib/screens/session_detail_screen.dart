import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/session_logger.dart';
import '../providers/session_provider.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';
import '../widgets/shot_replay_controls.dart';
import '../widgets/shot_trace_geometry.dart';
import '../widgets/train_target_widget.dart';

class SessionDetailScreen extends StatefulWidget {
  final SessionLog session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen>
    with SingleTickerProviderStateMixin {
  ShotResult? _selectedShot;
  int? _selectedShotIndex;
  int? _selectedSeriesNumber;

  /// Drives the trace playback of the selected shot. Same behaviour as the
  /// Train screen: the value maps to the target's `replayProgress`.
  ///
  /// Created in [initState] rather than lazily: a lazy field would be
  /// initialised on first read, which for an empty session happens in
  /// [dispose] — creating a ticker on a deactivated element.
  late final AnimationController _replayController;

  @override
  void dispose() {
    _replayController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _replayController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2500),
          value: 1.0,
        )..addListener(() {
          if (mounted) setState(() {});
        });
    final numbers = _seriesNumbers;
    if (numbers.length <= 1) {
      _selectedSeriesNumber = null;
    } else {
      _selectedSeriesNumber = numbers.last;
    }
    final shots = _visibleShots;
    if (shots.isNotEmpty) {
      _selectedShot = shots.last;
      _selectedShotIndex = shots.length - 1;
    }
  }

  @override
  void didUpdateWidget(covariant SessionDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      final numbers = _seriesNumbers;
      _selectedSeriesNumber = numbers.length <= 1 ? null : numbers.last;
      final shots = _visibleShots;
      _selectedShot = shots.isEmpty ? null : shots.last;
      _selectedShotIndex = shots.isEmpty ? null : shots.length - 1;
      _replayController.value = 1.0;
    }
  }

  List<int> get _seriesNumbers => widget.session.seriesNumbers;

  List<ShotResult> get _visibleShots {
    final selected = _selectedSeriesNumber;
    if (selected == null) return widget.session.shots;
    return widget.session.shots
        .where((shot) => shot.seriesNumber == selected)
        .toList();
  }

  double _averageForShots(List<ShotResult> shots) {
    if (shots.isEmpty) return 0;
    return shots.map((s) => s.totalScore).reduce((a, b) => a + b) / shots.length;
  }

  void _selectSeries(int? seriesNumber) {
    final shots = seriesNumber == null
        ? widget.session.shots
        : widget.session.shots
            .where((s) => s.seriesNumber == seriesNumber)
            .toList();
    setState(() {
      _selectedSeriesNumber = seriesNumber;
      _selectedShot = shots.isEmpty ? null : shots.last;
      _selectedShotIndex = shots.isEmpty ? null : shots.length - 1;
    });
    _replayController.value = 1.0;
  }

  void _selectShot(ShotResult shot) {
    final shots = _visibleShots;
    final idx = shots.indexOf(shot);
    setState(() {
      _selectedShot = shot;
      _selectedShotIndex = idx;
    });
    // Selecting another shot resets the replay to the full trace.
    _replayController.value = 1.0;
  }

  void _playReplay() {
    if (_replayController.value >= 1.0) {
      _replayController.value = 0.0;
    }
    _replayController.forward();
  }

  void _pauseReplay() {
    _replayController.stop();
  }

  void _resetReplay() {
    _replayController.value = 1.0;
  }

  void _seekReplay(double v) {
    final wasAnimating = _replayController.isAnimating;
    _replayController.value = v.clamp(0.0, 1.0).toDouble();
    if (wasAnimating) {
      _replayController.forward();
    }
  }

  Widget _buildTargetBody() {
    if (_selectedShot == null || _selectedShotIndex == null) {
      return const SizedBox.shrink();
    }

    final shot = _selectedShot!;
    final traceAvailable = ShotTraceGeometry.fromShot(shot).points.isNotEmpty;
    return Column(
      children: [
        _TargetScoreRow(
          shotScore: shot.totalScore,
          averageScore: _averageForShots(_visibleShots),
          scoreColor: _getScoreColor(shot.totalScore),
        ),
        SizedBox(
          key: const ValueKey('session-target'),
          width: 320,
          height: 320,
          child: TrainTargetWidget(
            isActive: true,
            display: TrainTargetDisplay.activeTrace,
            selectedShot: shot,
            replayProgress: _replayController.value,
            trainingMode: shot.trainingMode,
          ),
        ),
        if (traceAvailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ShotReplayControls(
              progress: _replayController.value,
              isPlaying: _replayController.isAnimating,
              hasTrace: true,
              onPlay: _playReplay,
              onPause: _pauseReplay,
              onSeek: _seekReplay,
              onReset: _resetReplay,
            ),
          ),
      ],
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 95) return const Color(0xFFFFD700);
    if (score >= 85) return const Color(0xFF4CAF50);
    if (score >= 70) return const Color(0xFF2196F3);
    if (score >= 50) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    // The header follows the selected series: the shot count and the average
    // describe that series only.
    final visibleShots = _visibleShots;
    final avgScore = _averageForShots(visibleShots);

    return Scaffold(
      backgroundColor: StsysTheme.surfaceContainerLowestOf(context),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: StsysTheme.surfaceContainerLowOf(context),
                border: Border(
                  bottom: BorderSide(
                    color: StsysTheme.outlineVariantOf(
                      context,
                    ).withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: StsysTheme.surfaceContainerHighOf(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: StsysTheme.onSurfaceOf(
                          context,
                        ).withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat(
                            'EEEE, dd MMMM',
                          ).format(session.date).toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: StsysTheme.primaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${visibleShots.length} shots — ${avgScore.toStringAsFixed(1)} avg',
                          key: const ValueKey('session-detail-header-stats'),
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _getScoreColor(avgScore),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showDeleteDialog(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: StsysTheme.errorOf(
                          context,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: StsysTheme.errorOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Single scrollable page: target, shot data and analysis.
            // SingleChildScrollView (not ListView) so every section is built
            // eagerly — the analysis empty-state must be present without
            // scrolling to the bottom of the viewport first.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (visibleShots.isEmpty)
                      const SizedBox(
                        height: 240,
                        child: Center(
                          child: Text(
                            'NO SHOTS IN SESSION',
                            key: ValueKey('session-empty'),
                          ),
                        ),
                      )
                    else ...[
                      _buildTargetBody(),
                      if (_seriesNumbers.length > 1) _buildSeriesChipStrip(),
                      _buildShotChipStrip(visibleShots),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeriesChipStrip() {
    final seriesNumbers = _seriesNumbers;
    return Container(
      color: StsysTheme.surfaceContainerLowOf(context),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SERIES',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: StsysTheme.onSurfaceVariantOf(context),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: seriesNumbers.length,
              itemBuilder: (context, index) {
                final series = seriesNumbers[index];
                final isSelected = _selectedSeriesNumber == series;
                final seriesShots = widget.session.shots
                    .where((s) => s.seriesNumber == series)
                    .toList();
                final label = 'SERIES $series  (${seriesShots.length})';

                return GestureDetector(
                  key: ValueKey('series-chip-$series'),
                  onTap: () => _selectSeries(series),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? StsysTheme.primaryOf(context).withValues(alpha: 0.15)
                          : StsysTheme.scoreChipFillOf(context),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? StsysTheme.primaryOf(context)
                            : StsysTheme.outlineVariantOf(context)
                                .withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? StsysTheme.primaryOf(context)
                            : StsysTheme.onSurfaceOf(context),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShotChipStrip(List<ShotResult> shots) {
    return Container(
      color: StsysTheme.surfaceContainerLowOf(context),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SHOTS IN SESSION',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: StsysTheme.onSurfaceVariantOf(context),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: StsysTheme.primaryOf(context).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${shots.length}',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: StsysTheme.primaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: shots.length,
              itemBuilder: (context, index) {
                final shot = shots[index];
                final isSelected = shot == _selectedShot;
                final scoreColor = _getScoreColor(shot.totalScore);

                return GestureDetector(
                  key: ValueKey('shot-chip-$index'),
                  onTap: () => _selectShot(shot),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56,
                    height: 56,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? scoreColor.withValues(alpha: 0.15)
                          : StsysTheme.scoreChipFillOf(context),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? scoreColor
                            : StsysTheme.outlineVariantOf(
                                context,
                              ).withValues(alpha: 0.2),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        shot.totalScore.toInt().toString(),
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: isSelected
                              ? scoreColor
                              : StsysTheme.onSurfaceOf(context),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: Text(
          'DELETE SESSION?',
          style: StsysText.labelBold.copyWith(
            color: StsysTheme.errorOf(context),
          ),
        ),
        content: Text(
          'This action cannot be undone.',
          style: StsysText.bodyOf(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'BATAL',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                color: StsysTheme.onSurfaceVariantOf(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteSession();
            },
            child: Text(
              'HAPUS',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
                color: StsysTheme.errorOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Delete this session from storage and close the detail page.
  ///
  /// The [SessionProvider] is optional: the screen is also reachable from
  /// the Home tab, which owns its own provider instance.
  Future<void> _deleteSession() async {
    final provider = context.read<SessionProvider?>();
    await provider?.deleteSession(widget.session);
    if (mounted) Navigator.pop(context);
  }
}

class _TargetScoreRow extends StatelessWidget {
  final double shotScore;
  final double averageScore;
  final Color scoreColor;

  const _TargetScoreRow({
    required this.shotScore,
    required this.averageScore,
    required this.scoreColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: _scoreValue(
              context,
              'SCORE',
              shotScore,
              scoreColor,
              large: true,
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: StsysTheme.outlineVariantOf(context).withValues(alpha: 0.25),
          ),
          Expanded(
            child: _scoreValue(
              context,
              'MATCH TOTAL',
              averageScore,
              StsysTheme.onSurfaceOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreValue(
    BuildContext context,
    String label,
    double score,
    Color color, {
    bool large = false,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: StsysTheme.onSurfaceVariantOf(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          score.toStringAsFixed(large ? 0 : 1),
          key: large ? const ValueKey('target-score') : null,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: large ? 30 : 24,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}
