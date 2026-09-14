import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_data_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/muzzle_trace_widget.dart';

/// Simplified dot-only tracking screen.
/// Shows live trace preview — no START, END SERIES, END SESSION, score, or replay.
class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StsysTheme.mobileBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context),
            // Dot-only preview
            const Expanded(child: _DotOnlyPreview()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Text(
            'TRACKING',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: Color(0xFF00D8FF),
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          Consumer<SensorDataProvider>(
            builder: (context, sensor, _) {
              return _BatteryIndicator(level: sensor.batteryLevel);
            },
          ),
        ],
      ),
    );
  }
}

class _DotOnlyPreview extends StatelessWidget {
  const _DotOnlyPreview();

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, sensor, _) {
        if (!sensor.isCalibrated && !sensor.isCalibrating) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sensors, color: Color(0xFF8B8B8B), size: 40),
                const SizedBox(height: 12),
                Text(
                  'Waiting for sensor data...',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: StsysTheme.mobileMutedText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Connect your STASYS device or enable Demo Mode',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: StsysTheme.mobileMutedText.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0C0F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1F242C)),
              ),
              child: const MuzzleTraceWidget(),
            ),
          ),
        );
      },
    );
  }
}

class _BatteryIndicator extends StatelessWidget {
  final int level;
  const _BatteryIndicator({required this.level});

  IconData get _icon {
    if (level >= 80) return Icons.battery_full;
    if (level >= 60) return Icons.battery_5_bar;
    if (level >= 40) return Icons.battery_4_bar;
    if (level >= 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color get _color {
    if (level >= 60) return const Color(0xFF39D98A);
    if (level >= 20) return const Color(0xFFFF9800);
    return const Color(0xFFFF5252);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon, color: _color, size: 18),
        const SizedBox(width: 2),
        Text(
          '$level%',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _color,
          ),
        ),
      ],
    );
  }
}
