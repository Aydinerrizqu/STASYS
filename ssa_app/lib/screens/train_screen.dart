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

class TrainScreen extends StatelessWidget {
  const TrainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final trainState = context.watch<TrainSessionProvider>().state;

    return Scaffold(
      backgroundColor: StsysTheme.mobileBackground,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: trainState == TrainSessionState.choices
              ? const _ChoicesView(key: ValueKey('choices'))
              : const _SessionView(key: ValueKey('session')),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Choices view — profile + preset selection
// ---------------------------------------------------------------------------
class _ChoicesView extends StatelessWidget {
  const _ChoicesView({super.key});

  @override
  Widget build(BuildContext context) {
    final profileProv = context.watch<ProfileProvider>();
    final trainProv = context.read<TrainSessionProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TRAIN',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: Color(0xFF00D8FF),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),

          // Profile selector
          _buildProfileSection(context, profileProv),
          const SizedBox(height: 20),

          // Preset cards
          const Text(
            'PRESETS',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: Color(0xFF8B8B8B),
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
    );
  }

  Widget _buildProfileSection(BuildContext context, ProfileProvider prov) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SHOOTER PROFILE',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: Color(0xFF8B8B8B),
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
                color: const Color(0xFF111418),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1F242C)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add, color: Color(0xFF00D8FF), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Select or create profile',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: Color(0xFF8B8B8B),
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
      backgroundColor: const Color(0xFF0C0E11),
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
              const Text(
                'SELECT PROFILE',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              ...prov.profiles.map(
                (p) => ListTile(
                  title: Text(
                    p.trimmedName,
                    style: const TextStyle(color: Colors.white),
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
              const Divider(color: Color(0xFF1F242C)),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'New profile name',
                        hintStyle: const TextStyle(color: Color(0xFF8B8B8B)),
                        filled: true,
                        fillColor: const Color(0xFF111418),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF1F242C),
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
                        color: const Color(0xFF00D8FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF00D8FF).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        'ADD',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: Color(0xFF00D8FF),
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
          color: const Color(0xFF00D8FF).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF00D8FF).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person, color: Color(0xFF00D8FF), size: 16),
            const SizedBox(width: 8),
            Text(
              profile.trimmedName,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFF00D8FF),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.close, color: Color(0xFF8B8B8B), size: 14),
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
            color: const Color(0xFF111418),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1F242C)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.$1,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: Color(0xFF8B8B8B),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.$2,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white,
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
                  color: const Color(0xFF00D8FF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l.$3,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF00D8FF),
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
// Session view — TRAIN-0 (ready) + TRAIN-1 (active)
// ---------------------------------------------------------------------------
class _SessionView extends StatelessWidget {
  const _SessionView({super.key});

  @override
  Widget build(BuildContext context) {
    final trainProv = context.watch<TrainSessionProvider>();
    final isActive = trainProv.state == TrainSessionState.activeSeries;
    final sensorProv = context.watch<SensorDataProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Text(
                'TRAIN',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Color(0xFF00D8FF),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Series ${trainProv.seriesCount}',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: Color(0xFF8B8B8B),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  if (isActive) {
                    trainProv.endSeries();
                  } else {
                    trainProv.startSeries();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFFF5252).withValues(alpha: 0.15)
                        : const Color(0xFF00D8FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFFFF5252).withValues(alpha: 0.4)
                          : const Color(0xFF00D8FF).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    isActive ? 'END SERIES' : 'START',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: isActive
                          ? const Color(0xFFFF5252)
                          : const Color(0xFF00D8FF),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    trainProv.endSession();
                    if (sensorProv.isRecording) sensorProv.stopRecording();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFFF5252).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text(
                      'END SESSION',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: Color(0xFFFF5252),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Target
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: TrainTargetWidget(
                  isActive: isActive,
                  latestScore: sensorProv.latestShot?.totalScore,
                  sessionShots: sensorProv.sessionShots,
                ),
              ),
            ),
          ),

          // Shot log (latest shots)
          if (trainProv.currentSeriesShots.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ShotLogRow(shots: trainProv.currentSeriesShots),
          ],

          // Selected-shot replay panel
          if (isActive && trainProv.currentSeriesShots.isNotEmpty) ...[
            const SizedBox(height: 8),
            const ShotReplayPanel(),
          ],

          // End session button in ready state
          if (!isActive) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                trainProv.endSession();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFF5252).withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'END SESSION',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Color(0xFFFF5252),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShotLogRow extends StatelessWidget {
  final List<ShotResult> shots;
  const _ShotLogRow({required this.shots});

  @override
  Widget build(BuildContext context) {
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
              ? const Color(0xFF00D8FF)
              : const Color(0xFFFF5252);
          return GestureDetector(
            onTap: () => context.read<TrainSessionProvider>().selectShot(i),
            child: Container(
              width: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text(
                  score.round().toString(),
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
