import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/connected_device.dart';
import '../services/android_device_runner_service.dart';

/// Sentinel marker to allow explicitly setting nullable fields in copyWith.
const Object _unset = Object();

/// Immutable state representing connected Android devices and any active debug session.
@immutable
class AndroidDebugState {
  final List<ConnectedAndroidDevice> devices;
  final ConnectedAndroidDevice? selectedDevice;
  final DeviceRunStatus status;
  final String? activeAppId;
  final String? projectPath;
  final String? vmServiceUri;
  final String? devToolsUri;
  final String? progressMessage;
  final String? errorMessage;
  final AndroidConnectionDiagnostic? lastDiagnostic;
  final List<DeviceLogEntry> logs;

  const AndroidDebugState({
    this.devices = const [],
    this.selectedDevice,
    this.status = DeviceRunStatus.idle,
    this.activeAppId,
    this.projectPath,
    this.vmServiceUri,
    this.devToolsUri,
    this.progressMessage,
    this.errorMessage,
    this.lastDiagnostic,
    this.logs = const [],
  });

  bool get hasConnectedDevice => devices.isNotEmpty;

  bool get isActiveSession =>
      status == DeviceRunStatus.launching ||
      status == DeviceRunStatus.running ||
      status == DeviceRunStatus.reloading;

  bool get isRunningOrReloading =>
      status == DeviceRunStatus.running || status == DeviceRunStatus.reloading;

  AndroidDebugState copyWith({
    List<ConnectedAndroidDevice>? devices,
    Object? selectedDevice = _unset,
    DeviceRunStatus? status,
    Object? activeAppId = _unset,
    Object? projectPath = _unset,
    Object? vmServiceUri = _unset,
    Object? devToolsUri = _unset,
    Object? progressMessage = _unset,
    Object? errorMessage = _unset,
    Object? lastDiagnostic = _unset,
    List<DeviceLogEntry>? logs,
  }) {
    return AndroidDebugState(
      devices: devices ?? this.devices,
      selectedDevice: identical(selectedDevice, _unset)
          ? this.selectedDevice
          : selectedDevice as ConnectedAndroidDevice?,
      status: status ?? this.status,
      activeAppId: identical(activeAppId, _unset)
          ? this.activeAppId
          : activeAppId as String?,
      projectPath: identical(projectPath, _unset)
          ? this.projectPath
          : projectPath as String?,
      vmServiceUri: identical(vmServiceUri, _unset)
          ? this.vmServiceUri
          : vmServiceUri as String?,
      devToolsUri: identical(devToolsUri, _unset)
          ? this.devToolsUri
          : devToolsUri as String?,
      progressMessage: identical(progressMessage, _unset)
          ? this.progressMessage
          : progressMessage as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      lastDiagnostic: identical(lastDiagnostic, _unset)
          ? this.lastDiagnostic
          : lastDiagnostic as AndroidConnectionDiagnostic?,
      logs: logs ?? this.logs,
    );
  }
}

/// Manages Android device discovery, live `flutter run --machine` debug sessions,
/// and automatic debounced Hot Reload on file saves.
class AndroidDebugNotifier extends StateNotifier<AndroidDebugState> {
  final AndroidDeviceRunnerService _service;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  Timer? _reloadDebounceTimer;
  int _nextRequestId = 1;
  final Map<int, String> _pendingRpcMethods = {};

  static const int _maxLogEntries = 400;

  AndroidDebugNotifier(this._service) : super(const AndroidDebugState());

  void _appendLog(
    String rawMessage, {
    bool isError = false,
    bool isSystem = false,
  }) {
    if (!mounted) return;
    final clean = rawMessage.trimRight();
    if (clean.isEmpty) return;

    final updated = List<DeviceLogEntry>.from(state.logs)
      ..add(
        DeviceLogEntry(
          timestamp: DateTime.now(),
          message: clean,
          isError: isError,
          isSystem: isSystem,
        ),
      );
    if (updated.length > _maxLogEntries) {
      updated.removeRange(0, updated.length - _maxLogEntries);
    }
    state = state.copyWith(logs: updated);
  }

