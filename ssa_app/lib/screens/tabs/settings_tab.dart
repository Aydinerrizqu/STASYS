// ============================================
// File: screens/tabs/settings_tab.dart
// Settings — redesigned dark theme
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/data_models.dart';
import '../../theme/app_theme.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Consumer<SettingsProvider>(
          builder: (context, settings, child) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header
                const Text('Settings', style: AppTheme.title),
                const SizedBox(height: 4),
                Text(
                  'Configure your training preferences',
                  style: AppTheme.subtitle,
                ),
                const SizedBox(height: 24),

                // Training Setup Section
                _buildSectionHeader('TRAINING SETUP'),
                const SizedBox(height: 10),

                // Firearm Type
                _buildCard([
                  _buildCardHeader('Firearm Type', Icons.gps_fixed),
                  const SizedBox(height: 4),
                  Text(
                    'Affects scoring difficulty multiplier',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<FirearmType>(
                      segments: FirearmType.values.map((type) {
                        return ButtonSegment<FirearmType>(
                          value: type,
                          label: Text(type.displayName),
                        );
                      }).toList(),
                      selected: {settings.firearmType},
                      onSelectionChanged: (selected) {
                        settings.updateFirearmType(selected.first);
                      },
                    ),
                  ),
                ]),

                const SizedBox(height: 12),

                // Training Mode
                _buildCard([
                  _buildCardHeader('Training Mode', Icons.flash_on),
                  const SizedBox(height: 4),
                  Text(
                    'Dry Fire: piezo trigger. Live Fire: accelerometer detection.',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<TrainingMode>(
                      segments: TrainingMode.values.map((mode) {
                        return ButtonSegment<TrainingMode>(
                          value: mode,
                          label: Text(mode.displayName),
                        );
                      }).toList(),
                      selected: {settings.trainingMode},
                      onSelectionChanged: (selected) {
                        settings.updateTrainingMode(selected.first);
                      },
                    ),
                  ),
                ]),

                const SizedBox(height: 24),

                // Display Section
                _buildSectionHeader('DISPLAY'),
                const SizedBox(height: 10),

                // Graph Duration
                _buildCard([
                  _buildCardHeader('Graph Duration', Icons.timer),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${settings.maxSamples} seconds',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${settings.maxSamples * 100} samples',
                        style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Slider(
                    value: settings.maxSamples.toDouble(),
                    min: 3,
                    max: 15,
                    divisions: 4,
                    label: '${settings.maxSamples}s',
                    onChanged: (value) {
                      settings.updateMaxSamples(value.toInt());
                    },
                  ),
                ]),

                const SizedBox(height: 24),

                // Scoring Section
                _buildSectionHeader('SCORING'),
                const SizedBox(height: 10),

                _buildCard([
                  _buildCardHeader('Score Ratings', Icons.star_outline),
                  const SizedBox(height: 12),
                  _buildScoreLegend(),
                ]),

                const SizedBox(height: 12),

                _buildCard([
                  _buildCardHeader('Current Configuration', Icons.tune),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildConfigChip(
                          settings.firearmType.displayName,
                          AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildConfigChip(
                          settings.trainingMode.displayName,
                          AppTheme.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Difficulty: ${_getDifficultyLabel(settings.firearmType)}',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                  ),
                ]),

                const SizedBox(height: 24),

                // About Section
                _buildSectionHeader('ABOUT'),
                const SizedBox(height: 10),

                _buildCard([
                  _buildCardHeader('STASYS', Icons.track_changes),
                  const SizedBox(height: 12),
                  _buildAboutRow('Version', '3.1'),
                  _buildAboutRow('Platform', 'Flutter'),
                  _buildAboutRow('Purpose', 'Shooter Stability Analysis'),
                  const SizedBox(height: 8),
                  Text(
                    'DIY dry/live fire training with real-time shot scoring, muzzle trace visualization, and session analysis.',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                  ),
                ]),

                const SizedBox(height: 100),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: AppTheme.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildCardHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildScoreLegend() {
    return Column(
      children: [
        _scoreLegendRow('Elite', '95-100', AppTheme.scoreElite),
        _scoreLegendRow('Expert', '85-94', AppTheme.scoreExpert),
        _scoreLegendRow('Advanced', '70-84', AppTheme.scoreAdvanced),
        _scoreLegendRow('Intermediate', '50-69', AppTheme.scoreIntermediate),
        _scoreLegendRow('Beginner', '0-49', AppTheme.scoreBeginner),
      ],
    );
  }

  Widget _scoreLegendRow(String label, String range, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            range,
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildAboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _getDifficultyLabel(FirearmType type) {
    switch (type) {
      case FirearmType.pistol:
        return 'Baseline (1.0x)';
      case FirearmType.rifle:
        return 'More stable (0.7x)';
      case FirearmType.archery:
        return 'Most strict (1.3x)';
      case FirearmType.shotgun:
        return 'Follow-through (0.9x)';
    }
  }
}
