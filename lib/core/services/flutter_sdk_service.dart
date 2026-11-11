import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FlutterSdkStatus {
  final bool isInstalled;
  final String? version;
  final String? sdkPath;
  final bool isChecking;
  final String? error;

  const FlutterSdkStatus({
    required this.isInstalled,
    this.version,
    this.sdkPath,
    this.isChecking = false,
    this.error,
  });

  factory FlutterSdkStatus.initial() => const FlutterSdkStatus(
        isInstalled: false,
        isChecking: true,
      );

  factory FlutterSdkStatus.detected({
    required String version,
    required String sdkPath,
  }) =>
      FlutterSdkStatus(
        isInstalled: true,
        version: version,
        sdkPath: sdkPath,
        isChecking: false,
      );

  factory FlutterSdkStatus.missing({String? error}) => FlutterSdkStatus(
        isInstalled: false,
        isChecking: false,
        error: error,
      );

  factory FlutterSdkStatus.webSandbox() => const FlutterSdkStatus(
        isInstalled: true,
        version: 'Web Sandbox',
        sdkPath: 'Browser Environment',
        isChecking: false,
      );
}

class FlutterSdkNotifier extends StateNotifier<FlutterSdkStatus> {
  FlutterSdkNotifier() : super(FlutterSdkStatus.initial()) {
    checkSdk();
  }

  Future<void> checkSdk() async {
    if (kIsWeb) {
      state = FlutterSdkStatus.webSandbox();
      return;
    }

    state = const FlutterSdkStatus(isInstalled: false, isChecking: true);

    try {
      final isWindows = Platform.isWindows;
      final locatorCmd = isWindows ? 'where.exe' : 'which';
      final locatorRes = await Process.run(
        locatorCmd,
        ['flutter'],
        runInShell: isWindows,
      );

      if (locatorRes.exitCode != 0) {
        state = FlutterSdkStatus.missing(
          error: 'Flutter executable not found in system PATH.',
        );
        return;
      }

      final resolvedPath = locatorRes.stdout
          .toString()
          .split(RegExp(r'[\r\n]+'))
          .where((line) => line.trim().isNotEmpty)
          .firstOrNull ?? 'flutter';

      // Fetch version string from flutter --version
      final versionRes = await Process.run(
        'flutter',
        ['--version'],
        runInShell: true,
      );

      String version = 'Ready';
      if (versionRes.exitCode == 0) {
        final output = versionRes.stdout.toString();
        final match = RegExp(r'Flutter\s+(\d+\.\d+(\.\d+)?)').firstMatch(output);
        if (match != null) {
          version = 'v${match.group(1)}';
        }
      }

      state = FlutterSdkStatus.detected(
        version: version,
        sdkPath: resolvedPath,
      );
    } catch (e) {
      state = FlutterSdkStatus.missing(error: e.toString());
    }
  }
}

final flutterSdkProvider =
    StateNotifierProvider<FlutterSdkNotifier, FlutterSdkStatus>((ref) {
  return FlutterSdkNotifier();
});