  /// Scans connected Android devices via `flutter devices --machine` and runs
  /// USB/ADB/SDK environment diagnostics whenever no ready device is found.
  Future<void> scanDevices() async {
    if (kIsWeb || state.status == DeviceRunStatus.scanning) return;

    final previousStatus = state.status;
    if (!state.isActiveSession) {
      state = state.copyWith(
        status: DeviceRunStatus.scanning,
        errorMessage: null,
      );
    }

    try {
      final diagnostic = await _service.scanAndroidEnvironment();
      if (!mounted) return;

      final devices = diagnostic.devices;
      ConnectedAndroidDevice? nextSelected = state.selectedDevice;
      if (nextSelected == null ||
          !devices.any((d) => d.id == nextSelected!.id)) {
        nextSelected = devices.isNotEmpty ? devices.first : null;
      }

      final isScanError =
          diagnostic.issueType == AndroidConnectionIssueType.scanError;
      if (isScanError) {
        _appendLog('Erro ao buscar aparelhos Android: ${diagnostic.summary}',
            isError: true);
      }

      state = state.copyWith(
        devices: devices,
        selectedDevice: nextSelected,
        lastDiagnostic: diagnostic,
        status: state.isActiveSession
            ? previousStatus
            : DeviceRunStatus.idle,
        errorMessage: isScanError ? diagnostic.summary : null,
      );
    } catch (e) {
      if (!mounted) return;
      _appendLog('Erro ao buscar aparelhos Android: $e', isError: true);
      state = state.copyWith(
        status: state.isActiveSession ? previousStatus : DeviceRunStatus.idle,
        errorMessage: e.toString(),
      );
    }
  }

  /// Configures Flutter CLI `--android-sdk` and immediately re-scans connected devices.
  Future<bool> configureAndroidSdk(String sdkPath) async {
    final ok = await _service.configureFlutterAndroidSdk(sdkPath);
    if (!mounted) return ok;
    await scanDevices();
    return ok;
  }

  void selectDevice(ConnectedAndroidDevice device) {
    state = state.copyWith(selectedDevice: device);
  }

