/*
  NAPPNU - Motion Logger Flutter App (main.dart)

  This file implements the mobile UI that connects to the MotionLogger
  hardware over Bluetooth Low Energy (BLE). Key responsibilities:
  - Scan and connect to the MotionLogger device
  - Expose controls to start/stop logging remotely
  - List, download and delete CSV files stored on the device
  - Stream live IMU data when connected

  Important UUIDs (must match firmware):
  - Service UUID: serviceUuid
  - Command characteristic: cmdUuid (write commands)
  - File/notification characteristic: fileUuid (notifications for LIST/GET/DELETE)
*/

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

// Application theme options
enum AppThemeMode { light, dark, graphite }

// BLE identifiers used by both app and firmware; keep in sync with device firmware
final Guid serviceUuid = Guid('12345678-1234-1234-1234-1234567890ab'); // Main BLE service UUID
final Guid cmdUuid = Guid('12345678-1234-1234-1234-1234567890ae'); // Command characteristic UUID
final Guid fileUuid = Guid('12345678-1234-1234-1234-1234567890ad'); // File/notification characteristic UUID

// App entry point
void main() {
  // Launch root app widget
  runApp(const MotionLoggerApp());
}

// Root app widget: manages theme and launches HomePage
class MotionLoggerApp extends StatefulWidget {
  const MotionLoggerApp({super.key});

  @override
  State<MotionLoggerApp> createState() => _MotionLoggerAppState();
}

class _MotionLoggerAppState extends State<MotionLoggerApp> {
  // Current app theme mode (persisted)
  AppThemeMode currentTheme = AppThemeMode.light;

  @override
  void initState() {
    super.initState();
    // Load persisted theme mode on app startup
    _loadTheme();
  }

  // Load saved theme mode from persistent storage
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt('theme_mode') ?? 0;
    if (!mounted) return;
    setState(() {
      currentTheme = AppThemeMode.values[index];
    });
  }

  // Save selected theme mode to persistent storage
  Future<void> _saveTheme(AppThemeMode theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', theme.index);
  }

  // Build ThemeData for selected theme mode
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
    // Main app widget with theme and home page
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

