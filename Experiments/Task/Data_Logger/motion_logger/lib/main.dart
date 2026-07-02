import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

final Guid serviceUuid = Guid('12345678-1234-1234-1234-1234567890ab');
final Guid cmdUuid = Guid('12345678-1234-1234-1234-1234567890ae');
final Guid fileUuid = Guid('12345678-1234-1234-1234-1234567890ad');

void main() {
  runApp(const MotionLoggerApp());
}

class MotionLoggerApp extends StatelessWidget {
  const MotionLoggerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Motion Logger',
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool connected = false;
  BluetoothDevice? selectedDevice;

  List<BluetoothDevice> devices = [];
  List<String> files = [];

  BluetoothCharacteristic? cmdChar;
  BluetoothCharacteristic? fileChar;
  bool busy = false;

  void showMsg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> scanDevices() async {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();

    if (!await Permission.bluetoothScan.isGranted) {
      showMsg('Bluetooth scan permission denied');
      return;
    }
    setState(() {
      devices.clear();
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 5),
      );

      FlutterBluePlus.scanResults.listen((results) {
        final found = List<BluetoothDevice>.from(devices);

        for (final r in results) {
          final name = r.device.platformName.toLowerCase();

          if (!found.any((d) => d.remoteId == r.device.remoteId)) {
            found.add(r.device);
          }
        }

        if (mounted) {
          setState(() {
            devices = found;
          });
        }
      });
    } catch (e) {
      if (!e.toString().contains("User cancelled")) {
        showMsg(e.toString());
      }
    }
  }

  Future<void> toggleDevice(BluetoothDevice device) async {
    if (selectedDevice?.remoteId == device.remoteId) {
      try {
        await device.disconnect();
      } catch (_) {}

      setState(() {
        connected = false;
        selectedDevice = null;
        files.clear();
      });

      showMsg('Disconnected');
      return;
    }

    try {
      await FlutterBluePlus.stopScan();

      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );

      final services = await device.discoverServices();

      for (final s in services) {
        if (s.uuid == serviceUuid) {
          for (final c in s.characteristics) {
            if (c.uuid == cmdUuid) {
              cmdChar = c;
            }
            if (c.uuid == fileUuid) {
              fileChar = c;
            }
          }
        }
      }

      if (cmdChar == null || fileChar == null) {
        throw Exception('Required BLE characteristics not found');
      }

      setState(() {
        connected = true;
        selectedDevice = device;
        files.clear();
      });

      final name = device.platformName.isEmpty
          ? device.remoteId.str
          : device.platformName;

      showMsg('Connected to $name');
    } catch (e) {
      setState(() {
        connected = false;
        selectedDevice = null;
      });

      showMsg('Connection failed: $e');
    }
  }

  Future<void> listFiles() async {
    if (!connected || fileChar == null || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    files.clear();

    await fileChar!.setNotifyValue(true);

    final sub = fileChar!.lastValueStream.listen((data) {
      final line = String.fromCharCodes(data).trim();

      if (line.isEmpty || line == 'EOF') {
        return;
      }

      if (!files.contains(line)) {
        setState(() {
          files.add(line);
        });
      }
    });

    await cmdChar!.write('LIST'.codeUnits, withoutResponse: false);

    await Future.delayed(const Duration(seconds: 2));

    await sub.cancel();

    if (files.isEmpty) {
      showMsg('No filenames received. Check XIAO LIST implementation.');
    }
  }

  Future<void> downloadFile(String filename) async {
    if (!connected || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    setState(() => busy = true);

    try {
      await cmdChar!.write(
        'GET:$filename'.codeUnits,
        withoutResponse: false,
      );

      showMsg('Download started: $filename');
    } catch (e) {
      showMsg('Download failed: $e');
    }

    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> deleteFile(String filename) async {
    if (!connected || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    try {
      await cmdChar!.write(
        'DELETE:$filename'.codeUnits,
        withoutResponse: false,
      );

      setState(() {
        files.remove(filename);
      });

      showMsg('Delete command sent: $filename');
    } catch (e) {
      showMsg('Delete failed: $e');
    }
  }

  void startLogging() {
    if (!connected) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    showMsg('START command pending BLE implementation');
  }

  void stopLogging() {
    if (!connected) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    showMsg('STOP command pending BLE implementation');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Motion Logger"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: scanDevices,
              child: const Text("Scan Devices"),
            ),

            const SizedBox(height: 16),

            Card(
              child: ListTile(
                title: const Text("Status"),
                subtitle: Text(
                  connected ? "Connected" : "Disconnected",
                ),
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              "Devices",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            if (devices.isEmpty)
              const Text("No devices found")
            else if (connected && selectedDevice != null)
              Card(
                child: ListTile(
                  title: Text(
                    selectedDevice!.platformName.isEmpty
                        ? selectedDevice!.remoteId.str
                        : selectedDevice!.platformName,
                  ),
                  subtitle: Text(selectedDevice!.remoteId.str),
                  trailing: ElevatedButton(
                    onPressed: () async => await toggleDevice(selectedDevice!),
                    child: const Text("Disconnect"),
                  ),
                ),
              )
            else
              ...devices.map((device) {
                final name = device.platformName.isEmpty
                    ? device.remoteId.str
                    : device.platformName;

                return Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text(device.remoteId.str),
                    trailing: ElevatedButton(
                      onPressed: () async => await toggleDevice(device),
                      child: const Text("Connect"),
                    ),
                  ),
                );
              }),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: connected ? () async => await listFiles() : null,
              child: const Text("LIST FILES"),
            ),

            ...files.map(
              (f) => Card(
                child: ListTile(
                  title: Text(f),
                  subtitle: const Text('CSV log file'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: busy
                            ? null
                            : () async => await downloadFile(f),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: busy
                            ? null
                            : () async => await deleteFile(f),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: connected ? startLogging : null,
              child: const Text("START LOGGING"),
            ),

            const SizedBox(height: 8),

            OutlinedButton(
              onPressed: connected ? stopLogging : null,
              child: const Text("STOP LOGGING"),
            ),
          ],
        ),
      ),
    );
  }
}