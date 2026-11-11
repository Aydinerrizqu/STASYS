import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/providers/session_logger.dart';
import 'package:ssa_app/providers/session_provider.dart';
import 'package:ssa_app/providers/settings_provider.dart';
import 'package:ssa_app/screens/session_detail_screen.dart';
import 'package:ssa_app/widgets/analysis_tab.dart';
import 'package:ssa_app/widgets/replay_shot_widget.dart';
import 'package:ssa_app/widgets/shot_replay_controls.dart';

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
    holdX: const [0.0, 0.001],
    holdY: const [0.0, 0.001],
    pressX: const [0.001, 0.002],
    pressY: const [0.001, 0.002],
    recoilX: const [0.002, 0.003],
    recoilY: const [0.002, 0.003],
  );
}

SessionLog _session() {
  return SessionLog(
    id: 'layout-test',
    date: DateTime(2026, 8, 23),
    duration: 5,
    gyroX: const [],
    gyroY: const [],
    gyroZ: const [],
    accelX: const [],
    accelY: const [],
    accelZ: const [],
    shots: [
      _shot(timestamp: DateTime(2026, 8, 23, 12), score: 80),
      _shot(timestamp: DateTime(2026, 8, 23, 12, 1), score: 92),
    ],
  );
}

/// A session with two series: series 1 owns two shots, series 2 owns one.
SessionLog _multiSeriesSession() {
  return SessionLog(
    id: 'multi-series-default',
    date: DateTime(2026, 8, 23),
    duration: 5,
    gyroX: const [],
    gyroY: const [],
    gyroZ: const [],
    accelX: const [],
    accelY: const [],
    accelZ: const [],
    shots: [
      _shot(timestamp: DateTime(2026, 8, 23, 12), score: 80, seriesNumber: 1),
      _shot(
        timestamp: DateTime(2026, 8, 23, 12, 1),
        score: 88,
        seriesNumber: 1,
      ),
      _shot(
        timestamp: DateTime(2026, 8, 23, 12, 2),
        score: 92,
        seriesNumber: 2,
      ),
    ],
  );
}

/// A session whose series numbers have a gap: series 2 owns no shot.
SessionLog _seriesWithGapSession() {
  return SessionLog(
    id: 'series-gap',
    date: DateTime(2026, 8, 23),
    duration: 5,
    gyroX: const [],
    gyroY: const [],
    gyroZ: const [],
    accelX: const [],
    accelY: const [],
    accelZ: const [],
    shots: [
      _shot(timestamp: DateTime(2026, 8, 23, 12), score: 80, seriesNumber: 1),
      _shot(
        timestamp: DateTime(2026, 8, 23, 12, 2),
        score: 92,
        seriesNumber: 3,
      ),
    ],
  );
}

Widget _testApp({
  SessionLog? session,
  Brightness brightness = Brightness.light,
}) {
  return ChangeNotifierProvider<SettingsProvider>(
    create: (_) => SettingsProvider(),
    child: MaterialApp(
      theme: brightness == Brightness.light
          ? ThemeData.light()
          : ThemeData.dark(),
      home: SessionDetailScreen(session: session ?? _session()),
    ),
  );
}

class _MockSessionProvider extends Mock implements SessionProvider {}

class _RecordingNavigatorObserver extends NavigatorObserver {
  /// Names of the routes that were popped, in order.
  final List<String?> poppedRoutes = [];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    poppedRoutes.add(route.settings.name);
    super.didPop(route, previousRoute);
  }
}

