import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/profile_service.dart';

class ProfileProvider extends ChangeNotifier {
  final ProfileService _service;

  List<Profile> _profiles = [];
  Profile? _activeProfile;

  ProfileProvider({ProfileService? service})
    : _service = service ?? ProfileService();

  List<Profile> get profiles => List.unmodifiable(_profiles);
  Profile? get activeProfile => _activeProfile;

  Future<void> load() async {
    _profiles = await _service.loadProfiles();
    notifyListeners();
  }

  Future<Profile> createProfile(String name) async {
    final profile = Profile(name);
    await _service.saveProfile(profile);
    _profiles = await _service.loadProfiles();
    notifyListeners();
    return profile;
  }

  void selectProfile(Profile profile) {
    _activeProfile = profile;
    notifyListeners();
  }

  void clearActiveProfile() {
    if (_activeProfile == null) return;
    _activeProfile = null;
    notifyListeners();
  }

  /// Called when Bluetooth connection resets to clear the active selection
  /// without losing persisted profiles.
  void onConnectionReset() {
    clearActiveProfile();
  }
}
