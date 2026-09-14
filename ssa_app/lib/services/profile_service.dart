import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';

class ProfileService {
  static const _profilesKey = 'profiles';

  Future<List<Profile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((m) => Profile(m['name'] as String))
        .toList();
  }

  Future<void> saveProfile(Profile profile) async {
    final profiles = await loadProfiles();
    if (profiles.any((p) => p.trimmedName == profile.trimmedName)) {
      return;
    }
    profiles.add(profile);
    await _persistAll(profiles);
  }

  Future<void> deleteProfile(String name) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p.trimmedName == name.trim());
    await _persistAll(profiles);
  }

  Future<void> _persistAll(List<Profile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      profiles.map((p) => {'name': p.trimmedName}).toList(),
    );
    await prefs.setString(_profilesKey, encoded);
  }
}
