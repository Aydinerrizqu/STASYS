// ============================================
// File: screens/tabs/settings_tab.dart
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/data_models.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
        backgroundColor: Colors.grey[700],
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // --- TRAINING SETUP SECTION ---
              const Text(
                'TRAINING SETUP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),

              // Firearm Type Selector
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Jenis Senjata',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mempengaruhi difficulty multiplier pada scoring',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<FirearmType>(
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
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Training Mode Selector
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mode Latihan',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dry Fire: gunakan piezo trigger. Live Fire: deteksi via accelerometer.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<TrainingMode>(
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
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // --- DISPLAY SECTION ---
              const Text(
                'DISPLAY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),

              // Graph Duration Slider
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Durasi Grafik',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${settings.maxSamples} detik',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: settings.maxSamples.toDouble(),
                        min: 3,
                        max: 15,
                        divisions: 4,
                        label: '${settings.maxSamples} detik',
                        onChanged: (double value) {
                          settings.updateMaxSamples(value.toInt());
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // --- SCORING INFO ---
              const Text(
                'SCORING',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _scoreRow('Elite', '95-100', Colors.amber),
                      _scoreRow('Expert', '85-94', Colors.green),
                      _scoreRow('Advanced', '70-84', Colors.blue),
                      _scoreRow('Intermediate', '50-69', Colors.orange),
                      _scoreRow('Beginner', '0-49', Colors.red),
                      const SizedBox(height: 8),
                      Text(
                        'Difficulty: ${settings.firearmType.displayName} (${_getDifficultyLabel(settings.firearmType)}) • '
                        '${settings.trainingMode.displayName}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _scoreRow(String label, String range, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(range, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  String _getDifficultyLabel(FirearmType type) {
    switch (type) {
      case FirearmType.pistol:
        return 'Baseline';
      case FirearmType.rifle:
        return 'More stable';
      case FirearmType.archery:
        return 'Most strict';
      case FirearmType.shotgun:
        return 'Follow-through focus';
    }
  }
}
