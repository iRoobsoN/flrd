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
      if (mounted) state = FlutterSdkStatus.webSandbox();
      return;
    }

    if (mounted) {
      state = const FlutterSdkStatus(isInstalled: false, isChecking: true);
    }

    try {
      final isWindows = !kIsWeb && Platform.isWindows;
      final locatorCmd = isWindows ? 'where.exe' : 'which';
      String resolvedPath = 'flutter';
      bool locatorFound = false;

      try {
        final locatorRes = await Process.run(
          locatorCmd,
          ['flutter'],
          runInShell: isWindows,
        );

        if (locatorRes.exitCode == 0) {
          final firstLine = locatorRes.stdout
              .toString()
              .split(RegExp(r'[\r\n]+'))
              .where((line) => line.trim().isNotEmpty)
              .firstOrNull;
          if (firstLine != null && firstLine.trim().isNotEmpty) {
            resolvedPath = firstLine.trim();
            locatorFound = true;
          }
        }
      } catch (_) {
        // Locator command (where.exe/which) missing or threw ProcessException; proceed to test flutter directly
      }

      // Fetch version string from flutter --version
      ProcessResult? versionRes;
      try {
        versionRes = await Process.run(
          'flutter',
          ['--version'],
          runInShell: true,
        );
      } catch (e) {
        // If flutter command failed and locator also didn't find it
        if (!locatorFound) {
          if (mounted) {
            state = FlutterSdkStatus.missing(
              error: 'Flutter executable not found in system PATH ($e).',
            );
          }
          return;
        }
      }

      if (versionRes != null && versionRes.exitCode == 0) {
        String version = 'Ready';
        final output = versionRes.stdout.toString();
        final match = RegExp(r'Flutter\s+(\d+\.\d+(\.\d+)?)').firstMatch(output);
        if (match != null) {
          version = 'v${match.group(1)}';
        }

        if (mounted) {
          state = FlutterSdkStatus.detected(
            version: version,
            sdkPath: resolvedPath,
          );
        }
      } else if (locatorFound) {
        // Found via locator, but --version didn't return clean output
        if (mounted) {
          state = FlutterSdkStatus.detected(
            version: 'Ready',
            sdkPath: resolvedPath,
          );
        }
      } else {
        if (mounted) {
          state = FlutterSdkStatus.missing(
            error: 'Flutter executable not found in system PATH.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        state = FlutterSdkStatus.missing(error: e.toString());
      }
    }
  }
}

final flutterSdkProvider =
    StateNotifierProvider<FlutterSdkNotifier, FlutterSdkStatus>((ref) {
  return FlutterSdkNotifier();
});
