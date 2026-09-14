import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ssa_app/widgets/calibration_flow.dart';
import 'package:ssa_app/providers/sensor_data_provider.dart';

class MockSensorDataProvider extends Mock implements SensorDataProvider {}

void main() {
  late MockSensorDataProvider mockSensor;

  setUp(() {
    mockSensor = MockSensorDataProvider();
    when(() => mockSensor.resetAxis()).thenReturn(null);
    when(() => mockSensor.addListener(any())).thenReturn(null);
    when(() => mockSensor.removeListener(any())).thenReturn(null);
  });

  Widget buildDialog() {
    return MaterialApp(
      home: ChangeNotifierProvider<SensorDataProvider>.value(
        value: mockSensor,
        child: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) =>
                        ChangeNotifierProvider<SensorDataProvider>.value(
                          value: mockSensor,
                          child: const CalibrationFlowDialog(),
                        ),
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
  }

  group('CalibrationFlowDialog', () {
    testWidgets('Phase 1 shows direction check with title and buttons', (
      tester,
    ) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Title "CALIBRATE" and button "CALIBRATE" both render
      expect(find.text('CALIBRATE'), findsNWidgets(2));
      expect(find.text('MATCHED'), findsOneWidget);
      expect(find.text('MOUNT STASYS'), findsNothing);
      expect(find.text('CONFIRM'), findsNothing);
    });

    testWidgets('CALIBRATE button calls resetAxis and stays in Phase 1', (
      tester,
    ) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tap the CALIBRATE button (second of the two "CALIBRATE" texts)
      await tester.tap(find.text('CALIBRATE').last);
      verify(() => mockSensor.resetAxis()).called(1);
      // Still on phase 1
      expect(find.text('MATCHED'), findsOneWidget);
      expect(find.text('MOUNT STASYS'), findsNothing);
    });

    testWidgets('MATCHED advances to Phase 2 mount confirmation', (
      tester,
    ) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('MATCHED'));
      await tester.pumpAndSettle();

      expect(find.text('MOUNT STASYS'), findsOneWidget);
      expect(find.text('CONFIRM'), findsOneWidget);
      // Phase 1 elements gone
      expect(find.text('CALIBRATE'), findsNothing);
      expect(find.text('MATCHED'), findsNothing);
    });

    testWidgets('CONFIRM pops dialog', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Phase 1 -> Phase 2
      await tester.tap(find.text('MATCHED'));
      await tester.pumpAndSettle();

      // Phase 2 -> confirm (dialog pops)
      await tester.tap(find.text('CONFIRM'));
      await tester.pumpAndSettle();

      // Dialog dismissed
      expect(find.text('MOUNT STASYS'), findsNothing);
      expect(find.text('CONFIRM'), findsNothing);
    });
  });
}
