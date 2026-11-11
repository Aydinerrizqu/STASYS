import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/providers/session_logger.dart';
import 'package:ssa_app/providers/session_provider.dart';
import 'package:ssa_app/providers/settings_provider.dart';
import 'package:ssa_app/screens/history_screen.dart';

class _MockSessionProvider extends Mock implements SessionProvider {}

class _MockSettingsProvider extends Mock implements SettingsProvider {}

ShotResult _shot({
  required DateTime timestamp,
  required double score,
  int seriesNumber = 1,
}) {
  return ShotResult(
    timestamp: timestamp,
    totalScore: score,
    holdScore: score - 1,
    pressScore: score - 2,
    recoilScore: score - 3,
    elevationScore: score - 4,
    windageScore: score - 5,
    travelDistance: 0.1,
    peakJerk: 1.0,
    firearmType: FirearmType.pistol,
    trainingMode: TrainingMode.dryFire,
    seriesNumber: seriesNumber,
  );
}

SessionLog _session() => SessionLog(
  id: 'history-test',
  date: DateTime(2026, 8, 23, 14, 30),
  duration: 120,
  gyroX: const [],
  gyroY: const [],
  gyroZ: const [],
  accelX: const [],
  accelY: const [],
  accelZ: const [],
  firearmType: FirearmType.pistol,
  trainingMode: TrainingMode.dryFire,
  shots: [
    _shot(timestamp: DateTime(2026, 8, 23, 14, 30), score: 80),
    _shot(timestamp: DateTime(2026, 8, 23, 14, 31), score: 92),
  ],
);

SessionLog _multiSeriesSession() => SessionLog(
  id: 'history-multi-series',
  date: DateTime(2026, 8, 23, 14, 30),
  duration: 120,
  gyroX: const [],
  gyroY: const [],
  gyroZ: const [],
  accelX: const [],
  accelY: const [],
  accelZ: const [],
  firearmType: FirearmType.pistol,
  trainingMode: TrainingMode.dryFire,
  shots: [
    _shot(timestamp: DateTime(2026, 8, 23, 14, 30), score: 80),
    _shot(
      timestamp: DateTime(2026, 8, 23, 14, 31),
      score: 92,
      seriesNumber: 2,
    ),
  ],
);

Widget _app(
  _MockSessionProvider sessions,
  _MockSettingsProvider settings, {
  Brightness brightness = Brightness.light,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionProvider>.value(value: sessions),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.light
          ? ThemeData.light()
          : ThemeData.dark(),
      home: const HistoryScreen(),
    ),
  );
}

/// WCAG relative-luminance contrast ratio between two opaque colors.
double _contrastRatio(Color a, Color b) {
  // Flutter's Color.r/g/b are already normalized to 0..1.
  double channel(double v) {
    return v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);
  }

  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.0722 * channel(c.g) + 0.7152 * channel(c.b);

  final l1 = luminance(a);
  final l2 = luminance(b);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Composite a possibly translucent foreground over an opaque background.
Color _flatten(Color foreground, Color background) {
  final alpha = foreground.a;
  return Color.from(
    alpha: 1,
    red: foreground.r * alpha + background.r * (1 - alpha),
    green: foreground.g * alpha + background.g * (1 - alpha),
    blue: foreground.b * alpha + background.b * (1 - alpha),
  );
}

/// Contrast of [foreground] as rendered on top of [background].
double _renderedContrast(Color foreground, Color background) =>
    _contrastRatio(_flatten(foreground, background), background);

double _pow(double base, double exponent) {
  // exp(exponent * ln(base)) with a Taylor series for both primitives.
  var result = 1.0;
  var term = 1.0;
  final x = exponent * _ln(base);
  for (var i = 1; i < 40; i++) {
    term *= x / i;
    result += term;
  }
  return result;
}

double _ln(double x) {
  // ln(x) = 2 * atanh((x - 1) / (x + 1))
  final z = (x - 1) / (x + 1);
  final z2 = z * z;
  var term = z;
  var sum = 0.0;
  for (var i = 0; i < 80; i++) {
    sum += term / (2 * i + 1);
    term *= z2;
  }
  return 2 * sum;
}

void main() {
  late _MockSessionProvider sessions;
  late _MockSettingsProvider settings;

  setUpAll(() {
    registerFallbackValue(_session());
  });

  setUp(() {
    sessions = _MockSessionProvider();
    settings = _MockSettingsProvider();
    when(() => sessions.sessions).thenReturn([_session()]);
    when(() => sessions.loadSessions()).thenAnswer((_) async {});
    when(() => sessions.deleteSession(any())).thenAnswer((_) async {});
    when(() => settings.isDemoMode).thenReturn(false);
    when(() => settings.themeMode).thenReturn(ThemeMode.light);
  });

  group('History session card legibility', () {
    testWidgets('light theme keeps the firearm label readable on its chip',
        (tester) async {
      await tester.pumpWidget(_app(sessions, settings));
      await tester.pumpAndSettle();

      final label = find.byKey(const ValueKey('history-firearm-label'));
      expect(label, findsOneWidget);

      final text = tester.widget<Text>(label);
      final chip = tester.widget<Container>(
        find
            .ancestor(of: label, matching: find.byType(Container))
            .first,
      );
      final bg = (chip.decoration! as BoxDecoration).color!;

      expect(
        _renderedContrast(text.style!.color!, bg),
        greaterThanOrEqualTo(4.5),
        reason: 'firearm label must stay readable in light theme',
      );
    });

    testWidgets('light theme keeps the shot count readable on its chip',
        (tester) async {
      await tester.pumpWidget(_app(sessions, settings));
      await tester.pumpAndSettle();

      final count = find.byKey(const ValueKey('history-shot-count'));
      expect(count, findsOneWidget);

      final text = tester.widget<Text>(count);
      final chip = tester.widget<Container>(
        find.ancestor(of: count, matching: find.byType(Container)).first,
      );
      final bg = (chip.decoration! as BoxDecoration).color!;

      expect(
        _renderedContrast(text.style!.color!, bg),
        greaterThanOrEqualTo(4.5),
        reason: 'shot count must stay readable in light theme',
      );
    });

    testWidgets('dark theme keeps the firearm label readable on its chip',
        (tester) async {
      await tester.pumpWidget(
        _app(sessions, settings, brightness: Brightness.dark),
      );
      await tester.pumpAndSettle();

      final label = find.byKey(const ValueKey('history-firearm-label'));
      final text = tester.widget<Text>(label);
      final chip = tester.widget<Container>(
        find.ancestor(of: label, matching: find.byType(Container)).first,
      );
      final bg = (chip.decoration! as BoxDecoration).color!;

      expect(
        _renderedContrast(text.style!.color!, bg),
        greaterThanOrEqualTo(4.5),
        reason: 'firearm label must stay readable in dark theme',
      );
    });

    testWidgets('shows a series badge for a multi-series session', (
      tester,
    ) async {
      when(() => sessions.sessions).thenReturn([_multiSeriesSession()]);
      await tester.pumpWidget(_app(sessions, settings));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('history-series-count')),
        findsOneWidget,
      );
      expect(find.text('2 SERIES'), findsOneWidget);
    });

    testWidgets('hides the series badge for a single-series session', (
      tester,
    ) async {
      await tester.pumpWidget(_app(sessions, settings));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('history-series-count')), findsNothing);
    });
  });
}
