import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/train_preset.dart';
import 'package:ssa_app/models/data_models.dart';

void main() {
  group('TrainPreset', () {
    test('all has exactly 4 presets', () {
      expect(TrainPreset.all.length, 4);
    });

    test('all preset ids are unique', () {
      final ids = TrainPreset.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('first preset is dry-air-softgun-10', () {
      final preset = TrainPreset.all[0];
      expect(preset.id, 'dry-air-softgun-10');
      expect(preset.trainingMode, TrainingMode.dryFire);
      expect(preset.firearmType, FirearmType.pistol);
      expect(preset.weaponLabel, 'Air Softgun');
      expect(preset.distanceMeters, 10);
      expect(preset.displayTitle, 'Dry Air Softgun 10m');
    });

    test('second preset is live-air-pistol-10', () {
      final preset = TrainPreset.all[1];
      expect(preset.id, 'live-air-pistol-10');
      expect(preset.trainingMode, TrainingMode.liveFire);
      expect(preset.firearmType, FirearmType.pistol);
      expect(preset.weaponLabel, 'Air Pistol');
      expect(preset.distanceMeters, 10);
    });

    test('third preset is live-air-rifle-10', () {
      final preset = TrainPreset.all[2];
      expect(preset.id, 'live-air-rifle-10');
      expect(preset.trainingMode, TrainingMode.liveFire);
      expect(preset.firearmType, FirearmType.rifle);
      expect(preset.weaponLabel, 'Air Rifle');
      expect(preset.distanceMeters, 10);
    });

    test('fourth preset is live-rifle-50', () {
      final preset = TrainPreset.all[3];
      expect(preset.id, 'live-rifle-50');
      expect(preset.trainingMode, TrainingMode.liveFire);
      expect(preset.firearmType, FirearmType.rifle);
      expect(preset.weaponLabel, 'Rifle');
      expect(preset.distanceMeters, 50);
    });

    test('equality and hashCode are consistent', () {
      final a = TrainPreset.all[0];
      final b = TrainPreset(
        id: 'dry-air-softgun-10',
        trainingMode: TrainingMode.dryFire,
        firearmType: FirearmType.pistol,
        weaponLabel: 'Air Softgun',
        distanceMeters: 10,
        displayTitle: 'Dry Air Softgun 10m',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality for different presets', () {
      expect(TrainPreset.all[0], isNot(equals(TrainPreset.all[1])));
    });

    test('toString contains id and weaponLabel', () {
      final str = TrainPreset.all[0].toString();
      expect(str, contains('dry-air-softgun-10'));
      expect(str, contains('Air Softgun'));
    });
  });
}
