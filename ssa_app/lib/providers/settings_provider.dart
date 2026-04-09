// ============================================
// File: providers/settings_provider.dart
// ============================================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/data_models.dart';

class SettingsProvider extends ChangeNotifier {
  late SharedPreferences _prefs;

  // Display settings
  int _maxSamples = 6;
  final double _stableAxisLimit = 0.16;

  // Training settings
  FirearmType _firearmType = FirearmType.pistol;
  TrainingMode _trainingMode = TrainingMode.dryFire;

  // Demo mode
  bool _isDemoMode = false;

  // Getters
  int get maxSamples => _maxSamples;
  double get stableAxisLimit => _stableAxisLimit;
  FirearmType get firearmType => _firearmType;
  TrainingMode get trainingMode => _trainingMode;
  bool get isDemoMode => _isDemoMode;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    _maxSamples = _prefs.getInt('maxSamples') ?? 6;
    _firearmType = FirearmType.fromString(
      _prefs.getString('firearmType') ?? 'pistol',
    );
    _trainingMode = TrainingMode.fromString(
      _prefs.getString('trainingMode') ?? 'dryFire',
    );
    notifyListeners();
  }

  Future<void> updateMaxSamples(int newMaxSamples) async {
    if (_maxSamples == newMaxSamples) return;
    _maxSamples = newMaxSamples;
    await _prefs.setInt('maxSamples', newMaxSamples);
    notifyListeners();
  }

  Future<void> updateFirearmType(FirearmType type) async {
    if (_firearmType == type) return;
    _firearmType = type;
    await _prefs.setString('firearmType', type.name);
    notifyListeners();
  }

  Future<void> updateTrainingMode(TrainingMode mode) async {
    if (_trainingMode == mode) return;
    _trainingMode = mode;
    await _prefs.setString('trainingMode', mode.name);
    notifyListeners();
  }

  void setDemoMode(bool value) {
    if (_isDemoMode == value) return;
    _isDemoMode = value;
    notifyListeners();
  }
}