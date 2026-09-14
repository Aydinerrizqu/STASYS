import 'package:flutter/foundation.dart';
import '../models/train_preset.dart';
import '../models/profile.dart';
import '../models/data_models.dart';

enum TrainSessionState { choices, readySeries, activeSeries }

class TrainSessionProvider extends ChangeNotifier {
  TrainSessionState _state = TrainSessionState.choices;
  TrainPreset? _preset;
  Profile? _profile;
  int _seriesCount = 0;
  List<ShotResult> _currentSeries = [];
  List<ShotResult> _allShots = [];
  int? _selectedShotIndex;

  TrainSessionState get state => _state;
  TrainPreset? get selectedPreset => _preset;
  Profile? get activeProfile => _profile;
  int get seriesCount => _seriesCount;
  List<ShotResult> get currentSeriesShots => List.unmodifiable(_currentSeries);
  List<ShotResult> get allSeriesShots => List.unmodifiable(_allShots);
  int? get selectedShotIndex => _selectedShotIndex;

  void selectPreset({required TrainPreset preset, required Profile profile}) {
    if (_state != TrainSessionState.choices) return;
    _preset = preset;
    _profile = profile;
    _state = TrainSessionState.readySeries;
    notifyListeners();
  }

  void startSeries() {
    if (_state != TrainSessionState.readySeries) return;
    _seriesCount++;
    _currentSeries = [];
    _selectedShotIndex = null;
    _state = TrainSessionState.activeSeries;
    notifyListeners();
  }

  void endSeries() {
    if (_state != TrainSessionState.activeSeries) return;
    _allShots = [..._allShots, ..._currentSeries];
    _currentSeries = [];
    _selectedShotIndex = null;
    _state = TrainSessionState.readySeries;
    notifyListeners();
  }

  void endSession() {
    if (_state == TrainSessionState.choices) return;

    if (_state == TrainSessionState.activeSeries) {
      _allShots = [..._allShots, ..._currentSeries];
      _currentSeries = [];
    }

    _state = TrainSessionState.choices;
    _preset = null;
    _profile = null;
    _seriesCount = 0;
    _allShots = [];
    _currentSeries = [];
    _selectedShotIndex = null;
    notifyListeners();
  }

  void onShotDetected(ShotResult shot) {
    if (_state != TrainSessionState.activeSeries) return;
    _currentSeries = [..._currentSeries, shot];
    _selectedShotIndex = _currentSeries.length - 1;
    notifyListeners();
  }

  void selectShot(int index) {
    if (_state != TrainSessionState.activeSeries) return;
    if (index < 0 || index >= _currentSeries.length) return;
    _selectedShotIndex = index;
    notifyListeners();
  }
}
