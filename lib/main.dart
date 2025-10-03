import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter BLE Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter BLE Home'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool isScanning = false;
  List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;

  @override
  void initState() {
    super.initState();
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        setState(() {
          isScanning = false;
        });
      }
    });
  }

  Future<bool> isBluetoothNotEnabled() async {
    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth not supported by this device");
      return true;
    }

    if (!kIsWeb && Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
      return false;
    }
    return true;
  }

  void startScan() async {
    // Request Bluetooth permission
    bool isNotEnable = await isBluetoothNotEnabled();
    if (isNotEnable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bluetooth and Location permissions are required.'),
        ),
      );
      return;
    }
    // Check Bluetooth state
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      // Try to turn on Bluetooth (Android only)
      await FlutterBluePlus.turnOn();
      // Re-check state
      final newState = await FlutterBluePlus.adapterState.first;
      if (newState != BluetoothAdapterState.on) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enable Bluetooth to scan devices.')),
        );
        return;
      }
    }
    setState(() {
      isScanning = true;
      scanResults.clear();
    });
    FlutterBluePlus.startScan(timeout: Duration(seconds: 4));

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results;
      });

      for (ScanResult result in results) {
        if (result.advertisementData.serviceUuids.contains(
          'your-service-uuid', // Replace with actual Service UUID
        )) {
          debugPrint('Found device: ${result.device.platformName}');
          connectToDevice(result.device);
        }
      }
    });

    FlutterBluePlus.isScanning.listen((scanning) {
      setState(() {
        isScanning = scanning;
      });
    });
  }

  void connectToDevice(BluetoothDevice device) async {
    await device.connect(license: License.free);
    debugPrint("Connected to ${device.platformName}");

    setState(() {
      connectedDevice = device;
    });

    discoverServices(device);
  }

  void discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();

    for (var service in services) {
      if (service.uuid.toString() == 'your-service-uuid') {
        // Replace with actual UUID
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          debugPrint('Characteristic UUID: ${characteristic.uuid}');

          if (characteristic.uuid.toString() ==
              'data-status-characteristic-uuid') {
            // Subscribe to the data status notifications
            subscribeToDataStatus(characteristic);
          }
        }
      }
    }
  }

  void subscribeToDataStatus(BluetoothCharacteristic characteristic) async {
    await characteristic.setNotifyValue(true);

    characteristic.lastValueStream.listen((value) {
      String data = String.fromCharCodes(value);
      debugPrint('Data received: $data');

      // Parse the received data (assuming JSON)
      Map<String, dynamic> parsedData = jsonDecode(data);
      debugPrint(
        'Pill count: ${parsedData['pills']}, Battery: ${parsedData['battery']}',
      );
      // You can store the parsed data and update UI with it
      setState(() {
        // For example, show pill count and battery
      });
    });
  }

  void sendCommand(
    BluetoothCharacteristic characteristic,
    String command,
  ) async {
    List<int> commandBytes = utf8.encode(command);
    await characteristic.write(commandBytes);
    debugPrint('Command sent: $command');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: isScanning ? null : startScan,
            child: Text(isScanning ? 'Scanning...' : 'Start Scan'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: scanResults.length,
              itemBuilder: (context, index) {
                final result = scanResults[index];
                final hasService = result.advertisementData.serviceUuids
                    .contains('your-service-uuid');
                return ListTile(
                  title: Text(
                    result.device.platformName.isNotEmpty
                        ? result.device.platformName
                        : result.device.remoteId.str,
                  ),
                  subtitle: Text('RSSI: ${result.rssi}'),
                  trailing: hasService
                      ? ElevatedButton(
                          onPressed: () => connectToDevice(result.device),
                          child: Text('Connect'),
                        )
                      : null,
                );
              },
            ),
          ),
          if (connectedDevice != null) ...[
            // Show connected device name or other info
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text("Connected to: ${connectedDevice!.platformName}"),
            ),
            // Add a command button (e.g., Unlock command)
            ElevatedButton(
              onPressed: () {
                // Replace with actual command
                sendCommandToDevice('unlock');
              },
              child: Text('Unlock Solenoid'),
            ),
          ],
        ],
      ),
    );
  }

  void sendCommandToDevice(String command) {
    if (connectedDevice == null) return;

    // Discover services again if needed or use previously discovered services
    connectedDevice!.discoverServices().then((services) {
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == 'command-characteristic-uuid') {
            sendCommand(characteristic, command);
          }
        }
      }
    });
  }
}
