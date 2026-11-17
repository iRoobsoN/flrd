import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'doctor_analyzer.dart';
export 'doctor_analyzer.dart';

/// Service and Riverpod StateNotifier for executing `flutter doctor -v`,
/// running host PC toolchain probes, and updating diagnostic state.
class FlutterDoctorService extends StateNotifier<DoctorReport> {
  final DoctorProcessRunner _runner;
  final DoctorEnvironmentProvider? _environmentProvider;
  final bool _enableExtendedPcChecks;

  FlutterDoctorService({
    bool autoScan = true,
    DoctorProcessRunner? processRunner,
    DoctorEnvironmentProvider? environmentProvider,
    bool? enableExtendedPcChecks,
  })  : _runner = processRunner ?? DoctorAnalyzer.defaultProcessRunner,
        _environmentProvider = environmentProvider,
        _enableExtendedPcChecks =
            enableExtendedPcChecks ?? _defaultExtendedChecks(processRunner),
        super(DoctorReport.initial()) {
    if (autoScan) {
      runDoctor();
    }
  }

  static bool _defaultExtendedChecks(DoctorProcessRunner? customRunner) {
    if (customRunner != null) return false;
    if (kIsWeb) return false;
    try {
      return !Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  /// Executes `flutter doctor -v` (plus PC probes when enabled), parses and
  /// enriches the report, and updates Riverpod state safely.
  Future<DoctorReport> runDoctor() async {
    if (kIsWeb) {
      final report = DoctorReport.webSandbox();
      if (mounted) state = report;
      return report;
    }

    if (mounted) {
      state = state.copyWith(isScanning: true, error: null);
    }

    final report = await DoctorAnalyzer.runDiagnostics(
      processRunner: _runner,
      environmentProvider: _environmentProvider,
      includeExtendedPcChecks: _enableExtendedPcChecks,
    );

    if (mounted) {
      state = report;
    }
    return report;
  }

  /// Pure parser forwarding to [DoctorAnalyzer.parseDoctorOutput].
  static DoctorReport parseDoctorOutput(String rawOutput) =>
      DoctorAnalyzer.parseDoctorOutput(rawOutput);

  /// Pure item enrichment forwarding to [DoctorAnalyzer.enrichDoctorItem].
  static DoctorItem enrichDoctorItem(DoctorItem item) =>
      DoctorAnalyzer.enrichDoctorItem(item);
}

/// Global Riverpod StateNotifierProvider for [FlutterDoctorService].
final flutterDoctorProvider =
    StateNotifierProvider<FlutterDoctorService, DoctorReport>((ref) {
  return FlutterDoctorService();
});
