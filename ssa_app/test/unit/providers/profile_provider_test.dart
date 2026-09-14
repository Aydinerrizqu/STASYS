import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/profile.dart';
import 'package:ssa_app/providers/profile_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Profile model', () {
    test('creates with valid name', () {
      final p = Profile('Alice');
      expect(p.name, 'Alice');
      expect(p.trimmedName, 'Alice');
    });

    test('trims whitespace in trimmedName', () {
      final p = Profile('  Bob  ');
      expect(p.trimmedName, 'Bob');
    });

    test('throws ArgumentError for empty name', () {
      expect(() => Profile(''), throwsArgumentError);
    });

    test('throws ArgumentError for whitespace-only name', () {
      expect(() => Profile('   '), throwsArgumentError);
    });

    test('equality uses trimmedName', () {
      expect(Profile(' Alice '), equals(Profile('Alice')));
    });

    test('toString contains trimmed name', () {
      expect(Profile('Alice').toString(), contains('Alice'));
    });
  });

  group('ProfileProvider', () {
    late ProfileProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      provider = ProfileProvider();
      await provider.load();
    });

    test('starts with empty profiles', () {
      expect(provider.profiles, isEmpty);
      expect(provider.activeProfile, isNull);
    });

    test('createProfile adds a persisted profile', () async {
      final profile = await provider.createProfile('Shooter One');
      expect(profile.name, 'Shooter One');
      expect(provider.profiles.length, 1);
      expect(provider.profiles.first.trimmedName, 'Shooter One');
    });

    test('createProfile persists across load', () async {
      await provider.createProfile('Shooter One');
      final freshProvider = ProfileProvider();
      await freshProvider.load();
      expect(freshProvider.profiles.length, 1);
      expect(freshProvider.profiles.first.trimmedName, 'Shooter One');
    });

    test('createProfile does not duplicate same name', () async {
      await provider.createProfile('Shooter One');
      await provider.createProfile('Shooter One');
      expect(provider.profiles.length, 1);
    });

    test('selectProfile sets activeProfile', () async {
      final profile = await provider.createProfile('Shooter One');
      provider.selectProfile(profile);
      expect(provider.activeProfile, profile);
    });

    test('clearActiveProfile resets active', () async {
      final profile = await provider.createProfile('Shooter One');
      provider.selectProfile(profile);
      provider.clearActiveProfile();
      expect(provider.activeProfile, isNull);
    });

    test('clearActiveProfile is no-op when already null', () {
      provider.clearActiveProfile(); // should not throw
      expect(provider.activeProfile, isNull);
    });

    test('onConnectionReset clears active but keeps profiles', () async {
      final profile = await provider.createProfile('Shooter One');
      provider.selectProfile(profile);
      provider.onConnectionReset();
      expect(provider.activeProfile, isNull);
      expect(provider.profiles.length, 1);
    });

    test('profiles list is unmodifiable', () async {
      await provider.createProfile('Shooter One');
      expect(() => provider.profiles.add(Profile('X')), throwsUnsupportedError);
    });

    test('selectProfile notifies listeners', () async {
      var notified = false;
      provider.addListener(() => notified = true);
      final profile = await provider.createProfile('Shooter One');
      notified = false; // reset after createProfile notification
      provider.selectProfile(profile);
      expect(notified, isTrue);
    });

    test('clearActiveProfile notifies listeners', () async {
      final profile = await provider.createProfile('Shooter One');
      provider.selectProfile(profile);
      var notified = false;
      provider.addListener(() => notified = true);
      provider.clearActiveProfile();
      expect(notified, isTrue);
    });
  });
}
