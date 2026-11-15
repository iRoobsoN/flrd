import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../ai/services/gemini_ai_service.dart';
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
  final AndroidBuildDiagnostic? buildDiagnostic;
  final bool isApplyingBuildFix;
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
    this.buildDiagnostic,
    this.isApplyingBuildFix = false,
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
    Object? buildDiagnostic = _unset,
    bool? isApplyingBuildFix,
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
      buildDiagnostic: identical(buildDiagnostic, _unset)
          ? this.buildDiagnostic
          : buildDiagnostic as AndroidBuildDiagnostic?,
      isApplyingBuildFix: isApplyingBuildFix ?? this.isApplyingBuildFix,
      logs: logs ?? this.logs,
    );
  }
}

/// Manages Android device discovery, live `flutter run --machine` debug sessions,
/// automatic debounced Hot Reload on file saves, long-build progress heartbeats,
/// and build/install/runtime crash diagnostics + AI root-cause analysis.
class AndroidDebugNotifier extends StateNotifier<AndroidDebugState> {
  final AndroidDeviceRunnerService _service;
  final Duration _buildHeartbeatInterval;
  final http.Client? _aiHttpClient;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  Timer? _reloadDebounceTimer;
  Timer? _exitDrainTimer;
  Timer? _buildHeartbeatTimer;
  Timer? _runtimeCrashDebounceTimer;
  int _nextRequestId = 1;
  final Map<int, String> _pendingRpcMethods = {};
  final List<String> _currentRunLines = [];
  int _launchGeneration = 0;
  bool _hasActiveAppStarted = false;
  bool _evaluatedCurrentRunFailure = false;
  bool _isDiagnosingFailure = false;
  bool _gradleTaskStarted = false;
  bool _userRequestedStop = false;
  DateTime? _gradleBuildStartedAt;
  int _heartbeatTickCount = 0;

  static const int _maxLogEntries = 800;

  AndroidDebugNotifier(
    this._service, {
    Duration buildHeartbeatInterval = const Duration(seconds: 20),
    http.Client? aiHttpClient,
  })  : _buildHeartbeatInterval = buildHeartbeatInterval,
        _aiHttpClient = aiHttpClient,
        super(const AndroidDebugState());

