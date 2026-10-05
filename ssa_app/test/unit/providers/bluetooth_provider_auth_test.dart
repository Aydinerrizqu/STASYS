/// Auth failure-path tests for BluetoothProvider's v2 line state machine (I2).
///
/// The BT socket stream cannot be driven in a unit test without a connection
/// abstraction (explicitly out of scope), so the provider exposes two minimal
/// `@visibleForTesting` seams:
///   - `feedAuthData` feeds raw bytes into the exact `_handleTextData` state
///     machine the BT stream listener calls in production;
///   - `selectDeviceForAuth` injects the device identity used for proof
///     computation and flags the state machine as running outside a real
///     socket, so the post-`readKey` connection check (a teardown-race
///     guard) does not trip on the absent socket.
/// Everything else — DeviceKeyStore, line buffering, phase transitions,
/// `_failAuthentication` — runs the real implementation.

import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ssa_app/providers/bluetooth_provider.dart';
import 'package:ssa_app/providers/sensor_data_provider.dart';
import 'package:ssa_app/services/device_key_store.dart';

class _MockSensorDataProvider extends Mock implements SensorDataProvider {}

/// Map-backed fake backend (mirrors device_key_store_test) so tests never
/// touch platform secure storage. `throwOnRead` simulates secure-storage
/// failures (e.g. KeyStore unwrap errors after device restore).
class _FakeKeyBackend implements DeviceKeyBackend {
  _FakeKeyBackend({this.value, this.throwOnRead = false});

  String? value;
  final bool throwOnRead;

  @override
  Future<String?> read() async {
    if (throwOnRead) throw Exception('secure storage unavailable');
    return value;
  }

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> delete() async => value = null;
}

const _nonceHex = '000102030405060708090a0b0c0d0e0f'
    '101112131415161718191a1b1c1d1e1f';
const _validKeyHex = '00112233445566778899aabbccddeeff'
    '00112233445566778899aabbccddeeff';
const _greeting = 'READY v=2 gen=7\n';
const _nonceLine = 'AUTH $_nonceHex\n';

BluetoothProvider buildProvider(DeviceKeyStore store) {
  final provider = BluetoothProvider(
    sensorDataProvider: _MockSensorDataProvider(),
    deviceKeyStore: store,
  );
  provider.selectDeviceForAuth(
    const BluetoothDevice(address: '78:1c:3c:f5:16:18'),
  );
  return provider;
}

void main() {
  group('v2 auth failure diagnostics', () {
    test('missing device key fails with configured diagnostic', () async {
      final provider = buildProvider(
        DeviceKeyStore(backend: _FakeKeyBackend()),
      );

      await provider.feedAuthData(_greeting.codeUnits);
      await provider.feedAuthData(_nonceLine.codeUnits);

      expect(provider.isAuthenticated, isFalse);
      expect(provider.authError, 'Device key not configured.');
    });

    test('secure-storage read failure routes to readable diagnostic',
        () async {
      final provider = buildProvider(
        DeviceKeyStore(backend: _FakeKeyBackend(throwOnRead: true)),
      );

      await provider.feedAuthData(_greeting.codeUnits);
      await provider.feedAuthData(_nonceLine.codeUnits);

      expect(provider.isAuthenticated, isFalse);
      expect(
        provider.authError,
        'Authentication failed: Unable to read the device key or authenticate.',
      );
    });

    test('malformed greeting routes FormatException to diagnostic', () async {
      final provider = buildProvider(
        DeviceKeyStore(backend: _FakeKeyBackend(value: _validKeyHex)),
      );

      await provider.feedAuthData('READY v=9 gen=7\n'.codeUnits);

      expect(provider.isAuthenticated, isFalse);
      expect(provider.authError, 'Authentication failed: Unsupported firmware greeting');
    });

    test('FAIL response finalizes with rejected diagnostic', () async {
      final provider = buildProvider(
        DeviceKeyStore(backend: _FakeKeyBackend(value: _validKeyHex)),
      );

      await provider.feedAuthData(_greeting.codeUnits);
      await provider.feedAuthData(_nonceLine.codeUnits);
      await provider.feedAuthData('FAIL\n'.codeUnits);

      expect(provider.isAuthenticated, isFalse);
      expect(provider.authError, 'Device rejected authentication.');
    });

    test('OK response authenticates and clears a prior auth error',
        () async {
      final backend = _FakeKeyBackend(); // no key yet
      final provider = buildProvider(DeviceKeyStore(backend: backend));

      // First attempt fails definitively with the missing-key diagnostic.
      await provider.feedAuthData(_greeting.codeUnits);
      await provider.feedAuthData(_nonceLine.codeUnits);
      expect(provider.authError, 'Device key not configured.');

      // Key becomes available; auth succeeds on the next exchange.
      backend.value = _validKeyHex;
      await provider.feedAuthData(_nonceLine.codeUnits);
      await provider.feedAuthData('OK\n'.codeUnits);

      expect(provider.isAuthenticated, isTrue);
      expect(provider.authError, isNull);
    });
  });
}
