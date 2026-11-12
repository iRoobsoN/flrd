import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/connected_device.dart';

typedef ProcessRunnerFn = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell,
});

typedef ProcessStarterFn = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell,
});

/// Handles detection of connected Android devices and execution of
/// `flutter run --machine` sessions with JSON-RPC Hot Reload / Hot Restart.
class AndroidDeviceRunnerService {
  final ProcessRunnerFn _processRunner;
  final ProcessStarterFn _processStarter;

  AndroidDeviceRunnerService({
    ProcessRunnerFn? processRunner,
    ProcessStarterFn? processStarter,
  })  : _processRunner = processRunner ?? _defaultProcessRunner,
        _processStarter = processStarter ?? _defaultProcessStarter;

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = true,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
  }

  static Future<Process> _defaultProcessStarter(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = true,
  }) {
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
  }

  /// Queries `flutter devices --machine` and returns supported Android devices,
  /// prioritizing physical hardware phones ahead of emulators.
  Future<List<ConnectedAndroidDevice>> scanAndroidDevices() async {
    if (kIsWeb) return const [];

    final result = await _processRunner(
      'flutter',
      const ['devices', '--machine'],
      runInShell: Platform.isWindows,
    );

    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw ProcessException(
        'flutter',
        const ['devices', '--machine'],
        err.isNotEmpty ? err : 'Exited with code ${result.exitCode}',
        result.exitCode,
      );
    }

    return parseDevicesOutput(result.stdout.toString());
  }

  /// Parses JSON output from `flutter devices --machine`, extracting Android devices.
  static List<ConnectedAndroidDevice> parseDevicesOutput(String rawStdout) {
    final trimmed = rawStdout.trim();
    if (trimmed.isEmpty) return const [];

    // Locate the outermost JSON array in case Flutter CLI prepends tool logs.
    final startIdx = trimmed.indexOf('[');
    final endIdx = trimmed.lastIndexOf(']');
    if (startIdx == -1 || endIdx <= startIdx) return const [];

    final jsonSlice = trimmed.substring(startIdx, endIdx + 1);
    final decoded = jsonDecode(jsonSlice);
    if (decoded is! List) return const [];

    final devices = <ConnectedAndroidDevice>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      if (map['isSupported'] == false) continue;

      final platform = (map['targetPlatform'] ?? '').toString().toLowerCase();
      final sdk = (map['sdk'] ?? '').toString().toLowerCase();
      if (!platform.contains('android') && !sdk.contains('android')) continue;

      final device = ConnectedAndroidDevice.fromFlutterJson(map);
      if (device.id.isNotEmpty) {
        devices.add(device);
      }
    }

    // Physical devices first, then emulators alphabetically.
    devices.sort((a, b) {
      if (a.isEmulator != b.isEmulator) {
        return a.isEmulator ? 1 : -1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return devices;
  }

  /// Spawns an interactive `flutter run --machine -d <deviceId>` daemon process.
  Future<Process> startAppProcess({
    required String projectPath,
    required String deviceId,
  }) {
    return _processStarter(
      'flutter',
      ['run', '--machine', '-d', deviceId],
      workingDirectory: projectPath,
      runInShell: Platform.isWindows,
    );
  }

  /// Parses a single daemon JSON-RPC line (`[{"event":...}]` or `[{"id":...}]`).
  /// Returns `null` when [line] is plain non-JSON tool output.
  static Map<String, dynamic>? parseDaemonMessageLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('[{') || !trimmed.endsWith('}]')) {
      return null;
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        return Map<String, dynamic>.from(decoded.first as Map);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Serializes a Flutter daemon JSON-RPC command line.
  static String encodeDaemonCommand({
    required int id,
    required String method,
    required Map<String, dynamic> params,
  }) {
    return '${jsonEncode([
      {
        'id': id,
        'method': method,
        'params': params,
      }
    ])}\n';
  }

  /// Ensures a spawned Flutter run process tree is terminated cleanly.
  Future<void> killProcessTree(Process process) async {
    try {
      if (!kIsWeb && Platform.isWindows) {
        await _processRunner(
          'taskkill',
          ['/F', '/T', '/PID', '${process.pid}'],
          runInShell: true,
        );
      } else {
        process.kill();
      }
    } catch (_) {
      try {
        process.kill();
      } catch (_) {}
    }
  }
}