// Main HomePage widget: handles BLE, files, and UI logic
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
  // BLE connection state: true if a device is connected
  bool connected = false;
  // Currently selected BLE device (if any)
  BluetoothDevice? selectedDevice;
  // List of discovered BLE devices from scan
  List<BluetoothDevice> devices = [];
  // List of CSV files detected on device
  List<String> files = [];
  // Map of filename to index for device file commands (for GET/DELETE)
  final Map<String, int> _fileIndexes = {};
  // BLE characteristic for sending commands (write)
  BluetoothCharacteristic? cmdChar;
  // BLE characteristic for receiving file data and notifications
  BluetoothCharacteristic? fileChar;
  // Busy state: true if a file download is in progress
  bool busy = false;
  // Logging status: true if device is logging
  bool isLogging = false;
  // Subscription for BLE scan results stream
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  // True if a BLE scan is currently in progress
  bool _isScanning = false;
  // True if theme palette menu is open
  bool _themeMenuOpen = false;
  // True if an auto-connection attempt is in progress
  bool _autoConnecting = false;
  // Timestamp of last auto-connect attempt (to avoid rapid retries)
  DateTime? _lastAutoConnect;
  // Subscription for BLE connection state changes
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  // Subscription for BLE file download notifications
  StreamSubscription<List<int>>? _downloadSub;
  // Subscription for BLE adapter state changes (on/off)
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  // Timer for periodic BLE auto-scan
  Timer? _autoScanTimer;
  // Timer for periodic file list refresh while logging
  Timer? _fileRefreshTimer;
  // Set of device IDs logged during scan (to avoid duplicate logs)
  final Set<String> _loggedDevices = {};

  // Start periodic timer to auto-scan for BLE devices
  // Start or restart a periodic timer to automatically scan for BLE devices every 30 seconds
  void _startAutoScanTimer() {
    _autoScanTimer?.cancel();
    _autoScanTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      // Skip scan if widget is disposed, already connected, or scanning in progress
      if (!mounted) return;
      if (connected) return;
      if (_isScanning) return;
      scanDevices();
    });
  }

  // Start periodic timer to refresh file list while logging
  // Start or restart a periodic timer to refresh the file list every 10 seconds while logging
  void _startFileRefreshTimer() {
    _fileRefreshTimer?.cancel();
    _fileRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // Only refresh if still mounted, connected, logging, and not busy
      if (!mounted) return;
      if (!connected || !isLogging || busy) return;
      if (cmdChar == null || fileChar == null) return;
      // Refresh file list from device
      unawaited(_loadFileList(clearBeforeLoad: false));
    });
  }

  // Stop periodic file refresh timer
  // Stop and clear the periodic file refresh timer
  void _stopFileRefreshTimer() {
    _fileRefreshTimer?.cancel();
    _fileRefreshTimer = null;
  }

  @override
  void initState() {
    super.initState();
    // Listen for BLE adapter state changes (on/off) and react accordingly
    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      if (state == BluetoothAdapterState.off) {
        // Bluetooth turned off: clear state and inform user
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
        // Bluetooth enabled: start auto-scan
        showMsg('Bluetooth enabled');
        _startAutoScanTimer();
        scanDevices();
      }
    });
    // Start scan and auto-scan after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scanDevices();
      _startAutoScanTimer();
    });
  }

  // Sort file list alphabetically
  // Sort the list of files alphabetically (case-insensitive)
  void _sortFiles() {
    files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  // Show a message as a SnackBar
  // Show a message at the bottom of the screen using a SnackBar
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

  // Show a dialog to prompt for required permissions or settings
  // Show a requirements dialog prompting the user to grant permissions or open settings
  Future<void> showRequirementDialog(
    String title,
    String message, {
    bool locationSettings = false,
  }) async {
    if (!mounted) return;
    // Show an AlertDialog with provided title/message and relevant actions
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
                  // Open system location settings via platform channel
                  // Open Android system Location settings via platform channel
                  await const MethodChannel(
                    'app.channel.shared/settings',
                  ).invokeMethod('openLocationSettings');
                  // After a short delay, check if location was enabled and trigger scan if needed
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

  // Ensure Bluetooth and location permissions are granted and adapter is ON
  Future<bool> _prepareBluetoothAndPermissions() async {
    // Request Bluetooth and location permissions
    // Request Bluetooth and location permissions from the user
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
    // Check Bluetooth adapter state (on/off)
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      showMsg('Bluetooth is OFF. Requesting enable...');
      try {
        // Attempt to programmatically turn on Bluetooth (if supported)
        await FlutterBluePlus.turnOn();
      } catch (_) {
        await showRequirementDialog(
          'Bluetooth Required',
          'Please enable Bluetooth to use NAPPNU.',
        );
        return false;
      }
      // Wait for adapter to become enabled, with timeout
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

  // Scan for nearby BLE devices and update devices list
  Future<void> scanDevices() async {
    // Prevent concurrent scans
    // Prevent starting a scan if one is already running
    if (_isScanning) {
      showMsg('Scan already in progress');
      return;
    }
    // Ensure permissions and BLE adapter are ready before scanning
    if (!await _prepareBluetoothAndPermissions()) {
      return;
    }
    // Cancel any previous scan subscription and clear device lists
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
    // Listen to scan results and update device list
    // Listen for BLE scan results and process discovered devices
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      final updated = List<BluetoothDevice>.from(devices);
      // Iterate over each scan result and filter for MotionLogger/NAPPNU devices
      for (final r in results) {
        final name = r.device.platformName;
        final advName = r.advertisementData.advName;
        final deviceName = name.isNotEmpty ? name : advName;
        final lowerNameForLog = deviceName.toLowerCase();
        // Only log and show devices matching MotionLogger patterns
        final isOurDevice =
            lowerNameForLog.startsWith('motionlo') ||
            lowerNameForLog.startsWith('motion') ||
            lowerNameForLog.startsWith('nappnu');
        // Log only unique devices matching our device name patterns
        if (isOurDevice && _loggedDevices.add(r.device.remoteId.str)) {
          debugPrint(
            'FOUND DEVICE: $deviceName SERVICES=${r.advertisementData.serviceUuids}',
          );
        }
        if (deviceName.isEmpty) continue;
        if (!updated.any((d) => d.remoteId == r.device.remoteId)) {
          // Add unique device by remoteId to updated list
          updated.add(r.device);
        }
        final lowerName = deviceName.toLowerCase();
        final canAutoConnect =
            _lastAutoConnect == null ||
            DateTime.now().difference(_lastAutoConnect!) >
                const Duration(seconds: 10);
        // Auto-connect to first NAPPNU device found (if not already connecting)
        // Automatically connect to the first matching device if not already connecting
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
        // Start BLE scan for a fixed timeout
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      } on PlatformException catch (e) {
        if ((e.message ?? '').contains('Bluetooth must be turned on')) {
          showMsg('Bluetooth is OFF. Please enable it and try again.');
          return;
        }
        rethrow;
      }
      // Wait for scan to finish
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

  // Connect/disconnect from the selected BLE device and set up listeners
  Future<void> toggleDevice(BluetoothDevice device) async {
    // If already connected to this device, disconnect
    // If already connected to this device, disconnect and reset state
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
      // Connect to device with high MTU and priority for better throughput
      // Connect to the device with nonprofit license and timeout
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      try {
        // Set maximum MTU for improved throughput
        await device.requestMtu(247);
      } catch (_) {}
      try {
        // Request high connection priority for best performance
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
      } catch (_) {}
      // Discover BLE services and find required characteristics
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
      // Listen for device disconnects and update UI accordingly
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
      // Show connected device name in UI
      final name = device.platformName.isEmpty
          ? device.remoteId.str
          : device.platformName;
      showMsg('Connected to $name');
      // Stop auto-scan while connected
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

  // Retrieve file list from device and update UI
  Future<void> listFiles() async {
    // Ensure connected and not busy before listing files
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

  // Internal: enable notifications on fileChar and collect filenames until EOF
  Future<void> _loadFileList({bool clearBeforeLoad = true}) async {
    // List to collect received filenames
    final receivedFiles = <String>[];
    // Map to track file indexes as reported by device
    final receivedIndexes = <String, int>{};
    // Completer to signal when EOF or error is received
    final completer = Completer<void>();
    Timer? timeoutTimer;

    void finish() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    // Optionally clear current file list before loading new list
    if (clearBeforeLoad && mounted) {
      setState(() {
        files.clear();
        _fileIndexes.clear();
      });
    } else if (clearBeforeLoad) {
      files.clear();
      _fileIndexes.clear();
    }

    // Listen for file notifications and parse filenames from BLE packets
    // Listen for filename notifications from device and handle EOF/errors
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
    // Enable notifications before sending LIST command
    await fileChar!.setNotifyValue(true);
    await Future.delayed(const Duration(milliseconds: 250));
    // Start a timeout to avoid hanging if device fails to respond
    timeoutTimer = Timer(const Duration(seconds: 5), finish);
    debugPrint('BLE LIST CMD: LIST');
    await cmdChar!.write('LIST'.codeUnits, withoutResponse: false);
    await completer.future;
    } finally {
      timeoutTimer?.cancel();
      await sub.cancel();
    }

    if (!mounted) return;

    // Update UI with new file list if changed
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

  // Start a file download and save received bytes via file picker
  Future<void> downloadFile(String filename) async {
    // Ensure connected and not busy before starting download
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
      // Prevent downloads while file indexes are stale
      showMsg('Refresh files and try again');
      return;
    }

    if (isLogging) {
      // Confirm download while logging is active (file may change during download)
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

    // Set busy state and show download message
    setState(() => busy = true);
    showMsg('Downloading: $filename');

    try {
      // Receive file bytes from device
      final bytes = await _receiveDownload(fileIndex);
      // Prompt user to save file using file picker
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
      // Cancel BLE notification subscription and clear busy state
      await _downloadSub?.cancel();
      _downloadSub = null;
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  // Download file by index and assemble raw bytes from BLE notifications
  Future<Uint8List> _receiveDownload(int index) async {
    // Completer to signal when download is complete
    final completer = Completer<Uint8List>();
    // Assemble incoming file data
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

    // Cancel previous download subscription if any
    await _downloadSub?.cancel();
    _downloadSub = null;
    // Listen for file data notifications and assemble file bytes
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
    // Cancel subscription if device disconnects during download
    selectedDevice?.cancelWhenDisconnected(sub);
    _downloadSub = sub;
    try {
    // Enable notifications before sending GET command
    await fileChar!.setNotifyValue(true);
    await Future.delayed(const Duration(milliseconds: 250));
    // Start download timeout
    resetTimeout();
    final command = 'G:$index';
    debugPrint('BLE DOWNLOAD CMD: $command');
    // Send download command to device
    await cmdChar!.write(command.codeUnits, withoutResponse: false);
    // Wait for file bytes to be received
    return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      await sub.cancel();
      if (identical(_downloadSub, sub)) {
        _downloadSub = null;
      }
    }
  }

  // Extract CSV filenames from a BLE text packet
  // Extract CSV filenames from a BLE text packet using regex
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

  // Sanitize filename for download
  // Sanitize filename for download (remove illegal characters, ensure .csv extension)
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

  // Send delete command for the selected file and update UI on success
  Future<void> deleteFile(String filename) async {
    // Ensure connected and not logging before deleting files
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

    // Confirm file deletion with user
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
      // Send DELETE command to device for the file index
      await cmdChar!.write('D:$fileIndex'.codeUnits, withoutResponse: false);
      setState(() {
        files.remove(filename);
        _fileIndexes.remove(filename);
      });
      showMsg('Deleted: $filename');
      // Refresh file list after short delay to reflect changes
      Future.delayed(const Duration(milliseconds: 400), () async {
        if (mounted && connected) {
          await listFiles();
        }
      });
    } catch (e) {
      showMsg('Delete failed: $e');
    }
  }

  // Send START command to device to begin logging and enable refresh
  void startLogging() async {
    // Start logging only if connected and not already logging
    if (!connected || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    if (isLogging) {
      showMsg('Already logging');
      return;
    }

    try {
      // Send START command to device
      await cmdChar!.write('START'.codeUnits, withoutResponse: false);

      setState(() {
        isLogging = true;
      });
      // Start periodic file refresh while logging
      _startFileRefreshTimer();
      unawaited(_loadFileList(clearBeforeLoad: false));

      showMsg('Logging started');
    } catch (e) {
      showMsg('START failed: $e');
    }
  }

  // Send STOP command to device to stop logging and disable refresh
  void stopLogging() async {
    // Stop logging only if connected and currently logging
    if (!connected || cmdChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    if (!isLogging) {
      showMsg('Logging already stopped');
      return;
    }

    try {
      // Send STOP command to device
      await cmdChar!.write('STOP'.codeUnits, withoutResponse: false);

      setState(() {
        isLogging = false;
      });
      // Stop periodic file refresh when not logging
      _stopFileRefreshTimer();

      showMsg('Logging stopped');
    } catch (e) {
      showMsg('STOP failed: $e');
    }
  }

  // Query device status (LOGGING/STOPPED) via fileChar notifications
  Future<void> getStatus() async {
    if (!connected || cmdChar == null || fileChar == null) {
      showMsg('Connect to MotionLogger first');
      return;
    }

    // Enable notifications to receive status from device
    await fileChar!.setNotifyValue(true);
    // Listen for status notification via BLE
    late final StreamSubscription<List<int>> sub;
    sub = fileChar!.onValueReceived.listen((data) async {
      final msg = String.fromCharCodes(data).trim();
      if (msg == 'LOGGING' || msg == 'STOPPED') {
        setState(() {
          isLogging = msg == 'LOGGING';
        });
        // Start/stop file refresh timer based on logging state
        if (isLogging) {
          _startFileRefreshTimer();
        } else {
          _stopFileRefreshTimer();
        }
        showMsg('Status: $msg');
        await sub.cancel();
      }
    });
    // Send STATUS command to device
    await cmdChar!.write('STATUS'.codeUnits, withoutResponse: false);
  }

  // Clean up timers, subscriptions, and BLE listeners on dispose
  @override
  void dispose() {
    // Cancel all timers and BLE subscriptions to avoid leaks
    // Cancel all timers and subscriptions to avoid memory leaks
    _autoScanTimer?.cancel();
    _scanSubscription?.cancel();
    _adapterStateSub?.cancel();
    _connectionSub?.cancel();
    _downloadSub?.cancel();
    _stopFileRefreshTimer();
    super.dispose();
  }

  // Build the main screen with connection status, files, and logging controls
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // App bar with info/about dialog
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
              // Show about dialog with app and company info
              showAboutDialog(
              context: context,
              applicationName: 'NAPPNU',
              applicationVersion: 'Version 1.0.0',
              applicationIcon: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.sensors_rounded,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              children: [
                const SizedBox(height: 8),

                const Divider(),

                const SizedBox(height: 12),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.monitor_heart_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'NAPPNU is a Bluetooth Low Energy (BLE) motion recorder that '
                        'logs timestamped IMU data to a microSD card and allows wireless '
                        'file transfer to a smartphone.',
                        style: TextStyle(fontSize: 15, height: 1.45),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                const Divider(),

                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.code_rounded,
                      size: 42,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Developed by',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              final uri = Uri.parse(
                                'https://suxmasystems.com/',
                              );

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
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Motion recorder firmware and mobile application.',
                            style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                const Divider(),

                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 42,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Copyright',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '© 2026 SUXMA Systems Pvt. Ltd.\n'
                            'All rights reserved.',
                            style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
              ],
            );
            },
          ),
        ],
      ),
      // Floating action button group for theme selection
      // Floating action button for theme selection and palette menu
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Theme palette menu options
          // Show theme palette menu if open
          if (_themeMenuOpen) ...[
            FloatingActionButton.small(
              heroTag: 'light_theme',
              tooltip: 'Light Theme',
              onPressed: () {
                // Switch to light theme
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
                // Switch to dark theme
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
                // Switch to graphite theme
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
              // Toggle theme palette menu
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
      // Main body: connection, files, and controls
      // Main body with device connection, file list, and controls
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          // Pull-to-refresh for file/device list
          child: RefreshIndicator(
            onRefresh: () async {
              // Refresh files if connected, otherwise scan for devices
              if (connected) {
                await listFiles();
              } else {
                await scanDevices();
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 90),
              // Main content column
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Discovery/connect section: scan, device dropdown, connection state
                  // Device discovery and connection section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          // Scan BLE button with progress indicator
                          // Scan BLE button and progress indicator
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
                          // BLE device dropdown and connection status
                          // BLE device dropdown and connection status
                          Expanded(
                            child: Row(
                              children: [
                                // BLE device dropdown list
                                // BLE device dropdown list
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
                                                // Handle device selection from dropdown
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
                                    // Connection status and disconnect button
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
                                          // Disconnect from selected device and reset state
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

                  // File list header and refresh button
                  // File list header and refresh button
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
                  // List of motion log files with download/delete buttons
                  // List of motion log files with download and delete buttons
                  if (files.isNotEmpty)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final file = files[index];

                        // File row containing filename, download, and delete buttons
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
                              // File icon
                              const Icon(Icons.description_outlined, size: 18),
                              const SizedBox(width: 10),
                              // Filename text
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
                              // Download and delete buttons for each file
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

                  // Logging control panel: start/stop logging
                  // Logging control panel: start/stop logging and state indicator
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
                          // Status indicator for logging state
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
                          // Row of logging control buttons (start/stop)
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
                                // Start logging button
                                IconButton(
                                  tooltip: 'Start Logging',
                                  onPressed: connected && !isLogging
                                      ? startLogging
                                      : null,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  color: Colors.green,
                                  visualDensity: VisualDensity.compact,
                                ),
                                // Stop logging button
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
