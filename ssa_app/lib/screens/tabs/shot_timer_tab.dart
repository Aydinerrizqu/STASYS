// ============================================
// File: screens/tabs/shot_timer_tab.dart
// Shot Timer — redesigned large digital display
// ============================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/sensor_data_provider.dart';
import '../../providers/bluetooth_provider.dart';
import '../../theme/app_theme.dart';

class ShotTimerTab extends StatefulWidget {
  const ShotTimerTab({super.key});

  @override
  State<ShotTimerTab> createState() => _ShotTimerTabState();
}

class _ShotTimerTabState extends State<ShotTimerTab> {
  ShotTimerState _timerState = ShotTimerState.ready;
  int _countdownSeconds = 3;
  int _selectedCountdown = 3;
  int _elapsedMs = 0;
  Timer? _timer;
  final List<_ShotTime> _shots = [];
  int _shotCount = 0;
  DateTime? _startTime;
  bool _isCalibrated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sensor = context.read<SensorDataProvider>();
      setState(() => _isCalibrated = sensor.isCalibrated);
      sensor.addListener(_onSensorUpdate);
    });
  }

  void _onSensorUpdate() {
    final sensor = context.read<SensorDataProvider>();
    final wasCalibrated = _isCalibrated;
    _isCalibrated = sensor.isCalibrated;
    if (!wasCalibrated && _isCalibrated) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    if (!_isCalibrated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Calibrate sensor first!'),
          backgroundColor: AppTheme.warning.withValues(alpha: 0.9),
        ),
      );
      return;
    }

    setState(() {
      _timerState = ShotTimerState.countdown;
      _countdownSeconds = _selectedCountdown;
      _shots.clear();
      _shotCount = 0;
      _elapsedMs = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() => _countdownSeconds--);
      } else {
        timer.cancel();
        _startTimer();
      }
    });
  }

  void _startTimer() {
    setState(() {
      _timerState = ShotTimerState.running;
      _startTime = DateTime.now();
    });

    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (_timerState != ShotTimerState.running) {
        timer.cancel();
        return;
      }
      setState(() => _elapsedMs = DateTime.now().difference(_startTime!).inMilliseconds);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() => _timerState = ShotTimerState.stopped);
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _timerState = ShotTimerState.ready;
      _elapsedMs = 0;
      _shots.clear();
      _shotCount = 0;
    });
  }

  String _formatMs(int ms) {
    final secs = ms ~/ 1000;
    final millis = (ms % 1000) ~/ 10;
    return '$secs.${millis.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Header
              _buildHeader(),

              const SizedBox(height: 12),

              // Connection status
              _buildConnectionStatus(),

              const SizedBox(height: 20),

              // Timer display
              Expanded(
                flex: 3,
                child: _buildTimerDisplay(),
              ),

              // Countdown selector
              if (_timerState == ShotTimerState.ready || _timerState == ShotTimerState.stopped)
                _buildCountdownSelector(),

              const SizedBox(height: 16),

              // Shots list
              Expanded(
                flex: 2,
                child: _buildShotList(),
              ),

              const SizedBox(height: 16),

              // Action buttons
              _buildControls(),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Shot Timer', style: AppTheme.title),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isCalibrated ? Icons.check_circle : Icons.warning_amber,
                size: 14,
                color: _isCalibrated ? AppTheme.success : AppTheme.warning,
              ),
              const SizedBox(width: 4),
              Text(
                _isCalibrated ? 'Calibrated' : 'Calibrate First',
                style: TextStyle(
                  color: _isCalibrated ? AppTheme.success : AppTheme.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    return Consumer<BluetoothProvider>(
      builder: (context, bt, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: AppTheme.cardDecoration(),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bt.isConnected ? AppTheme.success : AppTheme.textTertiary,
                  boxShadow: bt.isConnected
                      ? [BoxShadow(color: AppTheme.success.withValues(alpha: 0.5), blurRadius: 6)]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  bt.isConnected
                      ? bt.selectedDevice?.name ?? 'STASYS Device'
                      : 'No device connected',
                  style: TextStyle(
                    color: bt.isConnected ? AppTheme.textPrimary : AppTheme.textTertiary,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimerDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: AppTheme.cardDecoration(glow: _timerState == ShotTimerState.running),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // State label
          _buildStateLabel(),

          const SizedBox(height: 8),

          // Main timer
          _buildMainTimer(),

          const SizedBox(height: 12),

          // Shot counter
          if (_timerState == ShotTimerState.running || _timerState == ShotTimerState.stopped)
            _buildShotCounter(),
        ],
      ),
    );
  }

  Widget _buildStateLabel() {
    String label;
    Color color;

    switch (_timerState) {
      case ShotTimerState.ready:
        label = 'READY';
        color = AppTheme.textSecondary;
        break;
      case ShotTimerState.countdown:
        label = 'GET READY';
        color = AppTheme.warning;
        break;
      case ShotTimerState.running:
        label = 'TIME';
        color = AppTheme.success;
        break;
      case ShotTimerState.stopped:
        label = 'FINISHED';
        color = AppTheme.primary;
        break;
    }

    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 3,
      ),
    );
  }

  Widget _buildMainTimer() {
    if (_timerState == ShotTimerState.countdown) {
      return Text(
        '$_countdownSeconds',
        style: const TextStyle(
          fontSize: 100,
          fontWeight: FontWeight.bold,
          color: AppTheme.textPrimary,
          fontFamily: 'monospace',
        ),
      );
    }

    if (_timerState == ShotTimerState.ready) {
      return Text(
        '0.00',
        style: TextStyle(
          fontSize: 80,
          fontWeight: FontWeight.bold,
          color: AppTheme.textTertiary.withValues(alpha: 0.4),
          fontFamily: 'monospace',
        ),
      );
    }

    final displayMs = _timerState == ShotTimerState.stopped ? _elapsedMs : _elapsedMs;
    final secs = displayMs ~/ 1000;
    final millis = (displayMs % 1000) ~/ 10;

    return Text(
      '$secs.${millis.toString().padLeft(2, '0')}',
      style: TextStyle(
        fontSize: 80,
        fontWeight: FontWeight.bold,
        color: _timerState == ShotTimerState.running ? AppTheme.success : AppTheme.textPrimary,
        fontFamily: 'monospace',
        letterSpacing: 2,
        shadows: _timerState == ShotTimerState.running
            ? [
                Shadow(
                  color: AppTheme.success.withValues(alpha: 0.4),
                  blurRadius: 20,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildShotCounter() {
    final color = _getShotCountColor(_shotCount);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$_shotCount',
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'SHOT${_shotCount != 1 ? 'S' : ''}',
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Color _getShotCountColor(int count) {
    if (count == 0) return AppTheme.textTertiary;
    if (count <= 3) return AppTheme.primary;
    if (count <= 6) return AppTheme.success;
    return AppTheme.scoreElite;
  }

  Widget _buildCountdownSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            'Countdown:',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(width: 8),
          ...([3, 5, 10]).map((secs) => Expanded(
            child: _countdownChip(secs),
          )),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _countdownChip(int secs) {
    final isSelected = _selectedCountdown == secs;
    return GestureDetector(
      onTap: () => setState(() => _selectedCountdown = secs),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '${secs}s',
            style: TextStyle(
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShotList() {
    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text('#', style: _headerStyle),
                ),
                Expanded(child: Center(child: Text('TIME', style: _headerStyle))),
                SizedBox(
                  width: 70,
                  child: Text('SPLIT', style: _headerStyle),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: _shots.isEmpty
                ? Center(
                    child: Text(
                      'No shots recorded',
                      style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _shots.length,
                    itemBuilder: (context, index) {
                      final shot = _shots[_shots.length - 1 - index];
                      final splitColor = shot.splitMs < 500
                          ? AppTheme.success
                          : shot.splitMs > 2000
                              ? AppTheme.error
                              : AppTheme.textSecondary;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppTheme.cardBorder.withValues(alpha: 0.5)),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text(
                                '${shot.number}',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  _formatMs(shot.totalMs),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 70,
                              child: Text(
                                _formatMs(shot.splitMs),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  color: splitColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  TextStyle get _headerStyle => TextStyle(
    color: AppTheme.textTertiary,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1,
  );

  Widget _buildControls() {
    return Row(
      children: [
        if (_timerState == ShotTimerState.ready || _timerState == ShotTimerState.stopped)
          Expanded(
            child: _actionButton(
              'START',
              AppTheme.success,
              Icons.play_arrow,
              _startCountdown,
            ),
          ),
        if (_timerState == ShotTimerState.countdown)
          Expanded(
            child: _actionButton(
              'CANCEL',
              AppTheme.warning,
              Icons.close,
              _resetTimer,
            ),
          ),
        if (_timerState == ShotTimerState.running)
          Expanded(
            child: _actionButton(
              'STOP',
              AppTheme.error,
              Icons.stop,
              _stopTimer,
            ),
          ),
        if (_timerState == ShotTimerState.stopped) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _actionButton(
              'RESET',
              AppTheme.primary,
              Icons.refresh,
              _resetTimer,
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionButton(String label, Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.background, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.background,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum ShotTimerState { ready, countdown, running, stopped }

class _ShotTime {
  final int number;
  final int totalMs;
  final int splitMs;
  _ShotTime({required this.number, required this.totalMs, required this.splitMs});
}