/// Hosts the detail screen on a pushed route so `Navigator.pop` has
/// something to pop.
Widget _pushedApp({
  required SessionLog session,
  required SessionProvider sessionProvider,
  required NavigatorObserver observer,
  Brightness brightness = Brightness.light,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
      ChangeNotifierProvider<SessionProvider>.value(value: sessionProvider),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.light
          ? ThemeData.light()
          : ThemeData.dark(),
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: 'session-detail'),
                  builder: (_) => SessionDetailScreen(session: session),
                ),
              ),
              child: const Text('OPEN SESSION'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // SettingsProvider reads SharedPreferences on construction; mock the store
  // so its async load never fails mid-test with a MissingPluginException.
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    // mocktail needs a dummy instance to match `any()` against.
    registerFallbackValue(_session());
  });

  group('SessionDetailScreen single-page layout', () {
    testWidgets('shows no TARGET/SHOT DATA/ANALYSIS tab selector', (
      tester,
    ) async {
      await tester.pumpWidget(_testApp());
      await tester.pump();

      expect(find.text('TARGET'), findsNothing);
      expect(find.text('SHOT DATA'), findsNothing);
      expect(find.text('ANALYSIS'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders score, target and shot chips on one page', (
      tester,
    ) async {
      await tester.pumpWidget(_testApp());
      await tester.pump();

      expect(find.text('SCORE'), findsOneWidget);
      expect(find.text('MATCH TOTAL'), findsOneWidget);
      expect(find.byKey(const ValueKey('session-target')), findsOneWidget);
      expect(find.byKey(const ValueKey('shot-chip-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('shot-chip-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps score, target, replay and chips only — no shot data or '
        'analysis sections', (tester) async {
      await tester.pumpWidget(_testApp());
      await tester.pumpAndSettle();

      // Everything up to SHOTS IN SESSION stays on the page...
      expect(find.byKey(const ValueKey('session-target')), findsOneWidget);
      expect(find.byType(ShotReplayControls), findsOneWidget);
      expect(find.byKey(const ValueKey('shot-chip-1')), findsOneWidget);

      // ...and everything below the chip strip is removed.
      expect(find.byType(ReplayShotWidget), findsNothing);
      expect(find.byType(AnalysisTab), findsNothing);
      expect(find.text('NO IMU DATA AVAILABLE'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting the second shot updates the target score', (
      tester,
    ) async {
      await tester.pumpWidget(_testApp());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('shot-chip-0')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('target-score'))).data,
        '80',
      );

      await tester.tap(find.byKey(const ValueKey('shot-chip-1')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('target-score'))).data,
        '92',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty session shows NO SHOTS and no shot chips', (
      tester,
    ) async {
      SessionLog emptySession() => SessionLog(
        id: 'empty-test',
        date: DateTime(2026, 8, 23),
        duration: 5,
        gyroX: const [],
        gyroY: const [],
        gyroZ: const [],
        accelX: const [],
        accelY: const [],
        accelZ: const [],
      );
      await tester.pumpWidget(_testApp(session: emptySession()));
      await tester.pump();

      expect(find.text('NO SHOTS IN SESSION'), findsOneWidget);
      expect(find.byKey(const ValueKey('shot-chip-0')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('session swap via didUpdateWidget resets selection', (
      tester,
    ) async {
      final first = _session();
      final second = _session();
      await tester.pumpWidget(_testApp(session: first));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('shot-chip-0')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('target-score'))).data,
        '80',
      );

      await tester.pumpWidget(_testApp(session: second));
      await tester.pump();

      // Selection resets to the new session's last shot (score 92).
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('target-score'))).data,
        '92',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SessionDetailScreen multi-series', () {
    testWidgets('shows series chips and filters shots by series', (tester) async {
      final session = SessionLog(
        id: 'multi-series',
        date: DateTime(2026, 8, 23),
        duration: 5,
        gyroX: const [],
        gyroY: const [],
        gyroZ: const [],
        accelX: const [],
        accelY: const [],
        accelZ: const [],
        seriesCount: 2,
        shots: [
          ShotResult(
            timestamp: DateTime(2026, 8, 23, 12),
            totalScore: 80,
            holdScore: 79,
            pressScore: 78,
            recoilScore: 77,
            elevationScore: 76,
            windageScore: 75,
            travelDistance: 0.1,
            peakJerk: 1.0,
            firearmType: FirearmType.pistol,
            trainingMode: TrainingMode.dryFire,
            seriesNumber: 1,
            holdX: const [0.0, 0.001],
            holdY: const [0.0, 0.001],
            pressX: const [0.001, 0.002],
            pressY: const [0.001, 0.002],
            recoilX: const [0.002, 0.003],
            recoilY: const [0.002, 0.003],
          ),
          ShotResult(
            timestamp: DateTime(2026, 8, 23, 12, 1),
            totalScore: 92,
            holdScore: 91,
            pressScore: 90,
            recoilScore: 89,
            elevationScore: 88,
            windageScore: 87,
            travelDistance: 0.1,
            peakJerk: 1.0,
            firearmType: FirearmType.pistol,
            trainingMode: TrainingMode.dryFire,
            seriesNumber: 2,
            holdX: const [0.0, 0.001],
            holdY: const [0.0, 0.001],
            pressX: const [0.001, 0.002],
            pressY: const [0.001, 0.002],
            recoilX: const [0.002, 0.003],
            recoilY: const [0.002, 0.003],
          ),
        ],
      );

      await tester.pumpWidget(_testApp(session: session));
      await tester.pump();

      expect(find.byKey(const ValueKey('series-chip-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('series-chip-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('shot-chip-0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('series-chip-1')));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const ValueKey('target-score'))).data,
        '80',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens on the last series by default', (tester) async {
      await tester.pumpWidget(_testApp(session: _multiSeriesSession()));
      await tester.pump();

      // Series 2 holds the shot with the score 92.
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('target-score'))).data,
        '92',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the header statistics follow the selected series', (
      tester,
    ) async {
      await tester.pumpWidget(_testApp(session: _multiSeriesSession()));
      await tester.pump();

      // Series 2: one shot with a score of 92.
      expect(
        tester.widget<Text>(
          find.byKey(const ValueKey('session-detail-header-stats')),
        ).data,
        '1 shots — 92.0 avg',
      );

      await tester.tap(find.byKey(const ValueKey('series-chip-1')));
      await tester.pump();

      // Series 1: two shots, scores 80 and 88 → average 84.
      expect(
        tester.widget<Text>(
          find.byKey(const ValueKey('session-detail-header-stats')),
        ).data,
        '2 shots — 84.0 avg',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('only the shots of the selected series are listed', (
      tester,
    ) async {
      await tester.pumpWidget(_testApp(session: _multiSeriesSession()));
      await tester.pump();

      // Series 2 is selected: its single shot is the only chip.
      expect(find.byKey(const ValueKey('shot-chip-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('shot-chip-1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('series-chip-1')));
      await tester.pump();

      // Series 1 owns two shots.
      expect(find.byKey(const ValueKey('shot-chip-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('shot-chip-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a series without shots is not offered as a chip', (
      tester,
    ) async {
      await tester.pumpWidget(_testApp(session: _seriesWithGapSession()));
      await tester.pump();

      // Series 2 owns no shot, so it stays hidden even though the numbers
      // have a gap.
      expect(find.byKey(const ValueKey('series-chip-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('series-chip-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('series-chip-2')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('SessionDetailScreen theming', () {
    testWidgets('light theme keeps the score row readable', (tester) async {
      await tester.pumpWidget(_testApp(brightness: Brightness.light));
      await tester.pump();

      final scoreLabel = find.text('SCORE');
      expect(scoreLabel, findsOneWidget);
      final style = tester.widget<Text>(scoreLabel).style!;
      expect(style.color!.computeLuminance(), lessThan(0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme keeps the score row readable', (tester) async {
      await tester.pumpWidget(_testApp(brightness: Brightness.dark));
      await tester.pump();

      final scoreLabel = find.text('SCORE');
      expect(scoreLabel, findsOneWidget);
      final style = tester.widget<Text>(scoreLabel).style!;
      expect(style.color!.computeLuminance(), greaterThan(0.5));
      expect(tester.takeException(), isNull);
    });
  });

  group('SessionDetailScreen delete', () {
    testWidgets('HAPUS deletes the session and closes the detail page', (
      tester,
    ) async {
      final provider = _MockSessionProvider();
      final observer = _RecordingNavigatorObserver();
      final session = _session();
      when(() => provider.deleteSession(any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        _pushedApp(
          session: session,
          sessionProvider: provider,
          observer: observer,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('OPEN SESSION'));
      await tester.pumpAndSettle();

      // Open the delete dialog and confirm.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HAPUS'));
      await tester.pumpAndSettle();

      verify(() => provider.deleteSession(session)).called(1);
      // The dialog and the detail page are both popped.
      expect(observer.poppedRoutes, contains('session-detail'));
      expect(find.byType(SessionDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('SessionDetailScreen replay', () {
    testWidgets('play button animates the trace and reset restores it', (
      tester,
    ) async {
      await tester.pumpWidget(_testApp());
      await tester.pump();

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      double progress() => tester.widget<Slider>(slider).value;

      expect(progress(), 1.0);

      // Play: the controller animates from 0 to 1 over 2.5 s.
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(progress(), lessThan(1.0));
      expect(progress(), greaterThanOrEqualTo(0.0));

      // Pause stops the animation.
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      final paused = progress();
      await tester.pump(const Duration(milliseconds: 500));
      expect(progress(), paused);

      // Reset jumps back to the full trace.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(progress(), 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('seeking the slider updates the replay progress', (
      tester,
    ) async {
      await tester.pumpWidget(_testApp());
      await tester.pump();

      final slider = find.byType(Slider);
      await tester.drag(slider, const Offset(-200, 0));
      await tester.pump();

      expect(tester.widget<Slider>(slider).value, lessThan(1.0));
      expect(tester.takeException(), isNull);
    });
  });
}
