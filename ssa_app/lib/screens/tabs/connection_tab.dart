
// ============================================
// File: screens/tabs/connection_tab.dart
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../../providers/bluetooth_provider.dart';

class ConnectionTab extends StatelessWidget {
  const ConnectionTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Connection'),
        backgroundColor: Colors.purple,
        actions: [
          Consumer<BluetoothProvider>(
            builder: (context, bluetoothProvider, child) {
              return bluetoothProvider.isConnected
                  ? IconButton(
                      onPressed: () => bluetoothProvider.disconnect(),
                      icon: const Icon(Icons.bluetooth_disabled),
                      tooltip: 'Disconnect',
                    )
                  : SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<BluetoothProvider>(
        builder: (context, bluetoothProvider, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection Status
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bluetoothProvider.isConnected ? Colors.green[100] : Colors.red[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        bluetoothProvider.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                        color: bluetoothProvider.isConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          bluetoothProvider.isConnected
                              ? 'Connected to ${bluetoothProvider.selectedDevice?.name ?? "Unknown"}'
                              : 'Not Connected',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: bluetoothProvider.isConnected ? Colors.green[800] : Colors.red[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Control Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: bluetoothProvider.isScanning ? null : () => bluetoothProvider.startScan(),
                        icon: bluetoothProvider.isScanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search),
                        label: Text(bluetoothProvider.isScanning ? 'Scanning...' : 'Scan Devices'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => bluetoothProvider.getBondedDevices(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Paired Devices'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Available Devices
                const Text(
                  'Available Devices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                Expanded(
                  child: bluetoothProvider.devicesList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bluetooth_searching,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No devices found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: bluetoothProvider.devicesList.length,
                          itemBuilder: (context, index) {
                            BluetoothDevice device = bluetoothProvider.devicesList[index];
                            bool isCurrentDevice = bluetoothProvider.isConnected && 
                                                   bluetoothProvider.selectedDevice == device;
                            
                            return Card(
                              elevation: isCurrentDevice ? 4 : 1,
                              color: isCurrentDevice ? Colors.green[50] : null,
                              child: ListTile(
                                leading: Icon(
                                  Icons.bluetooth,
                                  color: isCurrentDevice ? Colors.green : Colors.blue,
                                ),
                                title: Text(
                                  device.name ?? "Unknown Device",
                                  style: TextStyle(
                                    fontWeight: isCurrentDevice ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(device.address),
                                trailing: isCurrentDevice
                                    ? const Icon(Icons.check_circle, color: Colors.green)
                                    : const Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: isCurrentDevice ? null : () async {
                                  bool success = await bluetoothProvider.connectToDevice(device);
                                  if (success && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Connected to ${device.name ?? device.address}')),
                                    );
                                  } else if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed to connect to ${device.name ?? "Unknown"}')),
                                    );
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}