  void _appendLog(
    String rawMessage, {
    bool isError = false,
    bool isSystem = false,
  }) {
    if (!mounted) return;
    final clean = rawMessage.trimRight();
    if (clean.isEmpty) return;

    _currentRunLines.add(clean);
    if (_currentRunLines.length > _maxLogEntries) {
      _currentRunLines.removeRange(0, _currentRunLines.length - _maxLogEntries);
    }

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

  static bool _looksLikeGradleOrNativeBuild(String text) {
    final lower = text.toLowerCase();
    return lower.contains('gradle') ||
        lower.contains('assemble') ||
        lower.contains('cmake') ||
        lower.contains('ninja') ||
        lower.contains('building apk') ||
        lower.contains('compiling');
  }

  static String _formatElapsedSeconds(int totalSeconds) {
    if (totalSeconds < 60) return '${totalSeconds}s';
    final minutes = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return secs == 0 ? '${minutes}m' : '${minutes}m ${secs}s';
  }

  void _startBuildHeartbeatIfNeeded() {
    if (_gradleTaskStarted ||
        !mounted ||
        state.status != DeviceRunStatus.launching) {
      return;
    }
    _gradleTaskStarted = true;
    _gradleBuildStartedAt = DateTime.now();
    _heartbeatTickCount = 0;
    _buildHeartbeatTimer?.cancel();
    _buildHeartbeatTimer = Timer.periodic(_buildHeartbeatInterval, (_) {
      if (!mounted || state.status != DeviceRunStatus.launching) {
        _stopBuildHeartbeat();
        return;
      }
      _heartbeatTickCount++;
      final wallSeconds = DateTime.now()
          .difference(_gradleBuildStartedAt ?? DateTime.now())
          .inSeconds;
      final minTickSeconds =
          _heartbeatTickCount * _buildHeartbeatInterval.inSeconds;
      final elapsedSeconds =
          wallSeconds > minTickSeconds ? wallSeconds : minTickSeconds;
      final elapsedLabel = _formatElapsedSeconds(elapsedSeconds);
      final msg =
          'Compilação Gradle/C++/CMake em andamento ($elapsedLabel) — módulos nativos podem compilar em silêncio...';
      state = state.copyWith(progressMessage: msg);
      _appendLog('⏳ $msg', isSystem: true);
    });
  }

  void _stopBuildHeartbeat() {
    _buildHeartbeatTimer?.cancel();
    _buildHeartbeatTimer = null;
  }

  static bool _lineIndicatesCrashOrFatalIssue(String line) {
    final lower = line.toLowerCase();
    return lower.contains('app failed to start') ||
        lower.contains('lost connection to device') ||
        lower.contains('failed to link shaders') ||
        lower.contains('pipeline create failed') ||
        lower.contains('vkcmdbindpipeline') ||
        lower.contains('fatal signal ') ||
        lower.contains('sigsegv') ||
        lower.contains('sigabrt') ||
        lower.contains('cause: null pointer dereference') ||
        lower.contains('backtrace:') ||
        lower.contains('outofmemoryerror') ||
        lower.contains('std::bad_alloc') ||
        lower.contains('outofdevicememory') ||
        lower.contains('vk_error_out_of_device_memory') ||
        lower.contains('vk_error_out_of_host_memory') ||
        lower.contains('unhandled exception:') ||
        lower.contains('exception caught by') ||
        lower.contains('install_failed_') ||
        lower.contains('adb.exe: device') ||
        lower.contains('no devices/emulators found') ||
        lower.contains('device offline');
  }

  bool _hasFatalBuildFailureInCurrentRun() {
    final lower = _currentRunLines.join('\n').toLowerCase();
    return lower.contains('app failed to start') ||
        lower.contains('gradle build failed') ||
        lower.contains('failure: build failed with an exception') ||
        lower.contains('failed with exit code') ||
        lower.contains('cmake error') ||
        lower.contains('cmake was unable to find a build program corresponding to') ||
        lower.contains('cmake_make_program is not set') ||
        lower.contains('unable to find library -lkernel32') ||
        lower.contains('unable to find library -lmingw32') ||
        lower.contains('is not able to compile a simple test program') ||
        lower.contains('host compiler not found') ||
        lower.contains('vulkan_glslc_executable-notfound') ||
        lower.contains('cmake_mt-notfound') ||
        lower.contains('lnk1181') ||
        lower.contains('lnk1104') ||
        lower.contains('kernel32.lib') ||
        lower.contains('libcmt.lib') ||
        lower.contains('detecting c compiler abi info - failed') ||
        lower.contains('licenses not accepted') ||
        lower.contains('cmdline-tools component is missing') ||
        lower.contains('adb.exe: device') ||
        lower.contains('no devices/emulators found') ||
        lower.contains('device offline') ||
        lower.contains('install_failed_') ||
        lower.contains('failed to link shaders') ||
        lower.contains('pipeline create failed') ||
        lower.contains('vkcmdbindpipeline') ||
        lower.contains('fatal signal ') ||
        lower.contains('sigsegv') ||
        lower.contains('sigabrt') ||
        lower.contains('cause: null pointer dereference') ||
        lower.contains('backtrace:') ||
        lower.contains('outofmemoryerror') ||
        lower.contains('std::bad_alloc') ||
        lower.contains('outofdevicememory') ||
        lower.contains('vk_error_out_of_device_memory') ||
        lower.contains('vk_error_out_of_host_memory') ||
        lower.contains('unhandled exception:') ||
        lower.contains('exception caught by') ||
        lower.contains('lost connection to device');
  }

  void _scheduleRuntimeCrashEvaluation() {
    if (!mounted || _userRequestedStop || _isDiagnosingFailure) return;
    _runtimeCrashDebounceTimer?.cancel();
    final gen = _launchGeneration;
    _runtimeCrashDebounceTimer = Timer(const Duration(milliseconds: 45), () {
      if (!mounted || gen != _launchGeneration || _userRequestedStop) return;
      unawaited(
        _evaluateBuildFailureDiagnostics(
          generation: gen,
          allowEnrichExisting: true,
        ),
      );
    });
  }

  void _inspectStreamedLineForDiagnostics(String line) {
    if (!mounted || _userRequestedStop) return;
    final lower = line.toLowerCase();

    if (!_hasActiveAppStarted &&
        !_gradleTaskStarted &&
        state.status == DeviceRunStatus.launching &&
        _looksLikeGradleOrNativeBuild(line)) {
      _startBuildHeartbeatIfNeeded();
    }

    if (!_hasActiveAppStarted && lower.contains('app failed to start')) {
      _stopBuildHeartbeat();
      if (state.status != DeviceRunStatus.error) {
        state = state.copyWith(
          status: DeviceRunStatus.error,
          activeAppId: null,
          progressMessage: null,
          errorMessage: state.errorMessage ?? 'App failed to start',
        );
      }
      unawaited(_evaluateBuildFailureDiagnostics(
        generation: _launchGeneration,
        forceErrorStatus: true,
      ));
      return;
    }

    if (lower.contains('lost connection to device')) {
      _stopBuildHeartbeat();
      _runtimeCrashDebounceTimer?.cancel();
      _runtimeCrashDebounceTimer = null;
      if (state.status != DeviceRunStatus.error) {
        state = state.copyWith(
          status: DeviceRunStatus.error,
          activeAppId: null,
          progressMessage: null,
          errorMessage: state.buildDiagnostic?.title ??
              state.errorMessage ??
              'Conexão perdida com o dispositivo.',
        );
      }
      unawaited(_evaluateBuildFailureDiagnostics(
        generation: _launchGeneration,
        forceErrorStatus: true,
        allowEnrichExisting: true,
      ));
      return;
    }

    if (_lineIndicatesCrashOrFatalIssue(line)) {
      _scheduleRuntimeCrashEvaluation();
    }
  }

  Future<void> _evaluateBuildFailureDiagnostics({
    required int generation,
    String? projectPath,
    bool forceErrorStatus = false,
    bool allowEnrichExisting = false,
  }) async {
    if (!mounted || generation != _launchGeneration || _isDiagnosingFailure) {
      return;
    }
    if (_evaluatedCurrentRunFailure && !allowEnrichExisting) {
      return;
    }
    if (_evaluatedCurrentRunFailure &&
        allowEnrichExisting &&
        (state.buildDiagnostic?.isGeneratingAiFix == true ||
            state.buildDiagnostic?.aiFixSuggestion != null)) {
      return;
    }

    _isDiagnosingFailure = true;
    final snapshot = List<String>.from(_currentRunLines);
    final lineCountAtStart = snapshot.length;
    try {
      final diagnostic = await _service.diagnoseBuildFailure(
        snapshot,
        projectPath: projectPath ?? state.projectPath,
      );
      if (!mounted || generation != _launchGeneration) return;
      if (diagnostic != null) {
        final wasAlreadyEvaluated = _evaluatedCurrentRunFailure;
        final previous = state.buildDiagnostic;
        if (wasAlreadyEvaluated &&
            previous != null &&
            previous.issueType == diagnostic.issueType &&
            previous.affectedLocation == diagnostic.affectedLocation &&
            previous.relevantLogLines.length >=
                diagnostic.relevantLogLines.length) {
          return;
        }

        _evaluatedCurrentRunFailure = true;
        final keepAliveForDartException = !forceErrorStatus &&
            diagnostic.issueType == AndroidBuildIssueType.dartRuntimeException &&
            _hasActiveAppStarted &&
            _process != null &&
            state.isActiveSession;

        if (keepAliveForDartException) {
          state = state.copyWith(
            buildDiagnostic: diagnostic,
            errorMessage: diagnostic.title,
          );
        } else {
          _stopBuildHeartbeat();
          state = state.copyWith(
            status: DeviceRunStatus.error,
            progressMessage: null,
            errorMessage: diagnostic.title,
            buildDiagnostic: diagnostic,
          );
        }

        if (!wasAlreadyEvaluated) {
          _appendLog('💡 Diagnóstico automático: ${diagnostic.title}',
              isSystem: true);
          _appendLog('ℹ️ ${diagnostic.explanation}', isSystem: true);
          if (diagnostic.affectedLocation != null &&
              diagnostic.affectedLocation!.isNotEmpty) {
            _appendLog('📍 Local: ${diagnostic.affectedLocation}',
                isSystem: true);
          }
          if (diagnostic.suggestedTerminalCommand != null) {
            _appendLog(
              '🛠️ Comando sugerido: ${diagnostic.suggestedTerminalCommand}',
              isSystem: true,
            );
          }
        }
      }
    } finally {
      _isDiagnosingFailure = false;
      // Re-run once if additional failure lines arrived while inspecting environment.
      if (mounted &&
          generation == _launchGeneration &&
          !_evaluatedCurrentRunFailure &&
          _currentRunLines.length > lineCountAtStart &&
          _hasFatalBuildFailureInCurrentRun()) {
        unawaited(
          _evaluateBuildFailureDiagnostics(
            generation: generation,
            projectPath: projectPath,
            forceErrorStatus: forceErrorStatus,
          ),
        );
      }
    }
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

    final runGeneration = ++_launchGeneration;
    _hasActiveAppStarted = false;
    _evaluatedCurrentRunFailure = false;
    _isDiagnosingFailure = false;
    _gradleTaskStarted = false;
    _userRequestedStop = false;
    _gradleBuildStartedAt = null;
    _heartbeatTickCount = 0;
    _currentRunLines.clear();

    final normalizedProjectPath = p.normalize(projectPath);
    final preservedLogs = state.logs;
    state = state.copyWith(
      selectedDevice: targetDevice,
      status: DeviceRunStatus.launching,
      activeAppId: null,
      projectPath: normalizedProjectPath,
      vmServiceUri: null,
      devToolsUri: null,
      progressMessage: 'Preparando build para ${targetDevice.name}...',
      errorMessage: null,
      buildDiagnostic: null,
      isApplyingBuildFix: false,
      logs: preservedLogs,
    );

    if (preservedLogs.isNotEmpty) {
      _appendLog(
        '────────────────────────────────────────',
        isSystem: true,
      );
    }

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
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      _stdoutSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleStdoutLine,
            onDone: () {
              if (!stdoutDone.isCompleted) stdoutDone.complete();
            },
            onError: (_) {
              if (!stdoutDone.isCompleted) stdoutDone.complete();
            },
          );

      _stderrSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.trim().isNotEmpty) {
                _appendLog(line, isError: true);
                _inspectStreamedLineForDiagnostics(line);
              }
            },
            onDone: () {
              if (!stderrDone.isCompleted) stderrDone.complete();
            },
            onError: (_) {
              if (!stderrDone.isCompleted) stderrDone.complete();
            },
          );

      unawaited(proc.exitCode.then((code) async {
        // Allow buffered stdout/stderr chunks to flush through LineSplitter
        // before tearing down subscriptions and classifying build/runtime failures.
        if (!stdoutDone.isCompleted || !stderrDone.isCompleted) {
          final drainCompleter = Completer<void>();
          _exitDrainTimer?.cancel();
          _exitDrainTimer = Timer(const Duration(milliseconds: 25), () {
            if (!drainCompleter.isCompleted) drainCompleter.complete();
          });
          unawaited(
            Future.wait([stdoutDone.future, stderrDone.future]).then((_) {
              _exitDrainTimer?.cancel();
              _exitDrainTimer = null;
              if (!drainCompleter.isCompleted) drainCompleter.complete();
            }),
          );
          await drainCompleter.future;
        }
        if (!mounted || _process != proc) return;
        final wasRunning = state.isActiveSession;
        _cleanupSubscriptions();
        _process = null;

        final hasCrashLogs = _hasFatalBuildFailureInCurrentRun();
        final failedLaunchOrCrash = !_userRequestedStop &&
            ((code != 0 &&
                    (wasRunning || !_hasActiveAppStarted || hasCrashLogs)) ||
                (hasCrashLogs && state.buildDiagnostic == null));

        if (failedLaunchOrCrash) {
          if (state.status != DeviceRunStatus.error || code != 0) {
            _appendLog(
              '❌ Processo encerrado com código $code. O terminal permanece aberto para diagnóstico.',
              isError: true,
            );
          }
          state = state.copyWith(
            status: DeviceRunStatus.error,
            activeAppId: null,
            progressMessage: null,
            errorMessage: state.buildDiagnostic?.title ??
                state.errorMessage ??
                'Processo encerrado com código $code.',
          );
          if (!_evaluatedCurrentRunFailure || state.buildDiagnostic == null) {
            unawaited(
              _evaluateBuildFailureDiagnostics(
                generation: runGeneration,
                projectPath: normalizedProjectPath,
                forceErrorStatus: true,
                allowEnrichExisting: true,
              ),
            );
          }
        } else if (state.status != DeviceRunStatus.error) {
          if (wasRunning) {
            _appendLog(
              '⏹️ Conexão/execução encerrada (código $code). O terminal permanece ativo.',
              isSystem: true,
            );
          }
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
      _stopBuildHeartbeat();
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
      _inspectStreamedLineForDiagnostics(line);
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
          if (_looksLikeGradleOrNativeBuild(message)) {
            _startBuildHeartbeatIfNeeded();
          }
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
        _hasActiveAppStarted = true;
        _stopBuildHeartbeat();
        state = state.copyWith(
          status: DeviceRunStatus.running,
          progressMessage: null,
          errorMessage: _evaluatedCurrentRunFailure ? state.errorMessage : null,
          buildDiagnostic:
              _evaluatedCurrentRunFailure ? state.buildDiagnostic : null,
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
          _inspectStreamedLineForDiagnostics(logText);
        }
        break;

      case 'app.stop':
        _stopBuildHeartbeat();
        _runtimeCrashDebounceTimer?.cancel();
        _runtimeCrashDebounceTimer = null;
        final stopErr = params['error']?.toString();
        if (_userRequestedStop) {
          state = state.copyWith(
            status: DeviceRunStatus.idle,
            activeAppId: null,
            progressMessage: null,
          );
          break;
        }
        if (stopErr != null && stopErr.isNotEmpty) {
          _appendLog(
            '❌ Sessão encerrada com erro: $stopErr (terminal mantido aberto).',
            isError: true,
          );
          state = state.copyWith(
            status: DeviceRunStatus.error,
            activeAppId: null,
            progressMessage: null,
            errorMessage: stopErr,
          );
          unawaited(_evaluateBuildFailureDiagnostics(
            generation: _launchGeneration,
            forceErrorStatus: true,
            allowEnrichExisting: true,
          ));
        } else if (_hasFatalBuildFailureInCurrentRun()) {
          _appendLog(
            _hasActiveAppStarted
                ? '❌ App encerrado inesperadamente após erro/crash em runtime. Terminal mantido aberto para diagnóstico.'
                : '❌ Build/instalação falhou antes de iniciar no dispositivo. Terminal mantido aberto para diagnóstico.',
            isError: true,
          );
          state = state.copyWith(
            status: DeviceRunStatus.error,
            activeAppId: null,
            progressMessage: null,
            errorMessage: state.buildDiagnostic?.title ??
                (_hasActiveAppStarted
                    ? 'App encerrado após falha em execução.'
                    : 'Falha ao iniciar app no dispositivo.'),
          );
          unawaited(_evaluateBuildFailureDiagnostics(
            generation: _launchGeneration,
            forceErrorStatus: true,
            allowEnrichExisting: true,
          ));
        } else {
          _appendLog(
            '⏹️ App encerrado no dispositivo. Terminal mantido aberto.',
            isSystem: true,
          );
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
          _inspectStreamedLineForDiagnostics(msg);
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
    _userRequestedStop = true;
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = null;
    _stopBuildHeartbeat();
    _runtimeCrashDebounceTimer?.cancel();
    _runtimeCrashDebounceTimer = null;

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

  /// Applies a discovered compatible JDK via `flutter config --jdk-dir` and
  /// automatically relaunches the current project on the selected Android device.
  Future<bool> applyCompatibleJdkAndRelaunch({String? jdkPath}) async {
    final targetPath =
        (jdkPath ?? state.buildDiagnostic?.compatibleJdk?.path)?.trim();
    if (targetPath == null || targetPath.isEmpty || state.isApplyingBuildFix) {
      return false;
    }

    state = state.copyWith(isApplyingBuildFix: true);
    _appendLog(
      '🛠️ Configurando `flutter config --jdk-dir="$targetPath"`...',
      isSystem: true,
    );

    final ok = await _service.configureFlutterJdkDir(targetPath);
    if (!mounted) return false;

    if (!ok) {
      state = state.copyWith(isApplyingBuildFix: false);
      _appendLog(
        '❌ Não foi possível aplicar `--jdk-dir`. Execute no terminal: flutter config --jdk-dir="$targetPath"',
        isError: true,
      );
      return false;
    }

    _appendLog(
      '✅ JDK compatível salvo no Flutter! Relançando app no dispositivo...',
      isSystem: true,
    );
    state = state.copyWith(
      isApplyingBuildFix: false,
      buildDiagnostic: null,
      errorMessage: null,
    );

    final projectPath = state.projectPath;
    if (projectPath != null && projectPath.trim().isNotEmpty) {
      await _service.stopProjectGradleDaemons(projectPath: projectPath);
      if (!mounted) return false;
      return launchProject(projectPath, device: state.selectedDevice);
    }
    return true;
  }

  /// Applies FLRD's Windows CMake host-toolchain fix (when requested), stops stale
  /// Gradle daemons so updated MSVC/PATH env takes effect, clears `android/app/.cxx`,
  /// and relaunches the app on the active device.
  Future<bool> applyCmakeFixAndRelaunch() async {
    final projectPath = state.projectPath?.trim();
    final diagnostic = state.buildDiagnostic;
    if (projectPath == null ||
        projectPath.isEmpty ||
        diagnostic == null ||
        !diagnostic.canAutoFixCmake ||
        state.isApplyingBuildFix) {
      return false;
    }

    state = state.copyWith(isApplyingBuildFix: true);

    if (diagnostic.canFixCmakeHostToolchain) {
      _appendLog(
        '🛠️ Configurando HOST_C_COMPILER / glslc no CMakeLists.txt...',
        isSystem: true,
      );
      final patched = await _service.applyWindowsHostToolchainCmakeFix(
        projectPath,
        msvcCompilerPath: diagnostic.detectedToolPath,
      );
      if (!mounted) return false;
      if (!patched) {
        state = state.copyWith(isApplyingBuildFix: false);
        _appendLog(
          '❌ Não foi possível atualizar android/app/src/main/cpp/CMakeLists.txt.',
          isError: true,
        );
        return false;
      }
    }

    _appendLog(
      '🛑 Encerrando Gradle Daemon antigo para carregar INCLUDE / LIB / PATH atualizados...',
      isSystem: true,
    );
    await _service.stopProjectGradleDaemons(projectPath: projectPath);
    if (!mounted) return false;

    if (diagnostic.canClearCxxCache) {
      _appendLog(
        '🧹 Limpando cache android/app/.cxx...',
        isSystem: true,
      );
      final cleared = await _service.clearAndroidCxxCache(projectPath);
      if (!mounted) return false;
      if (!cleared) {
        state = state.copyWith(isApplyingBuildFix: false);
        _appendLog(
          '❌ Não foi possível limpar android/app/.cxx (verifique se nenhum processo trava a pasta).',
          isError: true,
        );
        return false;
      }
    }

    _appendLog(
      '✅ Ambiente CMake atualizado! Relançando app com PATH/Ninja/MSVC atualizados...',
      isSystem: true,
    );
    state = state.copyWith(
      isApplyingBuildFix: false,
      buildDiagnostic: null,
      errorMessage: null,
    );

    return launchProject(projectPath, device: state.selectedDevice);
  }

  /// Re-scans connected ADB/Android devices and automatically relaunches the
  /// active project when a device becomes ready again.
  Future<bool> rescanAndRelaunch({String? projectPath}) async {
    final effectiveProject = (projectPath ?? state.projectPath)?.trim();
    final previousDeviceId = state.selectedDevice?.id;
    _appendLog(
      '🔄 Re-detectando dispositivos Android conectados via ADB...',
      isSystem: true,
    );
    await scanDevices();
    if (!mounted) return false;
    if (state.devices.isEmpty) {
      _appendLog(
        '⚠️ Nenhum aparelho Android pronto detectado ainda. Verifique o cabo USB e tente novamente.',
        isError: true,
      );
      return false;
    }

    final target = state.devices.firstWhere(
      (d) => d.id == previousDeviceId,
      orElse: () => state.selectedDevice ?? state.devices.first,
    );
    selectDevice(target);
    if (effectiveProject == null || effectiveProject.isEmpty) {
      return true;
    }
    return launchProject(effectiveProject, device: target);
  }

  /// Invokes [GeminiAiService.diagnoseAndSuggestAppFix] for the current
  /// diagnostic card, scanning local project files when available.
  Future<String?> generateAiDiagnosisForCurrentDiagnostic({
    String? projectPath,
    String? apiKey,
    http.Client? httpClient,
  }) async {
    final diagnostic = state.buildDiagnostic;
    if (diagnostic == null || diagnostic.isGeneratingAiFix) return null;

    final generation = _launchGeneration;
    final effectiveProjectPath = (projectPath ?? state.projectPath ?? '').trim();
    final effectiveLogs = diagnostic.relevantLogLines.isNotEmpty
        ? diagnostic.relevantLogLines
        : (_currentRunLines.isNotEmpty
            ? List<String>.from(_currentRunLines)
            : state.logs.map((e) => e.message).toList());

    state = state.copyWith(
      buildDiagnostic: diagnostic.copyWith(
        isGeneratingAiFix: true,
        aiFixError: null,
      ),
    );

    try {
      final suggestion = await GeminiAiService.diagnoseAndSuggestAppFix(
        projectPath: effectiveProjectPath,
        issueTitle: diagnostic.title,
        crashLogs: effectiveLogs,
        affectedLocation: diagnostic.affectedLocation,
        apiKey: apiKey,
        httpClient: httpClient ?? _aiHttpClient,
      );
      if (!mounted || generation != _launchGeneration) return null;
      final current = state.buildDiagnostic;
      if (current == null) return null;

      state = state.copyWith(
        buildDiagnostic: current.copyWith(
          isGeneratingAiFix: false,
          aiFixSuggestion: suggestion,
          aiFixError: null,
        ),
      );
      _appendLog(
        '🤖 Análise de IA concluída para: ${diagnostic.title}',
        isSystem: true,
      );
      return suggestion;
    } catch (e) {
      if (!mounted || generation != _launchGeneration) return null;
      final current = state.buildDiagnostic;
      if (current != null) {
        state = state.copyWith(
          buildDiagnostic: current.copyWith(
            isGeneratingAiFix: false,
            aiFixError: 'Falha ao analisar erro com IA: $e',
          ),
        );
      }
      return null;
    }
  }

  void dismissBuildDiagnostic() {
    state = state.copyWith(buildDiagnostic: null);
  }

  void dismissError() {
    state = state.copyWith(
      status: DeviceRunStatus.idle,
      errorMessage: null,
      buildDiagnostic: null,
    );
  }

  void _cleanupSubscriptions() {
    _stopBuildHeartbeat();
    _runtimeCrashDebounceTimer?.cancel();
    _runtimeCrashDebounceTimer = null;
    _exitDrainTimer?.cancel();
    _exitDrainTimer = null;
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

final aiDiagnosticHttpClientProvider = Provider<http.Client?>((ref) => null);

final androidDebugProvider =
    StateNotifierProvider<AndroidDebugNotifier, AndroidDebugState>((ref) {
  final service = ref.watch(androidDeviceRunnerServiceProvider);
  final httpClient = ref.watch(aiDiagnosticHttpClientProvider);
  return AndroidDebugNotifier(service, aiHttpClient: httpClient);
});
