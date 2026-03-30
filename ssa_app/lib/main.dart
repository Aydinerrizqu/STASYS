import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/sensor_data_provider.dart';
import 'providers/bluetooth_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/main_screen.dart';
import 'providers/session_logger.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => SessionLogger()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProxyProvider<SessionLogger, SessionProvider>(
          create: (context) => SessionProvider(
            logger: Provider.of<SessionLogger>(context, listen: false),
          ),
          update: (context, logger, previous) => SessionProvider(logger: logger),
        ),
        ChangeNotifierProxyProvider2<SettingsProvider, SessionLogger, SensorDataProvider>(
          create: (context) => SensorDataProvider(
            settings: Provider.of<SettingsProvider>(context, listen: false),
            logger: Provider.of<SessionLogger>(context, listen: false),
          ),
          update: (context, settings, logger, previous) {
            if (previous == null) return SensorDataProvider(settings: settings, logger: logger);
            previous.updateDependencies(settings: settings, logger: logger);
            return previous;
          },
        ),
        ChangeNotifierProxyProvider<SensorDataProvider, BluetoothProvider>(
          create: (context) => BluetoothProvider(
            sensorDataProvider: Provider.of<SensorDataProvider>(context, listen: false),
          )..initializeBluetooth(),
          update: (context, sensorData, previousBluetoothProvider) {
            previousBluetoothProvider!.sensorDataProvider = sensorData;
            return previousBluetoothProvider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'STASYS App',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const MainScreen(),
      ),
    );
  }
}