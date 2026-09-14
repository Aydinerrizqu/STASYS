import 'package:flutter/foundation.dart';
import 'data_models.dart';

@immutable
class TrainPreset {
  final String id;
  final TrainingMode trainingMode;
  final FirearmType firearmType;
  final String weaponLabel;
  final int distanceMeters;
  final String displayTitle;

  const TrainPreset({
    required this.id,
    required this.trainingMode,
    required this.firearmType,
    required this.weaponLabel,
    required this.distanceMeters,
    required this.displayTitle,
  });

  static const List<TrainPreset> all = [
    TrainPreset(
      id: 'dry-air-softgun-10',
      trainingMode: TrainingMode.dryFire,
      firearmType: FirearmType.pistol,
      weaponLabel: 'Air Softgun',
      distanceMeters: 10,
      displayTitle: 'Dry Air Softgun 10m',
    ),
    TrainPreset(
      id: 'live-air-pistol-10',
      trainingMode: TrainingMode.liveFire,
      firearmType: FirearmType.pistol,
      weaponLabel: 'Air Pistol',
      distanceMeters: 10,
      displayTitle: 'Live Air Pistol 10m',
    ),
    TrainPreset(
      id: 'live-air-rifle-10',
      trainingMode: TrainingMode.liveFire,
      firearmType: FirearmType.rifle,
      weaponLabel: 'Air Rifle',
      distanceMeters: 10,
      displayTitle: 'Live Air Rifle 10m',
    ),
    TrainPreset(
      id: 'live-rifle-50',
      trainingMode: TrainingMode.liveFire,
      firearmType: FirearmType.rifle,
      weaponLabel: 'Rifle',
      distanceMeters: 50,
      displayTitle: 'Live Rifle 50m',
    ),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainPreset &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          trainingMode == other.trainingMode &&
          firearmType == other.firearmType &&
          weaponLabel == other.weaponLabel &&
          distanceMeters == other.distanceMeters &&
          displayTitle == other.displayTitle;

  @override
  int get hashCode => Object.hash(
    id,
    trainingMode,
    firearmType,
    weaponLabel,
    distanceMeters,
    displayTitle,
  );

  @override
  String toString() =>
      'TrainPreset($id, $trainingMode, $firearmType, $weaponLabel, ${distanceMeters}m)';
}
