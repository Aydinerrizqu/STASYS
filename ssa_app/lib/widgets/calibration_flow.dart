// ============================================
// File: widgets/calibration_flow.dart
// Mandatory calibration + mount flow after BT connection
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_data_provider.dart';
import 'muzzle_trace_widget.dart';

/// Shows after BT auth + firmware check passes.
/// Phase 1: Direction calibration (live trace preview + CALIBRATE / MATCHED)
/// Phase 2: Mount confirmation message → navigate to /train
class CalibrationFlowDialog extends StatefulWidget {
  const CalibrationFlowDialog({super.key});

  @override
  State<CalibrationFlowDialog> createState() => _CalibrationFlowDialogState();
}

/// Calibration phase exposed for testing.
enum CalibrationPhase { directionCheck, mountConfirmation }

class _CalibrationFlowDialogState extends State<CalibrationFlowDialog> {
  CalibrationPhase _phase = CalibrationPhase.directionCheck;

  void _calibrate() {
    context.read<SensorDataProvider>().resetAxis();
  }

  void _matched() {
    setState(() => _phase = CalibrationPhase.mountConfirmation);
  }

  void _confirmed() {
    Navigator.of(context).pop(); // dismiss dialog — caller navigates
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0C0E11),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF1F242C)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: _phase == CalibrationPhase.directionCheck
            ? _buildDirectionCheck()
            : _buildMountConfirmation(),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Phase 1 — Direction Check
  // ------------------------------------------------------------------
  Widget _buildDirectionCheck() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          const Text(
            'CALIBRATE',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Move your device — the dot should follow your movement.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Same 60fps trace pipeline as tracking (ticker + accel fallback).
          const SizedBox(
            height: 160,
            width: double.infinity,
            child: MuzzleTraceWidget(
              zoom: 0.05,
              showGrid: true,
              compact: true,
            ),
          ),
          const SizedBox(height: 20),

          // Buttons row
          Row(
            children: [
              // CALIBRATE button (red accent)
              Expanded(
                child: _CalibButton(
                  label: 'CALIBRATE',
                  color: const Color(0xFFFF5252),
                  onTap: _calibrate,
                ),
              ),
              const SizedBox(width: 12),
              // MATCHED button (cyan)
              Expanded(
                child: _CalibButton(
                  label: 'MATCHED',
                  color: const Color(0xFF00D8FF),
                  onTap: _matched,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Phase 2 — Mount Confirmation
  // ------------------------------------------------------------------
  Widget _buildMountConfirmation() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.straighten,
            color: const Color(0xFF00D8FF).withValues(alpha: 0.8),
            size: 40,
          ),
          const SizedBox(height: 16),
          const Text(
            'MOUNT STASYS',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Attach the device to your firearm and confirm when ready.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: _CalibButton(
              label: 'CONFIRM',
              color: const Color(0xFF00D8FF),
              onTap: _confirmed,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Reusable button
// ------------------------------------------------------------------
class _CalibButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CalibButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: color,
          ),
        ),
      ),
    );
  }
}
