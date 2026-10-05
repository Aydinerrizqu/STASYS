import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/services/device_key_store.dart';
import 'package:ssa_app/widgets/device_key_section.dart';

/// Map-backed fake backend so tests never touch platform secure storage.
class _MapKeyBackend implements DeviceKeyBackend {
  String? value;
  bool failWrite = false;
  bool failDelete = false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String key) async {
    if (failWrite) throw Exception('secure storage unavailable');
    value = key;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw Exception('secure storage unavailable');
    value = null;
  }
}

void main() {
  const hexLower =
      '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
  const hexUpper =
      '00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF';
  const invalidLength = 'abc123';
  const nonHex64 = 'gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg';

  late _MapKeyBackend backend;

  Widget buildSection({DeviceKeyStore? keyStore}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DeviceKeySection(keyStore: keyStore),
        ),
      ),
    );
  }

  setUp(() {
    backend = _MapKeyBackend();
  });

  testWidgets(
      'shows DEVICE KEY header and prompts for entry when no key stored',
      (tester) async {
    await tester.pumpWidget(
        buildSection(keyStore: DeviceKeyStore(backend: backend)));
    await tester.pumpAndSettle();

    expect(find.text('DEVICE KEY'), findsOneWidget);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue,
        reason: 'secret input must be obscured by default');
    expect(find.text('SAVE'), findsOneWidget);
  });

  testWidgets('show/hide toggle reveals and re-obscures the input',
      (tester) async {
    await tester.pumpWidget(
        buildSection(keyStore: DeviceKeyStore(backend: backend)));
    await tester.pumpAndSettle();

    expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
  });

  testWidgets('saves valid 64-hex key as lowercase and masks it in the UI',
      (tester) async {
    await tester.pumpWidget(
        buildSection(keyStore: DeviceKeyStore(backend: backend)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), hexUpper);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(backend.value, hexLower,
        reason: 'backend must receive the lowercase-normalized value');
    expect(find.text('CONFIGURED'), findsOneWidget);
    expect(find.byType(TextField), findsNothing,
        reason: 'entry field is replaced by the confirmed state');
    expect(find.text(hexLower), findsNothing,
        reason: 'the secret must never be displayed');
    expect(find.text(hexUpper), findsNothing);
    expect(find.text('REMOVE'), findsOneWidget);
  });

  testWidgets('rejects invalid length with inline error and does not write',
      (tester) async {
    await tester.pumpWidget(
        buildSection(keyStore: DeviceKeyStore(backend: backend)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), invalidLength);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(find.text('Device key must be exactly 64 hex characters.'),
        findsOneWidget);
    expect(backend.value, isNull);
    expect(find.text('CONFIGURED'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        invalidLength,
        reason: 'invalid text is kept so the user can correct it');
  });

  testWidgets('rejects non-hex input with inline error and does not write',
      (tester) async {
    await tester.pumpWidget(
        buildSection(keyStore: DeviceKeyStore(backend: backend)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), nonHex64);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(find.text('Device key must be exactly 64 hex characters.'),
        findsOneWidget);
    expect(backend.value, isNull);
  });

  testWidgets('loads an existing key as CONFIGURED without revealing it',
      (tester) async {
    backend.value = hexLower;
    await tester.pumpWidget(
        buildSection(keyStore: DeviceKeyStore(backend: backend)));
    await tester.pumpAndSettle();

    expect(find.text('CONFIGURED'), findsOneWidget);
    expect(find.text(hexLower), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('REMOVE'), findsOneWidget);
  });

  testWidgets('remove clears the backend and returns to entry state',
      (tester) async {
    backend.value = hexLower;
    await tester.pumpWidget(
        buildSection(keyStore: DeviceKeyStore(backend: backend)));
    await tester.pumpAndSettle();
    expect(find.text('CONFIGURED'), findsOneWidget);

    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle();

    expect(backend.value, isNull);
    expect(find.text('CONFIGURED'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'removed key must not be re-echoed in the entry field',
    );
    expect(find.text('SAVE'), findsOneWidget);
  });

  testWidgets('save failure shows a SnackBar and keeps the entered text',
      (tester) async {
    backend.failWrite = true;
    await tester.pumpWidget(
        buildSection(keyStore: DeviceKeyStore(backend: backend)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), hexLower);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(find.text('Could not save device key.'), findsOneWidget);
    expect(backend.value, isNull);
    expect(find.text(hexLower), findsOneWidget,
        reason: 'text is kept so the user can retry');
    expect(find.text('CONFIGURED'), findsNothing);
  });

  testWidgets('remove failure shows a SnackBar and keeps the key',
      (tester) async {
    backend.value = hexLower;
    backend.failDelete = true;
    await tester.pumpWidget(
        buildSection(keyStore: DeviceKeyStore(backend: backend)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle();

    expect(find.text('Could not remove device key.'), findsOneWidget);
    expect(backend.value, hexLower);
    expect(find.text('CONFIGURED'), findsOneWidget);
  });
}
