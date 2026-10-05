// Task: firmware v2 bypass of the legacy GET_VERSION query (ConnectionScreen).
//
// Test approach: full widget-level test of ConnectionScreen with injected
// providers (mocktail BluetoothProvider + SensorDataProvider, real
// SettingsProvider) and a mocked flutter_bluetooth_serial MethodChannel.
// This drives the real seam end-to-end (scan -> device card tap ->
// _connectDevice -> auth -> _checkFirmwareUpdate) instead of restructuring
// the screen to expose private methods. `_checkFirmwareUpdate` has exactly
// one caller, so the widget test covers both the null-version decision and
// "does not block navigation" in one place.
//
// Harness notes:
// - Only the `flutter_bluetooth_serial/methods` MethodChannel is mocked
//   (getBondedDevices returns the STASYS device). The discovery EventChannel
//   is intentionally NOT mocked: registering it alongside the methods mock
//   causes a flutter_test fake-async zone hang after the test body completes
//   (verified empirically: either mock alone works, both together hang;
//   runAsync drains do not help). Without it, startDiscovery fails with a
//   missing-plugin error, which the screen's own onError handler absorbs.
// - pump() + bounded duration pumps are used instead of pumpAndSettle()
//   because the scan button and connecting dialog show indeterminate
//   ProgressIndicators, which never settle.
// - Each test body wraps its flow in try/finally that flushes the screen's
//   pending timers (12s scan auto-stop, SnackBar durations) so a failing
//   assertion doesn't leave pending timers behind at teardown.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssa_app/providers/bluetooth_provider.dart';
import 'package:ssa_app/providers/sensor_data_provider.dart';
import 'package:ssa_app/providers/settings_provider.dart';
import 'package:ssa_app/screens/connection_screen.dart';
import 'package:ssa_app/widgets/calibration_flow.dart';

class _MockBluetoothProvider extends Mock implements BluetoothProvider {}

class _MockSensorDataProvider extends Mock implements SensorDataProvider {}

const _btMethodsChannel = MethodChannel('flutter_bluetooth_serial/methods');

void main() {
  setUpAll(() {
    registerFallbackValue(
      const BluetoothDevice(name: 'fallback', address: '00:00:00:00:00:00'),
    );
  });

  late _MockBluetoothProvider bt;
  late _MockSensorDataProvider sensor;
  late SettingsProvider settings;
  late GoRouter router;
  late List<String> routeLog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsProvider();

    sensor = _MockSensorDataProvider();
    when(() => sensor.setDemoMode(any())).thenReturn(null);
    when(() => sensor.addListener(any())).thenReturn(null);
    when(() => sensor.removeListener(any())).thenReturn(null);

    bt = _MockBluetoothProvider();
    when(() => bt.connectToDevice(any())).thenAnswer((_) async => true);
    when(() => bt.getFirmwareVersion()).thenAnswer((_) async => null);
    when(() => bt.isConnected).thenReturn(true);
    when(() => bt.isAuthenticated).thenReturn(true);
    when(() => bt.connectedDeviceName).thenReturn('STASYS V2');
    when(() => bt.addListener(any())).thenReturn(null);
    when(() => bt.removeListener(any())).thenReturn(null);

    routeLog = <String>[];
    router = GoRouter(
      initialLocation: '/connection',
      routes: [
        GoRoute(
          path: '/connection',
          builder: (context, state) {
            routeLog.add('/connection');
            return const ConnectionScreen();
          },
        ),
        GoRoute(
          path: '/train',
          builder: (context, state) {
            routeLog.add('/train');
            return const Scaffold(body: Text('TRAIN_SCREEN'));
          },
        ),
      ],
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_btMethodsChannel, (call) async {
      switch (call.method) {
        case 'getBondedDevices':
          // Lowercased filter in the screen requires 'stasys' in the name.
          return [
            {
              'name': 'STASYS-V2',
              'address': '00:11:22:33:44:55',
              'type': 1,
              'isConnected': false,
              'bondState': 12, // bonded
            },
          ];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_btMethodsChannel, null);
    router.dispose();
    settings.dispose();
  });

  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<SensorDataProvider>.value(value: sensor),
          ChangeNotifierProvider<BluetoothProvider>.value(value: bt),
        ],
        child: MaterialApp.router(routerConfig: router),
      );

  Future<void> connectToBondedDevice(WidgetTester tester) async {
    await tester.pumpWidget(app());
    // Bounded pumps instead of pumpAndSettle: indeterminate
    // ProgressIndicators (scan button, connecting dialog) never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('CONNECT TO STASYS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('STASYS-V2'), findsOneWidget);

    await tester.tap(find.text('STASYS-V2'));
    // Flush: connect future, dialog pop, firmware version check chain.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Flush timers the screen schedules (12s scan auto-stop, SnackBar
  /// durations) so a failing assertion doesn't leave pending timers behind
  /// and hang teardown until the test timeout.
  Future<void> flushPendingTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 13));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
      'null firmware version proceeds to calibration and navigation '
      'instead of blocking with GET_VERSION error', (tester) async {
    // getFirmwareVersion() is stubbed to null in setUp: firmware v2 has no
    // legacy GET_VERSION command.
    try {
      await connectToBondedDevice(tester);

      // Connecting dialog dismissed after auth.
      expect(find.text('CONNECTING'), findsNothing);

      // The legacy version-query error must NOT block the flow — asserted
      // first so a RED failure names the blocking SnackBar explicitly.
      expect(find.textContaining('Gagal membaca versi firmware'), findsNothing);

      // Flow proceeds to the calibration dialog (does NOT block).
      expect(find.byType(CalibrationFlowDialog), findsOneWidget);
      // Dialog contains 'CALIBRATE' twice (title + button) -> findsWidgets.
      expect(find.text('CALIBRATE'), findsWidgets);

      // Navigation is not blocked: complete calibration -> /train.
      await tester.tap(find.text('MATCHED'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('CONFIRM'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(routeLog, contains('/train'));
      expect(find.text('TRAIN_SCREEN'), findsOneWidget);
    } finally {
      await flushPendingTimers(tester);
    }
  });

  testWidgets('auth failure surfaces authError in a SnackBar', (tester) async {
    when(() => bt.connectToDevice(any())).thenAnswer((_) async => false);
    when(() => bt.isConnected).thenReturn(false);
    when(() => bt.isAuthenticated).thenReturn(false);
    when(() => bt.authError).thenReturn('Authentication timed out.');

    try {
      await connectToBondedDevice(tester);

      // Connecting dialog dismissed, calibration NOT shown, authError readable.
      expect(find.text('CONNECTING'), findsNothing);
      expect(find.byType(CalibrationFlowDialog), findsNothing);
      expect(find.text('Authentication timed out.'), findsOneWidget);
    } finally {
      await flushPendingTimers(tester);
    }
  });

  testWidgets('auth failure without authError shows generic message',
      (tester) async {
    when(() => bt.connectToDevice(any())).thenAnswer((_) async => false);
    when(() => bt.isConnected).thenReturn(false);
    when(() => bt.isAuthenticated).thenReturn(false);
    when(() => bt.authError).thenReturn(null);

    try {
      await connectToBondedDevice(tester);

      expect(find.text('CONNECTING'), findsNothing);
      expect(find.byType(CalibrationFlowDialog), findsNothing);
      expect(find.text('Connection failed.'), findsOneWidget);
    } finally {
      await flushPendingTimers(tester);
    }
  });
}
