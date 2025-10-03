import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

const String SERVICE_UUID = '1f2b2515-75da-4a4a-8c1a-621d0e537cb4';
const String DATA_STATUS_CHAR_UUID = 'a39fe3b2-f9a2-4000-9399-b6a8c50676e1';
const String COMMAND_CHAR_UUID = '3d29e219-389e-4e4c-80c3-95f0d2b5d5fd';

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
    // Check location permission using permission_handler
    // This checks for coarse location permission.
    // For fine location (required for BLE scan on Android 10+), use Permission.locationWhenInUse
    if (await Permission.locationWhenInUse.isDenied ||
        await Permission.locationWhenInUse.isPermanentlyDenied) {
      var status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        debugPrint("Fine location permission not granted");
        return true;
      }
    }

    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("Bluetooth not supported by this device");
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
    FlutterBluePlus.startScan(
      timeout: Duration(seconds: 4),
      androidUsesFineLocation: true,
      // withServices: [Guid(SERVICE_UUID)],
    );

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results;
      });

      if (results.isNotEmpty) {
        debugPrint('Scan found ${results.length} device(s)');
        for (ScanResult result in results) {
            debugPrint(
            '--- ScanResult ---\n'
            'Device: ${result.device}\n'
            'Device ID: ${result.device.id}\n'
            'Device Name: ${result.device.name}\n'
            'Device Platform Name: ${result.device.platformName}\n'
            'Device Adv Name: ${result.device.advName}\n'
            'RSSI: ${result.rssi}\n'
            'Advertisement Data: ${result.advertisementData}\n'
            '  Local Name: ${result.advertisementData.localName}\n'
            '  Service UUIDs: ${result.advertisementData.serviceUuids}\n'
            '  Manufacturer Data: ${result.advertisementData.manufacturerData}\n'
            '  Service Data: ${result.advertisementData.serviceData}\n'
            '  Tx Power Level: ${result.advertisementData.txPowerLevel}\n'
            '  Connectable: ${result.advertisementData.connectable}\n'
            '------------------'
            );
          if (result.advertisementData.serviceUuids.contains(
            Guid(SERVICE_UUID),
          )) {
            debugPrint(
              'Found device with target service: ${result.device.platformName}',
            );
            connectToDevice(result.device);
          }
        }
      } else {
        debugPrint('No devices found in scan');
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
      if (service.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
        // Replace with actual UUID
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          debugPrint('Characteristic UUID: ${characteristic.uuid}');

          if (characteristic.uuid.toString().toLowerCase() ==
              DATA_STATUS_CHAR_UUID.toLowerCase()) {
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
                    .contains(Guid(SERVICE_UUID));
                return ListTile(
                  title: Text(
                    result.device.advName.isNotEmpty
                        ? result.device.advName
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
          if (characteristic.uuid.toString() == COMMAND_CHAR_UUID) {
            sendCommand(characteristic, command);
          }
        }
      }
    });
  }
}
