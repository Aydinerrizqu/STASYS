import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssa_app/providers/settings_provider.dart';

void main() {
  group('SettingsProvider theme mode', () {
    test('defaults to dark mode', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SettingsProvider();
      await provider.load();

      expect(provider.themeMode, ThemeMode.dark);
    });

    test('loads and saves light mode', () async {
      SharedPreferences.setMockInitialValues({'themeMode': 'light'});
      final provider = SettingsProvider();
      await provider.load();

      expect(provider.themeMode, ThemeMode.light);

      await provider.setThemeMode(ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themeMode'), 'dark');
    });

    test('unknown persisted value falls back to dark mode', () async {
      SharedPreferences.setMockInitialValues({'themeMode': 'sepia'});
      final provider = SettingsProvider();
      await provider.load();

      expect(provider.themeMode, ThemeMode.dark);
    });
  });
}
