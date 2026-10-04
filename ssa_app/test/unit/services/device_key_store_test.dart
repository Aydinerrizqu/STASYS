import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/services/device_key_store.dart';

/// Map-backed fake backend so tests never touch platform secure storage.
class _MapKeyBackend implements DeviceKeyBackend {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String key) async => value = key;

  @override
  Future<void> delete() async => value = null;
}

void main() {
  const hexA =
      '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
  const hexB =
      'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';
  // hexA is '001122...ff' repeated: byte i = (i % 16) * 0x11
  final bytesA = Uint8List.fromList(List<int>.generate(32, (i) => (i % 16) * 0x11));

  late _MapKeyBackend backend;
  late DeviceKeyStore store;

  setUp(() {
    backend = _MapKeyBackend();
    store = DeviceKeyStore(backend: backend);
  });

  group('DeviceKeyStore', () {
    test('readKey returns null when no key is stored', () async {
      expect(await store.readKey(), isNull);
    });

    test('saveKey normalizes to lowercase and roundtrips as 32 bytes',
        () async {
      await store.saveKey(hexA.toUpperCase());
      expect(backend.value, hexA);
      final key = await store.readKey();
      expect(key, isNotNull);
      expect(key!.length, 32);
      expect(key, bytesA);
    });

    test('saveKey rejects a key that is not exactly 64 hex chars', () async {
      await expectLater(
          store.saveKey(hexA.substring(0, 62)), throwsA(isA<FormatException>()));
      expect(backend.value, isNull);
    });

    test('saveKey rejects non-hex input', () async {
      final bad = 'g' * 64;
      await expectLater(store.saveKey(bad), throwsA(isA<FormatException>()));
      expect(backend.value, isNull);
    });

    test('saveKey replaces an existing key', () async {
      await store.saveKey(hexA);
      await store.saveKey(hexB);
      expect(backend.value, hexB);
      expect(await store.readKey(), isNot(equals(bytesA)));
      expect(await store.readKey(), isNotNull);
      expect((await store.readKey())!.length, 32);
    });

    test('deleteKey removes the stored key', () async {
      await store.saveKey(hexA);
      await store.deleteKey();
      expect(backend.value, isNull);
      expect(await store.readKey(), isNull);
    });
  });

  group('DeviceKeyStore.parseHexKey', () {
    test('parses a valid 64-char hex key into 32 bytes', () {
      final parsed = DeviceKeyStore.parseHexKey(hexA);
      expect(parsed.length, 32);
      expect(parsed, bytesA);
    });

    test('throws FormatException on wrong length', () {
      expect(() => DeviceKeyStore.parseHexKey('abc'),
          throwsA(isA<FormatException>()));
      expect(() => DeviceKeyStore.parseHexKey('${hexA}00'),
          throwsA(isA<FormatException>()));
    });

    test('throws FormatException on non-hex chars', () {
      expect(() => DeviceKeyStore.parseHexKey('z' * 64),
          throwsA(isA<FormatException>()));
    });
  });
}
