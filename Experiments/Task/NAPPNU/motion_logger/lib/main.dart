import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

enum AppThemeMode { light, dark, graphite }

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
      title: 'NAPPNU',
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
  final Map<String, int> _fileIndexes = {};

  BluetoothCharacteristic? cmdChar;
  BluetoothCharacteristic? fileChar;
  bool busy = false;
  bool isLogging = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isScanning = false;
  bool _themeMenuOpen = false;
  bool _autoConnecting = false;
  DateTime? _lastAutoConnect;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _downloadSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  Timer? _autoScanTimer;
  Timer? _fileRefreshTimer;
  final Set<String> _loggedDevices = {};
  void _startAutoScanTimer() {
    _autoScanTimer?.cancel();

    _autoScanTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (connected) return;
      if (_isScanning) return;

      scanDevices();
    });
  }

  void _startFileRefreshTimer() {
    _fileRefreshTimer?.cancel();

    _fileRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      if (!connected || !isLogging || busy) return;
      if (cmdChar == null || fileChar == null) return;

      unawaited(_loadFileList(clearBeforeLoad: false));
    });
  }

  void _stopFileRefreshTimer() {
    _fileRefreshTimer?.cancel();
    _fileRefreshTimer = null;
  }

  @override
  void initState() {
    super.initState();

    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;

      if (state == BluetoothAdapterState.off) {
        setState(() {
          connected = false;
          selectedDevice = null;
          files.clear();
          _fileIndexes.clear();
          cmdChar = null;
          fileChar = null;
          isLogging = false;
          _autoConnecting = false;
          _isScanning = false;
        });
        _stopFileRefreshTimer();

        if (_isScanning) {
          unawaited(FlutterBluePlus.stopScan());
        }
        showMsg('Bluetooth turned off');
        _autoScanTimer?.cancel();
      }

      if (state == BluetoothAdapterState.on && !connected) {
        showMsg('Bluetooth enabled');
        _startAutoScanTimer();
        scanDevices();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scanDevices();
      _startAutoScanTimer();
    });
  }

  void _sortFiles() {
    files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  void showMsg(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> showRequirementDialog(
    String title,
    String message, {
    bool locationSettings = false,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          if (locationSettings)
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);

                try {
                  await const MethodChannel(
                    'app.channel.shared/settings',
                  ).invokeMethod('openLocationSettings');

                  Future.delayed(const Duration(seconds: 1), () async {
                    if (!mounted) return;

                    final enabled =
                        await Permission.location.serviceStatus.isEnabled;

                    if (enabled && !_isScanning && !connected) {
                      showMsg('Location enabled. Scanning for devices...');
                      unawaited(scanDevices());
                    }
                  });
                } catch (e) {
                  debugPrint('openLocationSettings failed: $e');

                  if (mounted) {
                    showMsg('Could not open system Location settings');
                  }
                }
              },
              child: const Text('Turn On Location'),
            )
          else
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
        ],
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

    final locationPermissionGranted = await Permission.location.isGranted;

    if (!locationPermissionGranted) {
      await showRequirementDialog(
        'Location Permission Required',
        'Android requires location permission for Bluetooth Low Energy scanning.',
      );
      return false;
    }

    final locationServiceEnabled =
        await Permission.location.serviceStatus.isEnabled;

    if (!locationServiceEnabled) {
      await showRequirementDialog(
        'Location Services Disabled',
        'Android requires Location Services to be enabled for Bluetooth Low Energy scanning.',
        locationSettings: true,
      );
      return false;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;

    if (adapterState != BluetoothAdapterState.on) {
      showMsg('Bluetooth is OFF. Requesting enable...');

      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        await showRequirementDialog(
          'Bluetooth Required',
          'Please enable Bluetooth to use NAPPNU.',
        );
        return false;
      }

      final newState = await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              return BluetoothAdapterState.off;
            },
          );

      if (newState != BluetoothAdapterState.on) {
        await showRequirementDialog(
          'Bluetooth Required',
          'Bluetooth must be enabled before scanning for devices.',
        );
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

    if (await FlutterBluePlus.isScanning.first) {
      await FlutterBluePlus.stopScan();
    }

    if (mounted) {
      setState(() {
        devices.clear();
        _loggedDevices.clear();
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

        final lowerNameForLog = deviceName.toLowerCase();

        final isOurDevice =
            lowerNameForLog.startsWith('motionlo') ||
            lowerNameForLog.startsWith('motion') ||
            lowerNameForLog.startsWith('nappnu');

        if (isOurDevice && _loggedDevices.add(r.device.remoteId.str)) {
          debugPrint(
            'FOUND DEVICE: $deviceName SERVICES=${r.advertisementData.serviceUuids}',
          );
        }

        if (deviceName.isEmpty) continue;

        if (!updated.any((d) => d.remoteId == r.device.remoteId)) {
          updated.add(r.device);
        }

        final lowerName = deviceName.toLowerCase();
        final canAutoConnect =
            _lastAutoConnect == null ||
            DateTime.now().difference(_lastAutoConnect!) >
                const Duration(seconds: 10);

        if (!connected &&
            !_autoConnecting &&
            canAutoConnect &&
            (lowerName.contains('motionlo') ||
                lowerName.contains('motion lo') ||
                lowerName.contains('motionlogger') ||
                lowerName.contains('nappnu'))) {
          _lastAutoConnect = DateTime.now();
          _autoConnecting = true;

          Future.microtask(() async {
            try {
              showMsg('NAPPNU found. Connecting...');
              await toggleDevice(r.device);
            } finally {
              if (mounted) {
                _autoConnecting = false;
              }
            }
          });
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
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
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
        _fileIndexes.clear();
      });
      _stopFileRefreshTimer();

      showMsg('Disconnected');
      _startAutoScanTimer();
      return;
    }

    try {
      if (await FlutterBluePlus.isScanning.first) {
        await FlutterBluePlus.stopScan();
      }

      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      try {
        await device.requestMtu(247);
      } catch (_) {}
      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
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
        _fileIndexes.clear();
      });

      await _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (!mounted) return;

        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            connected = false;
            selectedDevice = null;
            files.clear();
            _fileIndexes.clear();
            cmdChar = null;
            fileChar = null;
            isLogging = false;
            _autoConnecting = false;
          });
          _stopFileRefreshTimer();

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
      if (mounted) {
        setState(() {
          connected = false;
          selectedDevice = null;
        });

        _autoConnecting = false;
      }

      showMsg('Connection failed: $e');
    }
  }

  Future<void> listFiles() async {
    if (!connected || fileChar == null || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }
    if (busy) {
      showMsg('Wait for the current download to finish');
      return;
    }

    await _loadFileList();

    if (files.isEmpty) {
      showMsg('No files found');
    }
  }

  Future<void> _loadFileList({bool clearBeforeLoad = true}) async {
    final receivedFiles = <String>[];
    final receivedIndexes = <String, int>{};
    final completer = Completer<void>();
    Timer? timeoutTimer;

    void finish() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    if (clearBeforeLoad && mounted) {
      setState(() {
        files.clear();
        _fileIndexes.clear();
      });
    } else if (clearBeforeLoad) {
      files.clear();
      _fileIndexes.clear();
    }

    late final StreamSubscription<List<int>> sub;
    sub = fileChar!.onValueReceived.listen(
      (data) {
        final packet = utf8.decode(data, allowMalformed: true).trim();
        debugPrint('BLE LIST PACKET: $packet');

        if (packet.isEmpty) {
          return;
        }

        if (packet == 'EOF' || packet == 'END') {
          finish();
          return;
        }

        if (packet.startsWith('ERROR:')) {
          if (!completer.isCompleted) {
            completer.completeError(StateError(packet));
          }
          return;
        }

        for (final name in _extractCsvNames(packet)) {
          if (receivedIndexes.containsKey(name)) {
            continue;
          }

          receivedIndexes[name] = receivedIndexes.length;
          receivedFiles.add(name);

          if (mounted) {
            setState(() {
              _fileIndexes[name] = receivedIndexes[name]!;
              files.add(name);
              _sortFiles();
            });
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: finish,
    );

    try {
      await fileChar!.setNotifyValue(true);
      await Future.delayed(const Duration(milliseconds: 250));
      timeoutTimer = Timer(const Duration(seconds: 5), finish);
      debugPrint('BLE LIST CMD: LIST');
      await cmdChar!.write('LIST'.codeUnits, withoutResponse: false);
      await completer.future;
    } finally {
      timeoutTimer?.cancel();
      await sub.cancel();
    }

    if (!mounted) return;

    if (files.length != receivedFiles.length) {
      setState(() {
        files
          ..clear()
          ..addAll(receivedFiles);
        _sortFiles();
        _fileIndexes
          ..clear()
          ..addAll(receivedIndexes);
      });
    }
  }

  Future<void> downloadFile(String filename) async {
    if (!connected || cmdChar == null || fileChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }
    if (busy) {
      showMsg('Wait for the current download to finish');
      return;
    }

    final fileIndex = _fileIndexes[filename];
    if (fileIndex == null) {
      showMsg('Refresh files and try again');
      return;
    }

    if (isLogging) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Download while logging?'),
              content: Text(
                '$filename may still be changing because logging is active.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Download'),
                ),
              ],
            ),
          ) ??
          false;

      if (!mounted) return;
      if (!confirmed) return;
    }

    setState(() => busy = true);
    showMsg('Downloading: $filename');

    try {
      final bytes = await _receiveDownload(fileIndex);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save motion log',
        fileName: _safeDownloadName(filename),
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: bytes,
      );

      if (savedPath == null) {
        showMsg('Download cancelled');
        return;
      }

      debugPrint('DOWNLOAD SAVED: $savedPath (${bytes.length} bytes)');
      showMsg('Downloaded: ${_safeDownloadName(filename)}');
    } catch (e) {
      showMsg('Download failed: $e');
    } finally {
      await _downloadSub?.cancel();
      _downloadSub = null;

      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<Uint8List> _receiveDownload(int index) async {
    final completer = Completer<Uint8List>();
    final content = BytesBuilder(copy: false);
    var started = false;
    Timer? timeoutTimer;

    void resetTimeout() {
      timeoutTimer?.cancel();
      timeoutTimer = Timer(const Duration(seconds: 20), () {
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('No data received for 20 seconds'),
          );
        }
      });
    }

    void completeWithContent() {
      if (!completer.isCompleted) {
        completer.complete(content.takeBytes());
      }
    }

    await _downloadSub?.cancel();
    _downloadSub = null;

    late final StreamSubscription<List<int>> sub;
    sub = fileChar!.onValueReceived.listen(
      (data) {
        resetTimeout();

        final marker = utf8.decode(data, allowMalformed: true).trim();
        debugPrint('BLE GET PACKET: $marker');

        if (marker.isEmpty) {
          return;
        }

        if (marker.startsWith('BEGIN:')) {
          started = true;
          return;
        }

        if (marker == 'END' || marker == 'EOF') {
          completeWithContent();
          return;
        }

        if (marker.startsWith('ERROR:')) {
          if (!completer.isCompleted) {
            completer.completeError(StateError(marker));
          }
          return;
        }

        if (started) {
          content.add(data);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError('Download stream closed'));
        }
      },
    );

    selectedDevice?.cancelWhenDisconnected(sub);
    _downloadSub = sub;

    try {
      await fileChar!.setNotifyValue(true);
      await Future.delayed(const Duration(milliseconds: 250));

      resetTimeout();

      final command = 'G:$index';
      debugPrint('BLE DOWNLOAD CMD: $command');
      await cmdChar!.write(command.codeUnits, withoutResponse: false);
      return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      await sub.cancel();
      if (identical(_downloadSub, sub)) {
        _downloadSub = null;
      }
    }
  }

  List<String> _extractCsvNames(String packet) {
    final names = <String>[];
    final matches = RegExp(
      r'[^,\s/\\]+\.CSV',
      caseSensitive: false,
    ).allMatches(packet);

    for (final match in matches) {
      names.add(match.group(0)!.trim());
    }

    return names;
  }

  String _safeDownloadName(String filename) {
    final cleaned = filename
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) {
      return 'motion_log.csv';
    }

    if (cleaned.toLowerCase().endsWith('.csv')) {
      return cleaned;
    }

    return '$cleaned.csv';
  }

  Future<void> deleteFile(String filename) async {
    if (!connected || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }
    if (isLogging) {
      showMsg('Stop logging before deleting files');
      return;
    }

    final fileIndex = _fileIndexes[filename];
    if (fileIndex == null) {
      showMsg('Refresh files and try again');
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete file?'),
            content: Text('Are you sure you want to delete\n\n$filename?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await cmdChar!.write('D:$fileIndex'.codeUnits, withoutResponse: false);

      setState(() {
        files.remove(filename);
        _fileIndexes.remove(filename);
      });

      showMsg('Deleted: $filename');
      Future.delayed(const Duration(milliseconds: 400), () async {
        if (mounted && connected) {
          await listFiles();
        }
      });
    } catch (e) {
      showMsg('Delete failed: $e');
    }
  }

  void startLogging() async {
    if (!connected || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    if (isLogging) {
      showMsg('Already logging');
      return;
    }

    try {
      await cmdChar!.write('START'.codeUnits, withoutResponse: false);

      setState(() {
        isLogging = true;
      });
      _startFileRefreshTimer();
      unawaited(_loadFileList(clearBeforeLoad: false));

      showMsg('Logging started');
    } catch (e) {
      showMsg('START failed: $e');
    }
  }

  void stopLogging() async {
    if (!connected || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    if (!isLogging) {
      showMsg('Logging already stopped');
      return;
    }

    try {
      await cmdChar!.write('STOP'.codeUnits, withoutResponse: false);

      setState(() {
        isLogging = false;
      });
      _stopFileRefreshTimer();

      showMsg('Logging stopped');
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
        setState(() {
          isLogging = msg == 'LOGGING';
        });
        if (isLogging) {
          _startFileRefreshTimer();
        } else {
          _stopFileRefreshTimer();
        }

        showMsg('Status: $msg');
        await sub.cancel();
      }
    });

    await cmdChar!.write('STATUS'.codeUnits, withoutResponse: false);
  }

  @override
  void dispose() {
    _autoScanTimer?.cancel();
    _scanSubscription?.cancel();
    _adapterStateSub?.cancel();
    _connectionSub?.cancel();
    _downloadSub?.cancel();
    _stopFileRefreshTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        centerTitle: true,
        title: const Text(
          "NAPPNU",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'About NAPPNU',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'NAPPNU',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.sensors_rounded),
                children: [
                  const Text(
                    'Motion logging companion for XIAO nRF52840 Sense.',
                  ),
                  const SizedBox(height: 16),
                  const Text('Developed by'),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final uri = Uri.parse('https://suxmasystems.com/');

                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    child: Text(
                      'SUXMA Systems Pvt. Ltd.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
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
              _themeMenuOpen ? Icons.close_rounded : Icons.palette_rounded,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: RefreshIndicator(
            onRefresh: () async {
              if (connected) {
                await listFiles();
              } else {
                await scanDevices();
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Compact Discovery/Connect section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _isScanning
                                              ? Icons
                                                    .bluetooth_searching_rounded
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
                                  child:
                                      DropdownButtonFormField<BluetoothDevice>(
                                        isExpanded: true,
                                        initialValue: selectedDevice,
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                      connected
                                          ? 'Connected'
                                          : '${devices.length} devices available',
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
                                            _fileIndexes.clear();
                                            cmdChar = null;
                                            fileChar = null;
                                            isLogging = false;
                                          });
                                          _stopFileRefreshTimer();

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
                                    '${files.length} files',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Refresh files',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    icon: const Icon(
                                      Icons.sync_rounded,
                                      size: 18,
                                    ),
                                    onPressed: connected
                                        ? () async => await listFiles()
                                        : null,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (files.isNotEmpty)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final file = files[index];

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
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
                                    : () async => await downloadFile(file),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: busy || isLogging
                                    ? null
                                    : () async => await deleteFile(file),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 10),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Control',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: connected
                                  ? (isLogging
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : Colors.orange.withValues(alpha: 0.15))
                                  : Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              connected
                                  ? (isLogging ? 'LOGGING' : 'STOPPED')
                                  : 'OFFLINE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: connected
                                    ? (isLogging ? Colors.green : Colors.orange)
                                    : Colors.red,
                              ),
                            ),
                          ),
                          const Spacer(),
                          DecoratedBox(
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
                                  onPressed: connected && !isLogging
                                      ? startLogging
                                      : null,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  color: Colors.green,
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  tooltip: 'Stop Logging',
                                  onPressed: connected && isLogging
                                      ? stopLogging
                                      : null,
                                  icon: const Icon(Icons.stop_rounded),
                                  color: Colors.red,
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
      ),
    );
  }
}
