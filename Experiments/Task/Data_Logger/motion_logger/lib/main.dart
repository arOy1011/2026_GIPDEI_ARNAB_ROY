import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';

enum AppThemeMode {
  light,
  dark,
  graphite,
}

final Guid serviceUuid = Guid('12345678-1234-1234-1234-1234567890ab');
final Guid cmdUuid = Guid('12345678-1234-1234-1234-1234567890ae');
final Guid fileUuid = Guid('12345678-1234-1234-1234-1234567890ad');

void main() {
  runApp(const MotionLoggerApp());
}

class MotionLoggerApp extends StatefulWidget {
  const MotionLoggerApp({super.key});

  @override
  State<MotionLoggerApp> createState() => _MotionLoggerAppState();
}

class _MotionLoggerAppState extends State<MotionLoggerApp> {
  AppThemeMode currentTheme = AppThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt('theme_mode') ?? 0;

    if (!mounted) return;

    setState(() {
      currentTheme = AppThemeMode.values[index];
    });
  }

  Future<void> _saveTheme(AppThemeMode theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', theme.index);
  }

  ThemeData buildTheme(AppThemeMode mode) {
    Color seed;
    Brightness brightness;

    switch (mode) {
      case AppThemeMode.dark:
        seed = Colors.indigo;
        brightness = Brightness.dark;
        break;
      case AppThemeMode.graphite:
        seed = Colors.blueGrey;
        brightness = Brightness.dark;
        break;
      case AppThemeMode.light:
        seed = Colors.indigo;
        brightness = Brightness.light;
        break;
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
      cardTheme: const CardThemeData(
        elevation: 2,
        margin: EdgeInsets.symmetric(vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Motion Logger',
      theme: buildTheme(currentTheme),
      home: HomePage(
        currentTheme: currentTheme,
        onThemeChanged: (theme) async {
          setState(() {
            currentTheme = theme;
          });
          await _saveTheme(theme);
        },
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final AppThemeMode currentTheme;
  final ValueChanged<AppThemeMode> onThemeChanged;

  const HomePage({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
  });

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
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isScanning = false;
  bool _themeMenuOpen = false;
  Timer? _autoScanTimer;
  void _startAutoScanTimer() {
    _autoScanTimer?.cancel();

    _autoScanTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (!mounted) return;
        if (connected) return;
        if (_isScanning) return;

        scanDevices();
      },
    );
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scanDevices();
      _startAutoScanTimer();
    });
  }

  void _sortFiles() {
    files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  void showMsg(String text) {
  final messenger = ScaffoldMessenger.of(context);

  messenger.clearSnackBars();

  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      duration: const Duration(milliseconds: 800),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

  Future<bool> _prepareBluetoothAndPermissions() async {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();

    if (!await Permission.bluetoothScan.isGranted ||
        !await Permission.bluetoothConnect.isGranted) {
      showMsg('Bluetooth permissions are required');
      await openAppSettings();
      return false;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;

    if (adapterState != BluetoothAdapterState.on) {
      showMsg('Bluetooth is OFF. Requesting enable...');

      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        showMsg(
          'Please enable Bluetooth from the system dialog and try again',
        );
        return false;
      }

      final newState = await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () {
        return BluetoothAdapterState.off;
      });

      if (newState != BluetoothAdapterState.on) {
        showMsg('Bluetooth was not enabled');
        return false;
      }
    }

    return true;
  }

  Future<void> scanDevices() async {
    if (_isScanning) {
      showMsg('Scan already in progress');
      return;
    }

    if (!await _prepareBluetoothAndPermissions()) {
      return;
    }

    await _scanSubscription?.cancel();
    await FlutterBluePlus.stopScan();

    if (mounted) {
      setState(() {
        devices.clear();
        _isScanning = true;
      });
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;

      final updated = List<BluetoothDevice>.from(devices);

      for (final r in results) {
        final name = r.device.platformName;
        final advName = r.advertisementData.advName;
        final deviceName = name.isNotEmpty ? name : advName;

        debugPrint(
          'FOUND: $name ADV=$advName SERVICES=${r.advertisementData.serviceUuids}',
        );

        if (deviceName.isEmpty) continue;

        if (!updated.any((d) => d.remoteId == r.device.remoteId)) {
          updated.add(r.device);
        }
      }

      if (updated.length != devices.length) {
        setState(() {
          devices = updated;
        });
      }
    });

    try {
      try {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 5),
        );
      } on PlatformException catch (e) {
        if ((e.message ?? '').contains('Bluetooth must be turned on')) {
          showMsg('Bluetooth is OFF. Please enable it and try again.');
          return;
        }

        rethrow;
      }

      await Future.delayed(const Duration(seconds: 5));
    } catch (e) {
      showMsg('Scan failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
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
      _startAutoScanTimer();
      return;
    }

    try {
      await FlutterBluePlus.stopScan();

      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      try {
        await device.requestMtu(247);
      } catch (_) {}

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

      device.connectionState.listen((state) {
        if (!mounted) return;

        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            connected = false;
            selectedDevice = null;
            files.clear();
            cmdChar = null;
            fileChar = null;
          });

          showMsg('Device disconnected');
          _startAutoScanTimer();
        }
      });

      final name = device.platformName.isEmpty
          ? device.remoteId.str
          : device.platformName;

      showMsg('Connected to $name');
      _autoScanTimer?.cancel();
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

    final sub = fileChar!.onValueReceived.listen((data) {
      final raw = String.fromCharCodes(data);
      debugPrint('BLE RAW: $raw');

      for (final line in raw.split(RegExp(r'\r?\n'))) {
        final name = line.trim();

        if (name.isEmpty || name == 'EOF') {
          continue;
        }

        // Ignore streamed CSV contents and keep only actual filenames.
        if (!name.toUpperCase().endsWith('.CSV')) {
          continue;
        }

        if (!files.contains(name)) {
          setState(() {
            files.add(name);
            _sortFiles();
          });
        }
      }
    });

    await cmdChar!.write('LIST'.codeUnits, withoutResponse: false);

    await Future.delayed(const Duration(seconds: 2));

    await sub.cancel();

    if (files.isEmpty) {
      showMsg('No filenames received. Check XIAO LIST implementation.');
    }
  }

  Future<void> downloadFile(int index, String filename) async {
    if (!connected || cmdChar == null || fileChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    final directory = Directory(
      '/storage/emulated/0/Download/MotionLogger',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    debugPrint('Saving file to: ${directory.path}/$filename');
    final outFile = File('${directory.path}/$filename');
    final sink = outFile.openWrite();
    final transferDone = Completer<void>();
    showMsg('Starting download: $filename');
    bool transferStarted = false;
    int expectedBytes = 0;
    int receivedBytes = 0;

    setState(() => busy = true);

    await fileChar!.setNotifyValue(true);

    late final StreamSubscription<List<int>> sub;

    sub = fileChar!.onValueReceived.listen((data) async {
      final msg = String.fromCharCodes(data).trim();

      if (!transferStarted) {
        debugPrint('RX: $msg');

        if (msg.startsWith('BEGIN:')) {
          expectedBytes = int.tryParse(msg.substring(6)) ?? 0;
          transferStarted = true;

          debugPrint('Expecting $expectedBytes bytes');
          return;
        }
      }

      if (transferStarted && (msg == 'END' || msg == 'EOF')) {
        if (transferDone.isCompleted) return;

        await sink.flush();
        await sink.close();
        await sub.cancel();

        debugPrint('$msg RECEIVED');
        debugPrint('FINAL: $receivedBytes / $expectedBytes');

        showMsg(
          'Download finished: $filename\n'
          '$receivedBytes / $expectedBytes bytes saved',
        );

        transferDone.complete();
        return;
      }

      sink.add(data);
      receivedBytes += data.length;

      if (receivedBytes % 1024 < data.length) {
        debugPrint(
          'Received $receivedBytes / $expectedBytes bytes',
        );
      }

      if (expectedBytes > 0 &&
          receivedBytes >= expectedBytes &&
          !transferDone.isCompleted) {

        debugPrint('SIZE TARGET REACHED');

        await sink.flush();
        await sink.close();
        await sub.cancel();

        showMsg(
          'Download finished: $filename\n'
          '$receivedBytes bytes received',
        );

        transferDone.complete();
      }
    });
    selectedDevice?.cancelWhenDisconnected(sub);

    try {
      await cmdChar!.write(
        'G:$index'.codeUnits,
        withoutResponse: false,
      );
    } catch (e) {
      await sink.close();
      await sub.cancel();

      if (!transferDone.isCompleted) {
        transferDone.completeError(e);
      }

      if (mounted) {
        setState(() => busy = false);
      }

      showMsg('Download failed: $e');
    }
    try {
      await transferDone.future.timeout(
        const Duration(seconds: 15),
      );
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> deleteFile(int index, String filename) async {
    if (!connected || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    try {
      await cmdChar!.write(
        'D:$index'.codeUnits,
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

  void startLogging() async {
    if (!connected || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    try {
      await cmdChar!.write(
        'START'.codeUnits,
        withoutResponse: false,
      );

      showMsg('START command sent');
    } catch (e) {
      showMsg('START failed: $e');
    }
  }

  void stopLogging() async {
    if (!connected || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    try {
      await cmdChar!.write(
        'STOP'.codeUnits,
        withoutResponse: false,
      );

      showMsg('STOP command sent');
    } catch (e) {
      showMsg('STOP failed: $e');
    }
  }

  Future<void> getStatus() async {
    if (!connected || cmdChar == null || fileChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    await fileChar!.setNotifyValue(true);

    late final StreamSubscription<List<int>> sub;

    sub = fileChar!.onValueReceived.listen((data) async {
      final msg = String.fromCharCodes(data).trim();

      if (msg == 'LOGGING' || msg == 'STOPPED') {
        showMsg('Status: $msg');
        await sub.cancel();
      }
    });

    await cmdChar!.write(
      'STATUS'.codeUnits,
      withoutResponse: false,
    );
  }

  @override
  void dispose() {
    _autoScanTimer?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        centerTitle: true,
        title: const Text(
          "Motion Logger",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_themeMenuOpen) ...[
            FloatingActionButton.small(
              heroTag: 'light_theme',
              tooltip: 'Light Theme',
              onPressed: () {
                widget.onThemeChanged(AppThemeMode.light);
                setState(() {
                  _themeMenuOpen = false;
                });
              },
              child: const Icon(Icons.wb_sunny_rounded),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'dark_theme',
              tooltip: 'Dark Theme',
              onPressed: () {
                widget.onThemeChanged(AppThemeMode.dark);
                setState(() {
                  _themeMenuOpen = false;
                });
              },
              child: const Icon(Icons.dark_mode_rounded),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'graphite_theme',
              tooltip: 'Graphite Theme',
              onPressed: () {
                widget.onThemeChanged(AppThemeMode.graphite);
                setState(() {
                  _themeMenuOpen = false;
                });
              },
              child: const Icon(Icons.landscape_rounded),
            ),
            const SizedBox(height: 8),
          ],
          FloatingActionButton(
            heroTag: 'theme_menu',
            tooltip: 'Appearance',
            onPressed: () {
              setState(() {
                _themeMenuOpen = !_themeMenuOpen;
              });
            },
            child: Icon(
              _themeMenuOpen
                  ? Icons.close_rounded
                  : Icons.palette_rounded,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 90),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

            // Compact Discovery/Connect section
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    // Replaced: AnimatedOpacity/scan button
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_isScanning)
                            const SizedBox(
                              width: 68,
                              height: 68,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                              ),
                            ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(6),
                              shape: const CircleBorder(),
                              backgroundColor: connected
                                  ? Colors.green
                                  : Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _isScanning ? null : scanDevices,
                            child: Opacity(
                              opacity: _isScanning ? 0.75 : 1.0,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isScanning
                                        ? Icons.bluetooth_searching_rounded
                                        : Icons.bluetooth_rounded,
                                    size: 22,
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'SCAN',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Device selector and status
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<BluetoothDevice>(
                              isExpanded: true,
                              value: selectedDevice,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                hintText: 'Select device',
                                border: OutlineInputBorder(),
                              ),
                              items: devices
                                  .map(
                                    (device) => DropdownMenuItem(
                                      value: device,
                                      child: Text(
                                        device.platformName.isEmpty
                                            ? device.remoteId.str
                                            : device.platformName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: devices.isEmpty
                                  ? null
                                  : (device) async {
                                      if (device != null) {
                                        await toggleDevice(device);
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                connected ? 'Connected' : '${devices.length}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (connected) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Disconnect',
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  icon: const Icon(
                                    Icons.link_off_rounded,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  onPressed: () async {
                                    final device = selectedDevice;
                                    if (device == null) return;

                                    try {
                                      await device.disconnect();
                                    } catch (_) {}

                                    if (!mounted) return;

                                    setState(() {
                                      connected = false;
                                      selectedDevice = null;
                                      files.clear();
                                      cmdChar = null;
                                      fileChar = null;
                                    });

                                    showMsg('Disconnected');
                                    _startAutoScanTimer();
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Files',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${files.length}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Refresh files',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              icon: const Icon(Icons.sync_rounded, size: 18),
                              onPressed: connected ? () async => await listFiles() : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ...files.asMap().entries.map((entry) {
              final index = entry.key;
              final file = entry.value;

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        file,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Download',
                      icon: const Icon(
                        Icons.download_rounded,
                        size: 18,
                        color: Colors.blue,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: busy
                          ? null
                          : () async => await downloadFile(index, file),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: Colors.red,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: busy
                          ? null
                          : () async => await deleteFile(index, file),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),

            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      'Control',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Start Logging',
                            onPressed: connected ? startLogging : null,
                            icon: const Icon(Icons.play_arrow_rounded),
                            color: Colors.green,
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            tooltip: 'Stop Logging',
                            onPressed: connected ? stopLogging : null,
                            icon: const Icon(Icons.stop_rounded),
                            color: Colors.red,
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            tooltip: 'Get Status',
                            onPressed: connected
                                ? () async => await getStatus()
                                : null,
                            icon: const Icon(Icons.info_outline_rounded),
                            color: Colors.orange,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}