  /// Launches the project in [projectPath] on [device] (or `state.selectedDevice`).
  Future<bool> launchProject(
    String projectPath, {
    ConnectedAndroidDevice? device,
  }) async {
    if (kIsWeb) {
      _appendLog(
        'Execução direta em dispositivo Android requer o aplicativo Desktop (Windows/macOS/Linux).',
        isError: true,
      );
      return false;
    }

    final targetDevice = device ?? state.selectedDevice;
    if (targetDevice == null) {
      state = state.copyWith(
        status: DeviceRunStatus.error,
        errorMessage: 'Nenhum aparelho Android selecionado.',
      );
      return false;
    }

    final projectDir = Directory(projectPath);
    final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
    if (!projectDir.existsSync() || !pubspecFile.existsSync()) {
      final msg =
          'Projeto Flutter inválido ou sem pubspec.yaml em: $projectPath';
      _appendLog(msg, isError: true);
      state = state.copyWith(
        status: DeviceRunStatus.error,
        errorMessage: msg,
      );
      return false;
    }

    // Stop any previous session before launching a new one.
    await stopSession(silent: true);
    if (!mounted) return false;

    state = state.copyWith(
      selectedDevice: targetDevice,
      status: DeviceRunStatus.launching,
      activeAppId: null,
      projectPath: p.normalize(projectPath),
      vmServiceUri: null,
      devToolsUri: null,
      progressMessage: 'Preparando build para ${targetDevice.name}...',
      errorMessage: null,
      logs: const [],
    );

    _appendLog(
      '🚀 Lançando app em tempo real no ${targetDevice.displayLabel} (${targetDevice.id})...',
      isSystem: true,
    );

    try {
      final proc = await _service.startAppProcess(
        projectPath: projectPath,
        deviceId: targetDevice.id,
      );
      if (!mounted) {
        await _service.killProcessTree(proc);
        return false;
      }

      _process = proc;

      _stdoutSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleStdoutLine);

      _stderrSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          _appendLog(line, isError: true);
        }
      });

      unawaited(proc.exitCode.then((code) {
        if (!mounted || _process != proc) return;
        final wasRunning = state.isActiveSession;
        _cleanupSubscriptions();
        _process = null;

        if (wasRunning && code != 0) {
          state = state.copyWith(
            status: DeviceRunStatus.error,
            activeAppId: null,
            progressMessage: null,
            errorMessage: 'Processo encerrado com código $code.',
          );
        } else if (state.status != DeviceRunStatus.error) {
          state = state.copyWith(
            status: DeviceRunStatus.idle,
            activeAppId: null,
            progressMessage: null,
          );
        }
      }));

      return true;
    } catch (e) {
      if (!mounted) return false;
      _appendLog('❌ Falha ao iniciar flutter run: $e', isError: true);
      state = state.copyWith(
        status: DeviceRunStatus.error,
        errorMessage: e.toString(),
        progressMessage: null,
      );
      return false;
    }
  }

  void _handleStdoutLine(String line) {
    if (!mounted) return;
    final parsed = AndroidDeviceRunnerService.parseDaemonMessageLine(line);
    if (parsed == null) {
      _appendLog(line);
      return;
    }

    // Handle RPC response to commands we sent (app.restart, app.stop, etc.).
    if (parsed.containsKey('id')) {
      final id = parsed['id'];
      final method = id is int ? _pendingRpcMethods.remove(id) : null;
      final error = parsed['error'];
      if (error != null) {
        _appendLog('❌ Erro ($method): $error', isError: true);
        if (state.status == DeviceRunStatus.reloading) {
          state = state.copyWith(status: DeviceRunStatus.running);
        }
        return;
      }

      final result = parsed['result'];
      if (method == 'app.restart') {
        if (result is Map && result['code'] != null && result['code'] != 0) {
          _appendLog(
            '⚠️ Hot Reload falhou: ${result['message'] ?? result['code']}',
            isError: true,
          );
        } else {
          _appendLog(
            '⚡ Hot Reload concluído no ${state.selectedDevice?.name ?? "dispositivo"}!',
            isSystem: true,
          );
        }
        if (state.status == DeviceRunStatus.reloading) {
          state = state.copyWith(
            status: DeviceRunStatus.running,
            progressMessage: null,
          );
        }
      }
      return;
    }

    final event = parsed['event']?.toString();
    final rawParams = parsed['params'];
    final params = rawParams is Map
        ? Map<String, dynamic>.from(rawParams)
        : const <String, dynamic>{};

    switch (event) {
      case 'app.start':
        final appId = params['appId']?.toString();
        state = state.copyWith(
          activeAppId: appId,
          status: DeviceRunStatus.launching,
        );
        break;

      case 'app.progress':
        final finished = params['finished'] == true;
        final message = params['message']?.toString();
        if (!finished && message != null && message.isNotEmpty) {
          state = state.copyWith(progressMessage: message);
          _appendLog('⏳ $message', isSystem: true);
        } else if (finished && state.progressMessage != null) {
          state = state.copyWith(progressMessage: null);
        }
        break;

      case 'app.debugPort':
        final wsUri = params['wsUri']?.toString();
        state = state.copyWith(vmServiceUri: wsUri);
        if (wsUri != null) {
          _appendLog('🔌 VM Service ativo: $wsUri', isSystem: true);
        }
        break;

      case 'app.devTools':
        final uri = params['uri']?.toString();
        state = state.copyWith(devToolsUri: uri);
        break;

      case 'app.started':
        state = state.copyWith(
          status: DeviceRunStatus.running,
          progressMessage: null,
          errorMessage: null,
        );
        _appendLog(
          '✅ App em execução em tempo real no ${state.selectedDevice?.name ?? "Android"}! Edições salvas serão aplicadas via Hot Reload.',
          isSystem: true,
        );
        break;

      case 'app.log':
        final logText = params['log']?.toString() ?? '';
        final isErr = params['error'] == true;
        if (logText.isNotEmpty) {
          _appendLog(logText, isError: isErr);
        }
        break;

      case 'app.stop':
        final stopErr = params['error']?.toString();
        if (stopErr != null && stopErr.isNotEmpty) {
          _appendLog('❌ Sessão encerrada com erro: $stopErr', isError: true);
          state = state.copyWith(
            status: DeviceRunStatus.error,
            activeAppId: null,
            progressMessage: null,
            errorMessage: stopErr,
          );
        } else {
          _appendLog('⏹️ App encerrado no dispositivo.', isSystem: true);
          state = state.copyWith(
            status: DeviceRunStatus.idle,
            activeAppId: null,
            progressMessage: null,
          );
        }
        break;

      case 'daemon.logMessage':
        final msg = params['message']?.toString() ?? '';
        final level = params['level']?.toString() ?? '';
        if (msg.isNotEmpty) {
          _appendLog(msg, isError: level == 'error');
        }
        break;

      default:
        break;
    }
  }

  void _sendRpcCommand(String method, Map<String, dynamic> params) {
    final proc = _process;
    if (proc == null) return;

    final id = _nextRequestId++;
    _pendingRpcMethods[id] = method;
    final payload = AndroidDeviceRunnerService.encodeDaemonCommand(
      id: id,
      method: method,
      params: params,
    );
    try {
      proc.stdin.write(payload);
    } catch (e) {
      _appendLog('Erro ao enviar comando ($method): $e', isError: true);
    }
  }

  /// Sends a Hot Reload command (`app.restart`, `fullRestart: false`) to the running device.
  Future<void> hotReload({String reason = 'manual'}) async {
    final appId = state.activeAppId;
    if (!state.isRunningOrReloading || appId == null || _process == null) {
      return;
    }

    state = state.copyWith(status: DeviceRunStatus.reloading);
    _appendLog('⚡ Executando Hot Reload ($reason)...', isSystem: true);
    _sendRpcCommand('app.restart', {
      'appId': appId,
      'fullRestart': false,
      'reason': reason,
    });
  }

  /// Sends a full Hot Restart command (`app.restart`, `fullRestart: true`) to the running device.
  Future<void> hotRestart() async {
    final appId = state.activeAppId;
    if (!state.isRunningOrReloading || appId == null || _process == null) {
      return;
    }

    state = state.copyWith(status: DeviceRunStatus.reloading);
    _appendLog('🔄 Executando Hot Restart...', isSystem: true);
    _sendRpcCommand('app.restart', {
      'appId': appId,
      'fullRestart': true,
      'reason': 'restart',
    });
  }

  /// Called when code inside [projectPath] is persisted to disk (Editor save, AI generation, Widget Studio).
  /// Debounces rapid writes and triggers real-time Hot Reload if an Android session is running for that project.
  void onCodeSaved(String projectPath) {
    if (!state.isRunningOrReloading || state.projectPath == null) return;

    final activeNorm = p.normalize(state.projectPath!).toLowerCase();
    final savedNorm = p.normalize(projectPath).toLowerCase();
    if (activeNorm != savedNorm) return;

    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && state.isRunningOrReloading) {
        hotReload(reason: 'save');
      }
    });
  }

  /// Stops the active Android debug session and terminates child processes cleanly.
  Future<void> stopSession({bool silent = false}) async {
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = null;

    final proc = _process;
    final appId = state.activeAppId;
    _process = null;

    if (proc != null) {
      if (appId != null) {
        try {
          final id = _nextRequestId++;
          proc.stdin.write(
            AndroidDeviceRunnerService.encodeDaemonCommand(
              id: id,
              method: 'app.stop',
              params: {'appId': appId},
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 250));
        } catch (_) {}
      }
      _cleanupSubscriptions();
      await _service.killProcessTree(proc);
    } else {
      _cleanupSubscriptions();
    }

    _pendingRpcMethods.clear();

    if (!mounted) return;
    if (!silent) {
      _appendLog('⏹️ Debug no aparelho encerrado.', isSystem: true);
      state = state.copyWith(
        status: DeviceRunStatus.idle,
        activeAppId: null,
        vmServiceUri: null,
        devToolsUri: null,
        progressMessage: null,
      );
    }
  }

  void clearLogs() {
    state = state.copyWith(logs: const []);
  }

  void dismissError() {
    state = state.copyWith(
      status: DeviceRunStatus.idle,
      errorMessage: null,
    );
  }

  void _cleanupSubscriptions() {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
  }

  @override
  void dispose() {
    _reloadDebounceTimer?.cancel();
    _cleanupSubscriptions();
    final proc = _process;
    _process = null;
    if (proc != null) {
      _service.killProcessTree(proc);
    }
    super.dispose();
  }
}

final androidDeviceRunnerServiceProvider =
    Provider<AndroidDeviceRunnerService>((ref) {
  return AndroidDeviceRunnerService();
});

final androidDebugProvider =
    StateNotifierProvider<AndroidDebugNotifier, AndroidDebugState>((ref) {
  final service = ref.watch(androidDeviceRunnerServiceProvider);
  return AndroidDebugNotifier(service);
});
