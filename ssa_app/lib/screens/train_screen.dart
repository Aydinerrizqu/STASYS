import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/profile.dart';
import '../models/train_preset.dart';
import '../models/data_models.dart';
import '../providers/profile_provider.dart';
import '../providers/train_session_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/train_target_widget.dart';
import '../widgets/shot_replay_panel.dart';

class _StasysHeader extends StatelessWidget {
  final Widget? trailing;
  final bool showBattery;
  const _StasysHeader({this.trailing, this.showBattery = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: StsysTheme.mobileHeaderOf(context, StsysTheme.mobileHeaderTrain),
        border: Border(
          bottom: BorderSide(color: StsysTheme.mobileBorderOf(context)),
        ),
      ),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) =>
                StsysTheme.brandGradient.createShader(bounds),
            child: const Text(
              'STASYS',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
          const Spacer(),
          if (showBattery)
            Consumer<SensorDataProvider>(
              builder: (context, sensor, _) => Text(
                '${sensor.batteryLevel}%',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: StsysTheme.successGreen,
                ),
              ),
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class TrainScreen extends StatefulWidget {
  const TrainScreen({super.key});

  @override
  State<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends State<TrainScreen> {
  ShotResult? _lastForwardedShot;
  TrainSessionState? _previousState;
  SensorDataProvider? _sensorProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sensor = context.read<SensorDataProvider>();
    if (!identical(sensor, _sensorProvider)) {
      _sensorProvider?.removeListener(_forwardDetectedShot);
      _sensorProvider = sensor;
      _sensorProvider!.addListener(_forwardDetectedShot);
    }
  }

  @override
  void dispose() {
    _sensorProvider?.removeListener(_forwardDetectedShot);
    super.dispose();
  }

  void _forwardDetectedShot() {
    final train = context.read<TrainSessionProvider>();
    final sensor = context.read<SensorDataProvider>();
    if (train.state == TrainSessionState.activeSeries &&
        sensor.latestShot != null &&
        !identical(sensor.latestShot, _lastForwardedShot)) {
      _lastForwardedShot = sensor.latestShot;
      train.onShotDetected(sensor.latestShot!);
    }
  }

  Future<void> _handleBack(TrainSessionState trainState) async {
    if (trainState != TrainSessionState.readySeries) return;
    final shouldReturn = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: Text('Kembali ke pilihan Train'),
        content: Text('Batalkan pilihan preset saat ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'No',
              style: TextStyle(color: StsysTheme.cyanOf(context)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Yes',
              style: TextStyle(color: StsysTheme.cyanOf(context)),
            ),
          ),
        ],
      ),
    );
    if (shouldReturn == true && mounted) {
      context.read<TrainSessionProvider>().returnToChoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trainState = context.watch<TrainSessionProvider>().state;
    if (_previousState != trainState) {
      if (trainState != TrainSessionState.activeSeries) {
        _lastForwardedShot = context.read<SensorDataProvider>().latestShot;
      }
      _previousState = trainState;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && trainState == TrainSessionState.readySeries) {
          _handleBack(trainState);
        }
      },
      child: Scaffold(
        backgroundColor: StsysTheme.mobileBackgroundOf(context),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: trainState == TrainSessionState.choices
                ? const _ChoicesView(key: ValueKey('choices'))
                : const _SessionView(key: ValueKey('session')),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Choices view â€” profile + preset selection
// ---------------------------------------------------------------------------
class _ChoicesView extends StatelessWidget {
  const _ChoicesView({super.key});

  @override
  Widget build(BuildContext context) {
    final profileProv = context.watch<ProfileProvider>();
    final trainProv = context.read<TrainSessionProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StasysHeader(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 0),
                Text(
                  'TRAIN',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: StsysTheme.cyanOf(context),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),

                // Profile selector
                _buildProfileSection(context, profileProv),
                const SizedBox(height: 20),

                // Preset cards
                Text(
                  'PRESETS',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: StsysTheme.mobileMutedTextOf(context),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: 4,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) => _PresetCard(
                      index: i,
                      enabled: profileProv.activeProfile != null,
                      onTap: () {
                        final preset = [
                          _PresetData.dryAirSoftgun,
                          _PresetData.liveAirPistol,
                          _PresetData.liveAirRifle,
                          _PresetData.liveRifle50,
                        ][i];
                        trainProv.selectPreset(
                          preset: preset,
                          profile: profileProv.activeProfile!,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSection(BuildContext context, ProfileProvider prov) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SHOOTER PROFILE',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: StsysTheme.mobileMutedTextOf(context),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        if (prov.activeProfile != null)
          _ActiveProfileChip(profile: prov.activeProfile!)
        else
          GestureDetector(
            onTap: () => _showProfilePicker(context, prov),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: StsysTheme.mobileSurfaceOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StsysTheme.mobileBorderOf(context)),
              ),
              child: Row(
                children: [
                  Icon(Icons.add, color: StsysTheme.cyanOf(context), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Select or create profile',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: StsysTheme.mobileMutedTextOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showProfilePicker(BuildContext context, ProfileProvider prov) {
    showModalBottomSheet(
      context: context,
      backgroundColor: StsysTheme.mobileBackgroundOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final nameCtrl = TextEditingController();
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SELECT PROFILE',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: StsysTheme.onSurfaceOf(context),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              ...prov.profiles.map(
                (p) => ListTile(
                  title: Text(
                    p.trimmedName,
                    style: TextStyle(color: StsysTheme.onSurfaceOf(context)),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFFF5252),
                      size: 20,
                    ),
                    onPressed: () {
                      prov.deleteProfile(p.trimmedName);
                    },
                  ),
                  onTap: () {
                    prov.selectProfile(p);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              Divider(color: StsysTheme.mobileBorderOf(context)),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: nameCtrl,
                      style: TextStyle(
                        color: StsysTheme.onSurfaceOf(context),
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: 'New profile name',
                        hintStyle: TextStyle(
                          color: StsysTheme.mobileMutedTextOf(context),
                        ),
                        filled: true,
                        fillColor: StsysTheme.mobileSurfaceOf(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: StsysTheme.mobileBorderOf(context),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      prov.createProfile(name);
                      nameCtrl.clear();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: StsysTheme.cyanOf(
                          context,
                        ).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: StsysTheme.cyanOf(
                            context,
                          ).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        'ADD',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: StsysTheme.cyanOf(context),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActiveProfileChip extends StatelessWidget {
  final Profile profile;
  const _ActiveProfileChip({required this.profile});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final prov = context.read<ProfileProvider>();
        prov.clearActiveProfile();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: StsysTheme.cyanOf(context).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: StsysTheme.cyanOf(context).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person, color: StsysTheme.cyanOf(context), size: 16),
            const SizedBox(width: 8),
            Text(
              profile.trimmedName,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: StsysTheme.cyanOf(context),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.close,
              color: StsysTheme.mobileMutedTextOf(context),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final int index;
  final bool enabled;
  final VoidCallback onTap;

  const _PresetCard({
    required this.index,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labels = [
      ('DRY FIRE', 'Air / Softgun', '10m'),
      ('LIVE FIRE', 'Air / Pistol', '10m'),
      ('LIVE FIRE', 'Air / Rifle', '10m'),
      ('LIVE FIRE', 'Rifle', '50m'),
    ];
    final l = labels[index];

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: StsysTheme.mobileSurfaceOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: StsysTheme.mobileBorderOf(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.$1,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: StsysTheme.mobileMutedTextOf(context),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.$2,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: StsysTheme.onSurfaceOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: StsysTheme.cyanOf(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l.$3,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: StsysTheme.cyanOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Session view â€” TRAIN-0 (ready) + TRAIN-1 (active)
// ---------------------------------------------------------------------------
class _SessionView extends StatefulWidget {
  const _SessionView({super.key});

  @override
  State<_SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<_SessionView>
    with TickerProviderStateMixin {
  bool _isSaving = false;
  ShotResult? _lastSelectedShot;

  late final AnimationController _replayController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2500),
        value: 1.0,
      )..addListener(() {
        if (mounted) setState(() {});
      });

  @override
  void dispose() {
    _replayController.dispose();
    super.dispose();
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

  Future<void> _endSeries(BuildContext context) async {
    if (_isSaving) return;
    final train = context.read<TrainSessionProvider>();
    final sensor = context.read<SensorDataProvider>();
    // Capture shots + metadata BEFORE provider mutation.
    final shots = train.currentSeriesShots;
    final profileName = train.activeProfile?.trimmedName ?? '';
    final trainingPreset = train.selectedPreset?.id ?? '';
    final seriesCount = train.seriesCount;
    final firearmType = train.selectedPreset?.firearmType;
    final trainingMode = train.selectedPreset?.trainingMode;

    setState(() => _isSaving = true);
    try {
      if (sensor.isRecording) sensor.stopRecording();
      if (shots.isNotEmpty) {
        await sensor.saveCurrentSession(
          shots: shots,
          profileName: profileName,
          trainingPreset: trainingPreset,
          seriesCount: seriesCount,
          firearmType: firearmType,
          trainingMode: trainingMode,
        );
      }
      train.endSeries();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _endSession(BuildContext context) async {
    if (_isSaving) return;
    final train = context.read<TrainSessionProvider>();
    final sensor = context.read<SensorDataProvider>();
    // Capture BEFORE endSession() resets profile/preset/session counters.
    final shots = train.currentSeriesShots;
    final profileName = train.activeProfile?.trimmedName ?? '';
    final trainingPreset = train.selectedPreset?.id ?? '';
    final seriesCount = train.seriesCount;
    final firearmType = train.selectedPreset?.firearmType;
    final trainingMode = train.selectedPreset?.trainingMode;

    setState(() => _isSaving = true);
    try {
      if (sensor.isRecording) sensor.stopRecording();
      if (shots.isNotEmpty) {
        await sensor.saveCurrentSession(
          shots: shots,
          profileName: profileName,
          trainingPreset: trainingPreset,
          seriesCount: seriesCount,
          firearmType: firearmType,
          trainingMode: trainingMode,
        );
      }
      train.endSession();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final train = context.watch<TrainSessionProvider>();
    final sensor = context.watch<SensorDataProvider>();
    final state = train.state;
    final active = state == TrainSessionState.activeSeries;
    final seriesReview = state == TrainSessionState.reviewSeries;
    final sessionReview = state == TrainSessionState.reviewSession;
    final review = seriesReview || sessionReview;
    final preset = train.selectedPreset;
    final shots = review ? train.lastSeriesShots : train.currentSeriesShots;
    final selectedIndex = train.selectedShotIndex;
    final selectedShot = shots.isEmpty
        ? null
        : shots[selectedIndex ?? shots.length - 1];

    // Selecting another shot resets the replay to the full trace.
    if (!identical(_lastSelectedShot, selectedShot)) {
      _lastSelectedShot = selectedShot;
      _replayController.value = 1.0;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // TRAIN-0 gets the larger Figma target. Once a shot exists, reserve
        // room for the log and compact replay instead of forcing a 342px
        // target plus a fixed-size replay into the phone viewport.
        final compactTarget = active || (review && shots.isNotEmpty);
        final widthCap = math.min(
          compactTarget ? 300.0 : 342.0,
          math.max(compactTarget ? 190.0 : 220.0, constraints.maxWidth - 40),
        );
        // Short viewports (e.g. 320x568) cannot fit a near-square target plus
        // the shot-log label, chips and replay panel: reserve their height so
        // the column never overflows. The reservation grows when the replay
        // panel shows its chip row (more than one shot).
        final minTarget = compactTarget ? 190.0 : 220.0;
        final heightCap = shots.isEmpty
            ? double.infinity
            : constraints.maxHeight - (shots.length > 1 ? 378.0 : 326.0);
        final targetSize = math.max(minTarget, math.min(widthCap, heightCap));
        // Full-bleed background band behind the square target while a series is
        // live or under review. The padded column can only hand out
        // maxWidth - 40 children, so the band overflows horizontally back to
        // the true screen width (overflowing a Column child sideways is safe:
        // RenderFlex only reports main-axis overflow) while the square target
        // stays centered inside it. TRAIN-0 (start) keeps the plain boxless
        // target.
        final showBand = active || review;
        final trainingMode =
            preset?.trainingMode ??
            (sessionReview && shots.isNotEmpty
                ? shots.last.trainingMode
                : null);
        const bandColor = Color(0xFFF3F4F2);
        final targetWidget = SizedBox(
          width: targetSize,
          height: targetSize,
          child: TrainTargetWidget(
            isActive: active,
            display: review
                ? (_replayController.value < 1.0
                      ? TrainTargetDisplay.activeTrace
                      : TrainTargetDisplay.seriesScatter)
                : active
                ? TrainTargetDisplay.activeTrace
                : TrainTargetDisplay.start,
            replayProgress: _replayController.value,
            selectedShot: selectedShot,
            scatterShots: review ? shots : const [],
            latestScore: shots.isEmpty ? null : shots.last.totalScore,
            sessionShots: shots,
            preset: preset,
            trainingMode: trainingMode,
            onStart: state == TrainSessionState.readySeries
                ? () {
                    train.startSeries();
                    sensor.startRecording();
                  }
                : null,
          ),
        );
        return Column(
          children: [
            const _StasysHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  children: [
                    const SizedBox(height: 0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  seriesReview
                                      ? 'SERIES REVIEW'
                                      : sessionReview
                                      ? 'SESSION REVIEW'
                                      : 'TRAIN-1',
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontWeight: FontWeight.w900,
                                    fontSize: review ? 13 : 17,
                                    color: StsysTheme.cyanOf(context),
                                    letterSpacing: 1.8,
                                  ),
                                ),
                                if (!review) ...[
                                  const SizedBox(width: 10),
                                  Text(
                                    '${preset?.weaponLabel ?? ''} · ${preset?.distanceMeters ?? 0}M',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 11,
                                      color: StsysTheme.mobileMutedTextOf(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (active && !_isSaving)
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _SessionControl(
                                    label: 'END SERIES',
                                    color: StsysTheme.liveRed,
                                    onTap: () => _endSeries(context),
                                  ),
                                  const SizedBox(width: 6),
                                  _SessionControl(
                                    label: 'END SESSION',
                                    color: StsysTheme.liveRed,
                                    onTap: () => _endSession(context),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (review)
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: _SessionControl(
                                label: 'OK',
                                color: StsysTheme.cyanOf(context),
                                onTap: () => train.confirmReview(),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        review
                            ? 'SERIES ${train.seriesCount}  ·  COMPLETE'
                            : active
                            ? 'SERIES ${train.seriesCount}  ·  LIVE'
                            : 'READY  ·  SERIES ${train.seriesCount + 1}',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: active
                              ? StsysTheme.liveRed
                              : StsysTheme.mobileMutedTextOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (showBand)
                      SizedBox(
                        width: constraints.maxWidth,
                        height: targetSize + 24,
                        child: OverflowBox(
                          minWidth: constraints.maxWidth,
                          maxWidth: constraints.maxWidth,
                          child: Container(
                            width: constraints.maxWidth,
                            color: bandColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: targetWidget),
                          ),
                        ),
                      )
                    else
                      targetWidget,
                    const SizedBox(height: 8),
                    if ((active || review) && shots.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'SHOT LOG / REPLAY',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.3,
                            color: StsysTheme.mobileMutedTextOf(context),
                          ),
                        ),
                      ),
                    const SizedBox(height: 5),
                    _ShotLogRow(shots: shots),
                    if ((active || review) && shots.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Flexible(
                        child: ShotReplayPanel(
                          progress: _replayController.value,
                          isPlaying: _replayController.isAnimating,
                          onPlay: _playReplay,
                          onPause: _pauseReplay,
                          onSeek: _seekReplay,
                          onReset: _resetReplay,
                        ),
                      ),
                    ] else
                      const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SessionControl extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SessionControl({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .7), width: 1.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .9,
          color: color,
        ),
      ),
    ),
  );
}

class _ShotLogRow extends StatelessWidget {
  final List<ShotResult> shots;
  _ShotLogRow({required this.shots});

  @override
  Widget build(BuildContext context) {
    if (shots.isEmpty) {
      return Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: StsysTheme.mobileSurfaceOf(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StsysTheme.mobileBorderOf(context)),
        ),
        child: Text(
          'NO SHOTS YET',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w700,
            fontSize: 10,
            color: StsysTheme.mobileMutedTextOf(context),
            letterSpacing: 1.2,
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final shot = shots[i];
          final score = shot.totalScore;
          final color = score >= 80
              ? const Color(0xFF39D98A)
              : score >= 60
              ? StsysTheme.cyanOf(context)
              : const Color(0xFFFF5252);
          return GestureDetector(
            onTap: () => context.read<TrainSessionProvider>().selectShot(i),
            child: Container(
              width: 108,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'SHOT ${i + 1}  ${score.round()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            color: color,
                          ),
                        ),
                        Text(
                          'STAB ${shot.holdScore.round()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            color: StsysTheme.mobileMutedTextOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.replay,
                    size: 14,
                    color: StsysTheme.mobileMutedTextOf(context),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Preset data mapped to TrainPreset models
class _PresetData {
  static final dryAirSoftgun = TrainPreset.all[0];
  static final liveAirPistol = TrainPreset.all[1];
  static final liveAirRifle = TrainPreset.all[2];
  static final liveRifle50 = TrainPreset.all[3];
}
