import 'package:flutter/foundation.dart';
import '../models/train_preset.dart';
import '../models/profile.dart';
import '../models/data_models.dart';

enum TrainSessionState { choices, readySeries, activeSeries, reviewSeries, reviewSession }

class TrainSessionProvider extends ChangeNotifier {
  TrainSessionState _state = TrainSessionState.choices;
  TrainPreset? _preset;
  Profile? _profile;
  int _seriesCount = 0;
  List<ShotResult> _currentSeries = [];
  List<ShotResult> _allShots = [];
  List<ShotResult> _lastSeriesShots = [];
  int? _selectedShotIndex;

  TrainSessionState get state => _state;
  TrainPreset? get selectedPreset => _preset;

  Profile? get activeProfile => _profile;
  int get seriesCount => _seriesCount;
  List<ShotResult> get currentSeriesShots => List.unmodifiable(_currentSeries);
  List<ShotResult> get allSeriesShots => List.unmodifiable(_allShots);

  /// Immutable snapshot of the most recently completed series, kept for the
  /// review scatter after END SERIES / END SESSION. Empty outside review.
  List<ShotResult> get lastSeriesShots => List.unmodifiable(_lastSeriesShots);
  int? get selectedShotIndex => _selectedShotIndex;

  void selectPreset({required TrainPreset preset, required Profile profile}) {
    if (_state != TrainSessionState.choices) return;
    _preset = preset;
    _profile = profile;
    _state = TrainSessionState.readySeries;
    notifyListeners();
  }

  /// Abandons the selected preset before a series starts and returns to the
  /// preset choices. An active series must remain protected from back actions.
  void returnToChoices() {
    if (_state != TrainSessionState.readySeries &&
        _state != TrainSessionState.reviewSeries &&
        _state != TrainSessionState.reviewSession) {
      return;
    }
    _state = TrainSessionState.choices;
    _preset = null;
    _profile = null;
    _seriesCount = 0;
    _allShots = [];
    _currentSeries = [];
    _lastSeriesShots = [];
    _selectedShotIndex = null;
    notifyListeners();
  }

  void startSeries() {
    if (_state != TrainSessionState.readySeries) return;
    _seriesCount++;
    _currentSeries = [];
    _lastSeriesShots = [];
    _selectedShotIndex = null;
    _state = TrainSessionState.activeSeries;
    notifyListeners();
  }

  List<ShotResult> endSeries() {
    if (_state != TrainSessionState.activeSeries) return const [];
    final completed = List<ShotResult>.from(_currentSeries);
    _allShots = [..._allShots, ...completed];
    _currentSeries = [];
    _lastSeriesShots = List<ShotResult>.from(completed);
    _selectedShotIndex = _lastSeriesShots.isEmpty
        ? null
        : _lastSeriesShots.length - 1;
    _state = TrainSessionState.reviewSeries;
    notifyListeners();
    return completed;
  }

  List<ShotResult> endSession() {
    if (_state == TrainSessionState.choices) return const [];

    // Earlier series are persisted by END SERIES. END SESSION only flushes
    // the currently active series so those saved rows are not duplicated.
    final completed = _state == TrainSessionState.activeSeries
        ? List<ShotResult>.from(_currentSeries)
        : const <ShotResult>[];

    final hasActiveShots = completed.isNotEmpty;
    _state = hasActiveShots
        ? TrainSessionState.reviewSession
        : TrainSessionState.choices;
    _preset = null;
    _profile = null;
    _seriesCount = 0;
    _allShots = [];
    _currentSeries = [];
    _lastSeriesShots = hasActiveShots ? completed : [];
    _selectedShotIndex = _lastSeriesShots.isEmpty
        ? null
        : _lastSeriesShots.length - 1;
    notifyListeners();
    return completed;
  }

  /// Acknowledges the current review screen: clears the scatter snapshot and
  /// returns to readySeries (series review) or choices (session review).
  /// No-op outside the review states.
  void confirmReview() {
    if (_state == TrainSessionState.reviewSeries) {
      _lastSeriesShots = [];
      _state = TrainSessionState.readySeries;
      notifyListeners();
    } else if (_state == TrainSessionState.reviewSession) {
      _lastSeriesShots = [];
      _state = TrainSessionState.choices;
      notifyListeners();
    }
  }

  void onShotDetected(ShotResult shot) {
    if (_state != TrainSessionState.activeSeries) return;
    _currentSeries = [..._currentSeries, shot];
    _selectedShotIndex = _currentSeries.length - 1;
    notifyListeners();
  }

  /// Selects the shot shown by the target/replay in the active series or in a
  /// series/session review. Ignored in states without a shot list or when the
  /// index is out of bounds.
  void selectShot(int index) {
    final List<ShotResult> shots;
    if (_state == TrainSessionState.activeSeries) {
      shots = _currentSeries;
    } else if (_state == TrainSessionState.reviewSeries ||
        _state == TrainSessionState.reviewSession) {
      shots = _lastSeriesShots;
    } else {
      return;
    }
    if (index < 0 || index >= shots.length) return;
    _selectedShotIndex = index;
    notifyListeners();
  }
}
