import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
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

/// Handles detection of connected Android devices, live USB/SDK troubleshooting
/// diagnostics, and `flutter run --machine` sessions with JSON-RPC Hot Reload / Hot Restart.
class AndroidDeviceRunnerService {
  final ProcessRunnerFn _processRunner;
  final ProcessStarterFn _processStarter;
  final Map<String, String> Function() _environmentProvider;
  final bool Function(String path) _fileExists;
  final bool Function(String path) _dirExists;
  final String? Function(String path) _readFileSync;
  final List<String> Function(String path) _listSubdirectories;
  final bool? _isWindowsOverride;

  AndroidDeviceRunnerService({
    ProcessRunnerFn? processRunner,
    ProcessStarterFn? processStarter,
    Map<String, String> Function()? environmentProvider,
    bool Function(String path)? fileExists,
    bool Function(String path)? dirExists,
    String? Function(String path)? readFileSync,
    List<String> Function(String path)? listSubdirectories,
    bool? isWindowsOverride,
  })  : _processRunner = processRunner ?? _defaultProcessRunner,
        _processStarter = processStarter ?? _defaultProcessStarter,
        _environmentProvider =
            environmentProvider ?? (() => Platform.environment),
        _fileExists = fileExists ?? ((path) => File(path).existsSync()),
        _dirExists = dirExists ?? ((path) => Directory(path).existsSync()),
        _readFileSync = readFileSync ?? _defaultReadFileSync,
        _listSubdirectories =
            listSubdirectories ?? _defaultListSubdirectories,
        _isWindowsOverride = isWindowsOverride;

  static String? _defaultReadFileSync(String path) {
    if (kIsWeb) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  static List<String> _defaultListSubdirectories(String path) {
    if (kIsWeb) return const [];
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return const [];
      return dir
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((d) => d.path)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  bool get _isWindows =>
      _isWindowsOverride ?? (!kIsWeb && Platform.isWindows);

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
      runInShell: _isWindows,
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

  /// Scans Android devices and, when none are ready, inspects Windows USB/ADB
  /// interfaces, `adb devices -l`, Android SDK paths, and Java JDK to pinpoint why.
  Future<AndroidConnectionDiagnostic> scanAndroidEnvironment() async {
    if (kIsWeb) {
      return const AndroidConnectionDiagnostic(
        issueType: AndroidConnectionIssueType.scanError,
        title: 'Disponível apenas no FLRD Desktop',
        summary:
            'A detecção e depuração USB em aparelhos Android físicos requer o aplicativo Desktop.',
      );
    }

    final List<ConnectedAndroidDevice> devices;
    try {
      devices = await scanAndroidDevices();
    } catch (e) {
      return AndroidConnectionDiagnostic(
        issueType: AndroidConnectionIssueType.scanError,
        title: 'Falha ao consultar dispositivos Flutter',
        summary: 'Não foi possível executar `flutter devices --machine`: $e',
        steps: const [
          'Verifique se o Flutter SDK está corretamente instalado e no PATH do sistema.',
          'Abra o Flutter Doctor para diagnosticar componentes ausentes.',
        ],
      );
    }

    if (devices.isNotEmpty) {
      return AndroidConnectionDiagnostic(
        devices: devices,
        issueType: AndroidConnectionIssueType.none,
        title: '${devices.length} aparelho(s) Android pronto(s)',
        summary: 'Conexão validada pelo Flutter CLI.',
        hasJava: true,
      );
    }

    final adbAndSdkFuture = _locateAdbAndSdk();
    final javaFuture = _checkJavaAvailable();
    final usbFuture = _isWindows
        ? _probeWindowsUsbDevices()
        : Future<List<WindowsUsbDeviceInfo>>.value(const []);

    final results = await Future.wait<Object?>([
      adbAndSdkFuture,
      javaFuture,
      usbFuture,
    ]);

    final sdkProbe = results[0]! as ({String? adbPath, String? sdkPath});
    final hasJava = results[1]! as bool;
    final usbDevices = results[2]! as List<WindowsUsbDeviceInfo>;

    final adbDevices = sdkProbe.adbPath != null
        ? await _runAdbDevices(sdkProbe.adbPath!)
        : const <AdbDeviceEntry>[];

    return buildConnectionDiagnostic(
      devices: devices,
      adbPath: sdkProbe.adbPath,
      discoveredSdkPath: sdkProbe.sdkPath,
      hasJava: hasJava,
      adbDevices: adbDevices,
      usbDevices: usbDevices,
      isWindows: _isWindows,
    );
  }

  /// Runs `flutter config --android-sdk <sdkPath>` to bind a discovered SDK path.
  Future<bool> configureFlutterAndroidSdk(String sdkPath) async {
    if (kIsWeb || sdkPath.trim().isEmpty) return false;
    final res = await _processRunner(
      'flutter',
      ['config', '--android-sdk', sdkPath],
      runInShell: _isWindows,
    );
    return res.exitCode == 0;
  }

  /// Configures Flutter's explicit `--jdk-dir` override so Gradle uses a
  /// compatible JDK (e.g., JDK 17/21) instead of Android Studio's newer JBR.
  Future<bool> configureFlutterJdkDir(String jdkPath) async {
    if (kIsWeb || jdkPath.trim().isEmpty) return false;
    final res = await _processRunner(
      'flutter',
      ['config', '--jdk-dir', jdkPath.trim()],
      runInShell: _isWindows,
    );
    return res.exitCode == 0;
  }

  String _joinOsPath(String base, String child) {
    final sep = _isWindows ? '\\' : '/';
    final cleanBase = base.endsWith('\\') || base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final cleanChild =
        child.startsWith('\\') || child.startsWith('/') ? child.substring(1) : child;
    return '$cleanBase$sep$cleanChild';
  }

  /// Extracts `JAVA_VERSION` from the contents of a JDK `release` file.
  static String? parseJavaReleaseVersion(String? releaseContent) {
    if (releaseContent == null || releaseContent.trim().isEmpty) return null;
    final quoted = RegExp(
      r'JAVA_VERSION\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(releaseContent);
    if (quoted != null) {
      return quoted.group(1)?.trim();
    }
    final unquoted = RegExp(
      r'JAVA_VERSION\s*=\s*([^\s#]+)',
      caseSensitive: false,
    ).firstMatch(releaseContent);
    return unquoted?.group(1)?.trim();
  }

  /// Parses the Java feature/major version (e.g. `"25.0.4"` -> `25`, `"1.8.0"` -> `8`).
  static int? parseJavaMajorVersion(String? version) {
    if (version == null) return null;
    final trimmed = version.trim();
    if (trimmed.isEmpty) return null;
    final legacy = RegExp(r'^1\.(\d+)').firstMatch(trimmed);
    if (legacy != null) {
      return int.tryParse(legacy.group(1)!);
    }
    final modern = RegExp(r'^(\d+)').firstMatch(trimmed);
    if (modern != null) {
      return int.tryParse(modern.group(1)!);
    }
    return null;
  }

  /// Extracts Gradle version (e.g. `8.14`) from `gradle-wrapper.properties`.
  static String? extractGradleWrapperVersion(String? content) {
    if (content == null || content.isEmpty) return null;
    final match = RegExp(
      r'gradle-(\d+\.\d+(?:\.\d+)?)(?:-[a-zA-Z0-9]+)?\.zip',
    ).firstMatch(content);
    return match?.group(1);
  }

  static List<int> _parseNumericSegments(String version) {
    return version
        .split(RegExp(r'[^0-9]+'))
        .where((s) => s.isNotEmpty)
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
  }

  static int _compareVersions(String a, String b) {
    final segA = _parseNumericSegments(a);
    final segB = _parseNumericSegments(b);
    final maxLen = segA.length > segB.length ? segA.length : segB.length;
    for (var i = 0; i < maxLen; i++) {
      final va = i < segA.length ? segA[i] : 0;
      final vb = i < segB.length ? segB[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  /// Checks whether [javaMajor] is supported by [gradleVersion] for Flutter builds.
  static bool isJavaCompatibleWithGradle({
    required int javaMajor,
    required String gradleVersion,
  }) {
    if (javaMajor < 17) return false;
    final minGradleByJava = <int, String>{
      17: '7.3',
      18: '7.5',
      19: '7.6',
      20: '8.3',
      21: '8.5',
      22: '8.8',
      23: '8.10',
      24: '8.14',
      25: '9.1',
    };
    final minGradle = minGradleByJava[javaMajor] ?? (javaMajor > 25 ? '9.1' : '7.3');
    return _compareVersions(gradleVersion, minGradle) >= 0;
  }

  JavaJdkInfo? _inspectJdkDirectory(String rawPath, {required String source}) {
    var clean = rawPath.trim();
    if (clean.isEmpty) return null;
    while (clean.length > 3 && (clean.endsWith('\\') || clean.endsWith('/'))) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (!_dirExists(clean)) return null;

    var homePath = clean;
    var releaseContent = _readFileSync(_joinOsPath(homePath, 'release'));
    if (releaseContent == null && !_isWindows) {
      final macHome = _joinOsPath(_joinOsPath(clean, 'Contents'), 'Home');
      if (_dirExists(macHome)) {
        homePath = macHome;
        releaseContent = _readFileSync(_joinOsPath(homePath, 'release'));
      }
    }

    final version = parseJavaReleaseVersion(releaseContent);
    final major = parseJavaMajorVersion(version);
    if (version == null || major == null) return null;

    final javaExe = _joinOsPath(
      _joinOsPath(homePath, 'bin'),
      _isWindows ? 'java.exe' : 'java',
    );
    if (!_fileExists(javaExe)) return null;

    return JavaJdkInfo(
      path: homePath,
      version: version,
      majorVersion: major,
      source: source,
    );
  }

  /// Discovers locally installed compatible LTS JDKs (17..21) ordered by preference.
  Future<List<JavaJdkInfo>> discoverCompatibleJdks() async {
    if (kIsWeb) return const [];
    final env = _environmentProvider();
    final found = <JavaJdkInfo>[];
    final seenPaths = <String>{};

    void tryAdd(String? candidatePath, String source) {
      if (candidatePath == null || candidatePath.trim().isEmpty) return;
      final info = _inspectJdkDirectory(candidatePath, source: source);
      if (info == null || !info.isLtsCompatible) return;
      final key = _isWindows ? info.path.toLowerCase() : info.path;
      if (seenPaths.add(key)) {
        found.add(info);
      }
    }

    tryAdd(env['JAVA_HOME'], 'JAVA_HOME');
    tryAdd(env['JDK_HOME'], 'JDK_HOME');

    if (_isWindows) {
      final roots = <String>[
        env['ProgramFiles'] ?? r'C:\Program Files',
        env['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
        if ((env['LOCALAPPDATA'] ?? '').isNotEmpty)
          _joinOsPath(env['LOCALAPPDATA']!, 'Programs'),
      ];
      const windowsVendors = <({String folder, String label})>[
        (folder: 'Eclipse Adoptium', label: 'Eclipse Adoptium'),
        (folder: 'Java', label: 'Oracle / OpenJDK'),
        (folder: 'Microsoft', label: 'Microsoft OpenJDK'),
        (folder: 'Zulu', label: 'Azul Zulu'),
        (folder: 'BellSoft', label: 'BellSoft Liberica'),
        (folder: 'Amazon Corretto', label: 'Amazon Corretto'),
        (folder: 'Semeru', label: 'IBM Semeru'),
      ];
      for (final root in roots) {
        for (final vendor in windowsVendors) {
          final vendorDir = _joinOsPath(root, vendor.folder);
          if (!_dirExists(vendorDir)) continue;
          tryAdd(vendorDir, vendor.label);
          for (final subDir in _listSubdirectories(vendorDir)) {
            tryAdd(subDir, vendor.label);
          }
        }
      }
    } else {
      final home = env['HOME'] ?? '';
      final unixContainers = <({String path, String label})>[
        (path: '/Library/Java/JavaVirtualMachines', label: 'System JVM'),
        (path: '/usr/lib/jvm', label: 'System JVM'),
        if (home.isNotEmpty)
          (path: _joinOsPath(home, '.sdkman/candidates/java'), label: 'SDKMAN'),
      ];
      for (final container in unixContainers) {
        if (!_dirExists(container.path)) continue;
        for (final subDir in _listSubdirectories(container.path)) {
          tryAdd(subDir, container.label);
        }
      }
    }

    found.sort((a, b) {
      final aHome = a.source == 'JAVA_HOME' ? 0 : 1;
      final bHome = b.source == 'JAVA_HOME' ? 0 : 1;
      if (aHome != bHome) return aHome.compareTo(bHome);

      final aIs17 = a.majorVersion == 17 ? 0 : 1;
      final bIs17 = b.majorVersion == 17 ? 0 : 1;
      if (aIs17 != bIs17) return aIs17.compareTo(bIs17);

      final majorCmp = b.majorVersion.compareTo(a.majorVersion);
      if (majorCmp != 0) return majorCmp;

      return _compareVersions(b.version, a.version);
    });

    return found;
  }

  /// Classifies captured Flutter/Gradle/CMake build logs into an actionable
  /// [AndroidBuildDiagnostic], or returns `null` if no known pattern matches.
  AndroidBuildDiagnostic? classifyBuildFailureLogs(
    List<String> logLines, {
    List<JavaJdkInfo> availableCompatibleJdks = const [],
    String? projectGradleVersion,
  }) {
    if (logLines.isEmpty) return null;
    final joined = logLines.join('\n');
    final lower = joined.toLowerCase();

    final isJavaGradleMismatch =
        lower.contains('gradle build failed due to java/gradle incompatibility') ||
            (lower.contains('the java version used for the build is') &&
                lower.contains('incompatible with gradle')) ||
            lower.contains('unsupported class file major version') ||
            (lower.contains('could not open cp_init generic class cache') &&
                lower.contains('semantic analysis'));

    if (isJavaGradleMismatch) {
      final javaMatch = RegExp(
        r'The Java version used for the build is\s+([0-9][0-9._+-]*)',
        caseSensitive: false,
      ).firstMatch(joined);
      final detectedJava = javaMatch?.group(1);

      final gradleMatch = RegExp(
        r'incompatible with Gradle\s+([0-9]+(?:\.[0-9]+)*)',
        caseSensitive: false,
      ).firstMatch(joined);
      final detectedGradle = gradleMatch?.group(1) ?? projectGradleVersion;

      final preferredJdk = availableCompatibleJdks.isNotEmpty
          ? availableCompatibleJdks.first
          : null;

      final javaLabel = detectedJava ?? 'incompatível';
      final gradleLabel = detectedGradle ?? 'atual';

      if (preferredJdk != null) {
        return AndroidBuildDiagnostic(
          issueType: AndroidBuildIssueType.javaGradleIncompatibility,
          title: 'Java $javaLabel conflita com o Gradle $gradleLabel',
          explanation:
              'O Flutter usou o Java $javaLabel (geralmente o JBR atualizado do Android Studio), '
              'mas o Gradle $gradleLabel deste projeto não suporta essa versão. '
              'Apenas subir o Gradle para 9.1+ costuma quebrar projetos com AGP 8.x. '
              'Encontramos o JDK ${preferredJdk.version} (${preferredJdk.source}) no seu PC — '
              'aplique-o no Flutter em 1 clique e tente rodar novamente.',
          detectedJavaVersion: detectedJava,
          gradleVersion: detectedGradle,
          compatibleJdk: preferredJdk,
          suggestedTerminalCommand:
              'flutter config --jdk-dir="${preferredJdk.path}"',
          steps: [
            'Encontrado JDK ${preferredJdk.version} (${preferredJdk.source}) em ${preferredJdk.path}.',
            'Clique em "Aplicar JDK ${preferredJdk.majorVersion} no Flutter e Rodar" para configurar `flutter config --jdk-dir` automaticamente.',
            'Não é preciso alterar `gradle-wrapper.properties` nem quebrar o AGP 8.x do projeto.',
          ],
        );
      }

      final installCmd = _isWindows
          ? 'winget install -e --id EclipseAdoptium.Temurin.17.JDK'
          : 'brew install --cask temurin@17';

      return AndroidBuildDiagnostic(
        issueType: AndroidBuildIssueType.javaGradleIncompatibility,
        title: 'Java $javaLabel conflita com o Gradle $gradleLabel',
        explanation:
            'O Flutter usou o Java $javaLabel (geralmente o JBR embutido no Android Studio atualizado), '
            'mas o Gradle $gradleLabel do projeto não suporta essa versão e nenhum JDK 17/21 compatível '
            'foi encontrado automaticamente. Apenas subir o Gradle para 9.1+ quebra projetos com AGP 8.x.',
        detectedJavaVersion: detectedJava,
        gradleVersion: detectedGradle,
        suggestedTerminalCommand: installCmd,
        externalHelpUrl: 'https://adoptium.net/temurin/releases/?version=17',
        steps: [
          'Instale o Eclipse Temurin JDK 17 LTS pelo terminal (`$installCmd`) ou pelo botão de download.',
          'Depois de instalar, clique em "Detectar Celular" / "Rodar" ou configure `flutter config --jdk-dir="<caminho-jdk-17>"`.',
        ],
      );
    }

    final isNinjaMissing =
        (lower.contains('cmake was unable to find a build program corresponding to') &&
                lower.contains('ninja')) ||
            lower.contains('cmake_make_program is not set');

    if (isNinjaMissing) {
      final ninjaCmd =
          _isWindows ? 'winget install -e --id Ninja-build.Ninja' : 'brew install ninja';
      return AndroidBuildDiagnostic(
        issueType: AndroidBuildIssueType.cmakeBuildToolMissing,
        title: 'CMake não encontrou o executável "Ninja"',
        explanation:
            'O Gradle e o Java compilaram normalmente, mas este projeto possui módulos nativos C/C++ (CMake ExternalProject) '
            'que exigem a ferramenta "Ninja" disponível no PATH do sistema (CMAKE_MAKE_PROGRAM não definido).',
        suggestedTerminalCommand: ninjaCmd,
        externalHelpUrl: 'https://ninja-build.org/',
        steps: [
          'Instale o Ninja no PATH (`$ninjaCmd`) ou informe `-DCMAKE_MAKE_PROGRAM` no `CMakeLists.txt` do módulo C++.',
          'Após instalar no PATH, reinicie o FLRD/terminal para atualizar as variáveis de ambiente e rode novamente.',
        ],
      );
    }

    final isSdkLicenseOrComponent =
        lower.contains('licenses not accepted') ||
            lower.contains('you have not accepted the license agreements') ||
            lower.contains('cmdline-tools component is missing') ||
            lower.contains('failed to install the following android sdk packages');

    if (isSdkLicenseOrComponent) {
      return const AndroidBuildDiagnostic(
        issueType: AndroidBuildIssueType.androidSdkLicenseOrComponentMissing,
        title: 'Licenças ou componentes do Android SDK pendentes',
        explanation:
            'O build falhou porque há licenças do Android SDK não aceitas ou o pacote `cmdline-tools` está ausente.',
        suggestedTerminalCommand: 'flutter doctor --android-licenses',
        steps: [
          'Execute `flutter doctor --android-licenses` no terminal interativo e confirme com `y`.',
          'Se faltar `cmdline-tools`, abra o Android Studio > SDK Manager > SDK Tools e marque "Android SDK Command-line Tools".',
        ],
      );
    }

    return null;
  }

  /// Inspects failed build logs together with locally installed JDKs and the
  /// target project's `gradle-wrapper.properties`.
  Future<AndroidBuildDiagnostic?> diagnoseBuildFailure(
    List<String> logLines, {
    String? projectPath,
  }) async {
    String? projectGradleVersion;
    if (projectPath != null && projectPath.trim().isNotEmpty) {
      final wrapperPath = _joinOsPath(
        _joinOsPath(_joinOsPath(projectPath.trim(), 'android'), 'gradle'),
        _joinOsPath('wrapper', 'gradle-wrapper.properties'),
      );
      projectGradleVersion =
          extractGradleWrapperVersion(_readFileSync(wrapperPath));
    }

    final initial = classifyBuildFailureLogs(
      logLines,
      projectGradleVersion: projectGradleVersion,
    );
    if (initial == null) return null;

    if (initial.issueType == AndroidBuildIssueType.javaGradleIncompatibility) {
      final jdks = await discoverCompatibleJdks();
      return classifyBuildFailureLogs(
        logLines,
        availableCompatibleJdks: jdks,
        projectGradleVersion: projectGradleVersion,
      );
    }

    return initial;
  }

  Future<({String? adbPath, String? sdkPath})> _locateAdbAndSdk() async {
    final env = _environmentProvider();
    final adbExe = _isWindows ? 'adb.exe' : 'adb';

    String? adbPath;
    String? sdkPath;

    final candidateSdkRoots = <String>[];
    void addSdkCandidate(String? raw) {
      final cleaned = raw?.trim();
      if (cleaned != null &&
          cleaned.isNotEmpty &&
          !candidateSdkRoots.contains(cleaned)) {
        candidateSdkRoots.add(cleaned);
      }
    }

    addSdkCandidate(env['ANDROID_HOME']);
    addSdkCandidate(env['ANDROID_SDK_ROOT']);

    if (_isWindows) {
      final localAppData = env['LOCALAPPDATA'];
      final userProfile = env['USERPROFILE'];
      if (localAppData != null && localAppData.isNotEmpty) {
        addSdkCandidate(p.join(localAppData, 'Android', 'Sdk'));
      }
      addSdkCandidate(r'C:\Android\Sdk');
      addSdkCandidate(r'C:\Android');
      if (userProfile != null && userProfile.isNotEmpty) {
        addSdkCandidate(p.join(userProfile, 'Android', 'Sdk'));
      }
    } else {
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        addSdkCandidate(p.join(home, 'Library', 'Android', 'sdk'));
        addSdkCandidate(p.join(home, 'Android', 'Sdk'));
      }
    }

    for (final root in candidateSdkRoots) {
      if (_dirExists(root)) {
        sdkPath ??= root;
        final candidateAdb = p.join(root, 'platform-tools', adbExe);
        if (_fileExists(candidateAdb)) {
          adbPath = candidateAdb;
          sdkPath = root;
          break;
        }
      }
    }

    // Fallback: locate `adb` in system PATH via `where.exe` / `which`.
    if (adbPath == null) {
      try {
        final locator = _isWindows ? 'where.exe' : 'which';
        final res = await _processRunner(
          locator,
          ['adb'],
          runInShell: _isWindows,
        );
        if (res.exitCode == 0) {
          final firstLine = res.stdout
              .toString()
              .split(RegExp(r'\r?\n'))
              .map((l) => l.trim())
              .firstWhere((l) => l.isNotEmpty, orElse: () => '');
          if (firstLine.isNotEmpty) {
            adbPath = firstLine;
            if (sdkPath == null) {
              final ptDir = p.dirname(firstLine);
              if (p.basename(ptDir).toLowerCase() == 'platform-tools') {
                sdkPath = p.dirname(ptDir);
              }
            }
          }
        }
      } catch (_) {}
    }

    return (adbPath: adbPath, sdkPath: sdkPath);
  }

  Future<bool> _checkJavaAvailable() async {
    try {
      final res = await _processRunner(
        'java',
        const ['-version'],
        runInShell: _isWindows,
      );
      if (res.exitCode == 0) return true;
    } catch (_) {}

    final env = _environmentProvider();
    final javaHome = env['JAVA_HOME'];
    final javaExe = _isWindows ? 'java.exe' : 'java';
    if (javaHome != null && javaHome.isNotEmpty) {
      if (_fileExists(p.join(javaHome, 'bin', javaExe))) return true;
    }

    if (_isWindows) {
      const studioJbr = r'C:\Program Files\Android\Android Studio\jbr\bin\java.exe';
      if (_fileExists(studioJbr)) return true;
    }

    return false;
  }

  Future<List<AdbDeviceEntry>> _runAdbDevices(String adbPath) async {
    try {
      final res = await _processRunner(
        adbPath,
        const ['devices', '-l'],
        runInShell: false,
      );
      if (res.exitCode != 0) return const [];
      return parseAdbDevicesOutput(res.stdout.toString());
    } catch (_) {
      return const [];
    }
  }

  Future<List<WindowsUsbDeviceInfo>> _probeWindowsUsbDevices() async {
    const psScript = r'''
$ProgressPreference = 'SilentlyContinue'
$items = @(Get-CimInstance Win32_PnPEntity -Filter "DeviceID LIKE 'USB\\%'" | Where-Object { $_.Service -eq 'WINUSB' -or $_.Service -eq 'WUDFWpdMtp' -or $_.Name -match 'ADB|Android|Samsung|Galaxy|Pixel|Motorola|Xiaomi|Redmi|OnePlus|Phone|SM-' } | Select-Object Name, Status, ConfigManagerErrorCode, Service, DeviceID, @{N='CompatibleID';E={$_.CompatibleID}})
ConvertTo-Json -InputObject $items -Compress
''';
    try {
      final encoded = encodePowerShellScriptBase64(psScript);
      final res = await _processRunner(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
        runInShell: false,
      );
      if (res.exitCode != 0) return const [];
      return parseWindowsUsbDevicesJson(res.stdout.toString());
    } catch (_) {
      return const [];
    }
  }

  /// Encodes a PowerShell script as UTF-16LE Base64 for `-EncodedCommand`.
  static String encodePowerShellScriptBase64(String script) {
    final codeUnits = script.codeUnits;
    final bytes = Uint8List(codeUnits.length * 2);
    for (var i = 0; i < codeUnits.length; i++) {
      bytes[i * 2] = codeUnits[i] & 0xFF;
      bytes[i * 2 + 1] = (codeUnits[i] >> 8) & 0xFF;
    }
    return base64Encode(bytes);
  }

  /// Parses `adb devices -l` stdout lines into structured [AdbDeviceEntry] items.
  static List<AdbDeviceEntry> parseAdbDevicesOutput(String rawStdout) {
    final entries = <AdbDeviceEntry>[];
    final lineRegex = RegExp(
      r'^(\S+)\s+(device|unauthorized|offline|authorizing|no permissions|recovery|sideload|bootloader)\b(.*)$',
    );
    final modelRegex = RegExp(r'\bmodel:(\S+)');

    for (final rawLine in rawStdout.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty ||
          line.startsWith('*') ||
          line.toLowerCase().startsWith('list of devices')) {
        continue;
      }

      final match = lineRegex.firstMatch(line);
      if (match == null) continue;

      final serial = match.group(1)!;
      final state = match.group(2)!;
      final details = match.group(3) ?? '';
      final modelRaw = modelRegex.firstMatch(details)?.group(1);
      final model = modelRaw?.replaceAll('_', ' ');

      entries.add(
        AdbDeviceEntry(
          serial: serial,
          state: state,
          model: model,
          rawLine: line,
        ),
      );
    }

    return entries;
  }

  /// Parses JSON returned by the Windows `Win32_PnPEntity` CIM query.
  static List<WindowsUsbDeviceInfo> parseWindowsUsbDevicesJson(String rawStdout) {
    final trimmed = rawStdout.trim();
    if (trimmed.isEmpty) return const [];

    // Locate the outermost JSON array or object in case PowerShell emits CLIXML/progress preamble.
    String? jsonSlice;
    final arrStart = trimmed.indexOf('[');
    final arrEnd = trimmed.lastIndexOf(']');
    if (arrStart != -1 && arrEnd > arrStart) {
      jsonSlice = trimmed.substring(arrStart, arrEnd + 1);
    } else {
      final objStart = trimmed.indexOf('{');
      final objEnd = trimmed.lastIndexOf('}');
      if (objStart != -1 && objEnd > objStart) {
        jsonSlice = trimmed.substring(objStart, objEnd + 1);
      }
    }
    if (jsonSlice == null) return const [];

    try {
      final decoded = jsonDecode(jsonSlice);
      final rawList = decoded is List
          ? decoded
          : (decoded is Map ? [decoded] : const <Object?>[]);

      final results = <WindowsUsbDeviceInfo>[];
      for (final item in rawList) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);

        final compatibleIds = <String>[];
        final rawCompat = map['CompatibleID'];
        if (rawCompat is List) {
          compatibleIds.addAll(rawCompat.map((e) => e.toString()));
        } else if (rawCompat is Map && rawCompat['value'] is List) {
          compatibleIds.addAll(
            (rawCompat['value'] as List).map((e) => e.toString()),
          );
        } else if (rawCompat is String && rawCompat.isNotEmpty) {
          compatibleIds.add(rawCompat);
        }

        final rawErrCode = map['ConfigManagerErrorCode'];
        final errorCode = rawErrCode is int
            ? rawErrCode
            : int.tryParse(rawErrCode?.toString() ?? '') ?? 0;

        results.add(
          WindowsUsbDeviceInfo(
            name: (map['Name'] ?? '').toString().trim(),
            status: (map['Status'] ?? '').toString().trim(),
            errorCode: errorCode,
            service: (map['Service'] ?? '').toString().trim(),
            deviceId: (map['DeviceID'] ?? '').toString().trim(),
            compatibleIds: compatibleIds,
          ),
        );
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Builds a comprehensive, human-friendly diagnosis from collected probe results.
  static AndroidConnectionDiagnostic buildConnectionDiagnostic({
    required List<ConnectedAndroidDevice> devices,
    String? adbPath,
    String? discoveredSdkPath,
    bool hasJava = false,
    List<AdbDeviceEntry> adbDevices = const [],
    List<WindowsUsbDeviceInfo> usbDevices = const [],
    bool isWindows = true,
  }) {
    if (devices.isNotEmpty) {
      return AndroidConnectionDiagnostic(
        devices: devices,
        issueType: AndroidConnectionIssueType.none,
        title: '${devices.length} aparelho(s) Android pronto(s)',
        summary: 'Dispositivo pronto para depuração em tempo real.',
        adbPath: adbPath,
        discoveredSdkPath: discoveredSdkPath,
        hasJava: hasJava,
      );
    }

    final adbUsb = usbDevices.where((d) => d.isAdbInterface).toList();
    final phoneUsb = usbDevices.where((d) => !d.isAdbInterface && d.isPhoneLike).toList();

    final primaryAdbUsb = adbUsb.isNotEmpty ? adbUsb.first : null;
    final matchingPhoneUsb = _findMatchingPhoneSibling(
      adbInterface: primaryAdbUsb,
      phoneDevices: phoneUsb,
    );

    final usbLabel = _formatDetectedUsbLabel(
      adbInterface: primaryAdbUsb,
      phoneSibling: matchingPhoneUsb,
    );
    final isSamsungUsb = (matchingPhoneUsb?.vidPidKey?.contains('04E8') ?? false) ||
        (primaryAdbUsb?.vidPidKey?.contains('04E8') ?? false) ||
        (usbLabel?.toLowerCase().contains('samsung') ?? false) ||
        (usbLabel?.toLowerCase().contains('s25') ?? false) ||
        (usbLabel?.toLowerCase().contains('galaxy') ?? false);

    final checks = <AndroidEnvironmentCheck>[
      if (isWindows)
        AndroidEnvironmentCheck(
          label: 'Celular na USB (Windows)',
          status: (primaryAdbUsb != null || matchingPhoneUsb != null)
              ? DiagnosticCheckStatus.ok
              : DiagnosticCheckStatus.warning,
          detail: (matchingPhoneUsb != null)
              ? '${matchingPhoneUsb.name} detectado'
              : (primaryAdbUsb != null
                  ? '${primaryAdbUsb.name} detectado'
                  : 'Nenhum celular Android visto na porta USB'),
        ),
      if (isWindows)
        AndroidEnvironmentCheck(
          label: 'Depuração USB (Interface ADB)',
          status: primaryAdbUsb == null
              ? (matchingPhoneUsb != null
                  ? DiagnosticCheckStatus.error
                  : DiagnosticCheckStatus.warning)
              : (primaryAdbUsb.isHealthy
                  ? DiagnosticCheckStatus.ok
                  : DiagnosticCheckStatus.error),
          detail: primaryAdbUsb == null
              ? (matchingPhoneUsb != null
                  ? 'Interface ADB ausente (Depuração USB desligada ou modo só carregamento)'
                  : 'Aguardando aparelho com Depuração USB ativa')
              : (primaryAdbUsb.isHealthy
                  ? 'Interface ADB ativa no Windows (${primaryAdbUsb.service})'
                  : 'Erro no driver USB (${primaryAdbUsb.status}, código ${primaryAdbUsb.errorCode})'),
        ),
      AndroidEnvironmentCheck(
        label: 'Android SDK & ADB (adb.exe)',
        status: adbPath != null
            ? DiagnosticCheckStatus.ok
            : (discoveredSdkPath != null
                ? DiagnosticCheckStatus.warning
                : DiagnosticCheckStatus.error),
        detail: adbPath != null
            ? 'Encontrado em $adbPath'
            : (discoveredSdkPath != null
                ? 'SDK em $discoveredSdkPath, mas falta Platform-Tools (adb.exe)'
                : 'Não encontrado no sistema (Android SDK ausente)'),
      ),
      AndroidEnvironmentCheck(
        label: 'Java JDK (Compilação Gradle)',
        status: hasJava
            ? DiagnosticCheckStatus.ok
            : DiagnosticCheckStatus.warning,
        detail: hasJava
            ? 'Java disponível no ambiente'
            : 'Java JDK não encontrado (necessário para compilar no aparelho)',
      ),
    ];

    // 1. ADB found an unauthorized device waiting for RSA prompt approval.
    final unauthList = adbDevices.where((d) => d.isUnauthorized).toList();
    if (unauthList.isNotEmpty) {
      final target = unauthList.first;
      return AndroidConnectionDiagnostic(
        issueType: AndroidConnectionIssueType.unauthorized,
        title: 'Autorize a Depuração USB na tela do aparelho',
        summary:
            'O PC e o ADB já enxergaram ${target.displayName}, mas ele está aguardando você aceitar a chave RSA na tela do celular.',
        steps: const [
          'Desbloqueie a tela do seu celular Android agora.',
          'Toque em "Permitir" na janela "Permitir depuração USB?" (marque "Sempre permitir a partir deste computador").',
          'Se a janela não apareceu: vá em Opções do desenvolvedor > Revogar autorizações de depuração USB e reconecte o cabo.',
          'Clique em "Testar Conexão Novamente" aqui no FLRD.',
        ],
        checks: [
          ...checks,
          AndroidEnvironmentCheck(
            label: 'Autorização ADB no aparelho',
            status: DiagnosticCheckStatus.error,
            detail: '${target.displayName} está como "unauthorized"',
          ),
        ],
        detectedUsbDeviceName: usbLabel ?? target.displayName,
        discoveredSdkPath: discoveredSdkPath,
        adbPath: adbPath,
        hasJava: hasJava,
      );
    }

    // 2. ADB found an offline device.
    final offlineList = adbDevices.where((d) => d.isOffline).toList();
    if (offlineList.isNotEmpty) {
      final target = offlineList.first;
      return AndroidConnectionDiagnostic(
        issueType: AndroidConnectionIssueType.offline,
        title: 'Aparelho desconectado / Offline no ADB',
        summary:
            'O ${target.displayName} apareceu no ADB como offline. Normalmente ocorre por cabo USB instável ou modo de conexão USB.',
        steps: const [
          'Desconecte o cabo USB e ligue em outra porta USB direta do computador (evite hubs ou adaptadores soltos).',
          'Na notificação USB do celular, selecione "Transferência de arquivos / Android Auto" (MTP).',
          'Desative e reative a chave "Depuração USB" em Opções do desenvolvedor.',
          'Clique em "Testar Conexão Novamente".',
        ],
        checks: [
          ...checks,
          AndroidEnvironmentCheck(
            label: 'Autorização ADB no aparelho',
            status: DiagnosticCheckStatus.warning,
            detail: '${target.displayName} está como "offline"',
          ),
        ],
        detectedUsbDeviceName: usbLabel ?? target.displayName,
        discoveredSdkPath: discoveredSdkPath,
        adbPath: adbPath,
        hasJava: hasJava,
        suggestedCommand: 'adb kill-server; adb start-server',
      );
    }

    // 3. ADB sees a ready device, yet `flutter devices` returned 0 -> Flutter SDK config/licenses issue.
    final readyAdb = adbDevices.where((d) => d.isReady).toList();
    if (readyAdb.isNotEmpty) {
      final target = readyAdb.first;
      return AndroidConnectionDiagnostic(
        issueType: AndroidConnectionIssueType.adbReadyFlutterBlocked,
        title: 'Aparelho detectado no ADB, mas bloqueado no Flutter',
        summary:
            'O ADB já comunicou com ${target.displayName}, porém o Flutter não conseguiu listar o aparelho por configuração pendente do SDK ou licenças.',
        steps: [
          if (discoveredSdkPath != null)
            'Clique em "Configurar SDK no Flutter" abaixo para vincular "$discoveredSdkPath".'
          else
            'Configure o caminho do Android SDK com: flutter config --android-sdk <caminho>',
          'Aceite as licenças Android executando: flutter doctor --android-licenses',
          if (!hasJava)
            'Instale o Java JDK 17 para permitir compilar o app no aparelho.',
          'Abra o Android Studio > SDK Manager > SDK Tools e marque "Android SDK Command-line Tools (latest)".',
        ],
        checks: [
          ...checks,
          AndroidEnvironmentCheck(
            label: 'Autorização ADB no aparelho',
            status: DiagnosticCheckStatus.ok,
            detail: '${target.displayName} autorizado no ADB',
          ),
        ],
        detectedUsbDeviceName: usbLabel ?? target.displayName,
        discoveredSdkPath: discoveredSdkPath,
        adbPath: adbPath,
        hasJava: hasJava,
        suggestedCommand: discoveredSdkPath != null
            ? 'flutter config --android-sdk "$discoveredSdkPath"; flutter doctor --android-licenses'
            : 'flutter doctor --android-licenses',
      );
    }

    // 4. Windows sees an active ADB USB Interface (exact S25 Ultra case!), but `adb.exe` / SDK is missing!
    if (adbPath == null && primaryAdbUsb != null) {
      final hasSdkWithoutPlatformTools = discoveredSdkPath != null;
      return AndroidConnectionDiagnostic(
        issueType: hasSdkWithoutPlatformTools
            ? AndroidConnectionIssueType.unconfiguredSdkFound
            : AndroidConnectionIssueType.usbInterfaceWithoutSdk,
        title: hasSdkWithoutPlatformTools
            ? 'SDK encontrado sem Platform-Tools (adb.exe)'
            : 'Celular conectado com Depuração USB, mas falta o Android SDK / ADB',
        summary:
            'O Windows já detectou "${usbLabel ?? primaryAdbUsb.name}" com Depuração USB ativa, mas o computador ainda não possui o ${hasSdkWithoutPlatformTools ? "Platform-Tools (adb.exe)" : "Android SDK (adb.exe)"}${hasJava ? "" : " nem o Java JDK"} instalado.',
        steps: hasSdkWithoutPlatformTools
            ? [
                'Abra o Android Studio > Settings > Android SDK > aba "SDK Tools".',
                'Marque "Android SDK Platform-Tools" e "Android SDK Command-line Tools (latest)" e clique em Apply.',
                'Se precisar, clique em "Configurar SDK no Flutter" para apontar para "$discoveredSdkPath".',
                'Depois volte e clique em "Testar Conexão Novamente".',
              ]
            : [
                'Instale o Android Studio (ele baixa o Android SDK + adb.exe) e o Java JDK 17 — você pode usar o comando PowerShell pronto abaixo ou o botão de download.',
                'Abra o Android Studio uma vez e conclua o assistente inicial ("Standard") para baixar o SDK automaticamente.',
                'Aceite as licenças rodando no terminal: flutter doctor --android-licenses',
                'Com o cabo conectado, desbloqueie o celular e toque em "Permitir depuração USB?".',
              ],
        checks: checks,
        detectedUsbDeviceName: usbLabel,
        discoveredSdkPath: discoveredSdkPath,
        adbPath: adbPath,
        hasJava: hasJava,
        suggestedCommand: hasSdkWithoutPlatformTools
            ? 'flutter config --android-sdk "$discoveredSdkPath"'
            : 'winget install -e --id Google.AndroidStudio; winget install -e --id EclipseAdoptium.Temurin.17.JDK',
        actionUrl: 'https://developer.android.com/studio',
        actionUrlLabel: 'Baixar Android Studio',
      );
    }

    // 5. `adb.exe` IS installed, Windows sees ADB Interface, yet `adb devices` returned nothing -> OEM USB Driver or cable/port!
    if (adbPath != null && primaryAdbUsb != null) {
      return AndroidConnectionDiagnostic(
        issueType: AndroidConnectionIssueType.driverOrUsbModeSuspected,
        title: 'Interface ADB detectada, mas o ADB não respondeu',
        summary:
            'O Windows enxergou "${usbLabel ?? primaryAdbUsb.name}" na USB, mas o adb.exe não listou o aparelho.${!primaryAdbUsb.isHealthy ? " Há erro de driver (código ${primaryAdbUsb.errorCode})." : ""}',
        steps: [
          if (isSamsungUsb)
            'Instale o Samsung Android USB Driver oficial para Windows (muitas vezes o driver genérico WinUSB não conclui a mão dupla com aparelhos Galaxy).'
          else
            'Instale ou atualize o Driver USB oficial do fabricante (ou Google USB Driver).',
          'Mude a conexão USB no celular para "Transferência de arquivos" (MTP) em vez de "Carregamento apenas".',
          'Teste outro cabo USB de dados (cabos só de energia falham) e porta USB direta no PC.',
          'Reinicie o servidor ADB com: adb kill-server; adb start-server',
        ],
        checks: checks,
        detectedUsbDeviceName: usbLabel,
        discoveredSdkPath: discoveredSdkPath,
        adbPath: adbPath,
        hasJava: hasJava,
        suggestedCommand: 'adb kill-server; adb start-server',
        actionUrl: isSamsungUsb
            ? 'https://developer.samsung.com/android-usb-driver'
            : 'https://developer.android.com/studio/run/win-usb',
        actionUrlLabel: isSamsungUsb
            ? 'Baixar Driver USB Samsung'
            : 'Guia Driver USB Google',
      );
    }

    // 6. Windows sees a phone (MTP/WPD) WITHOUT any ADB interface!
    if (primaryAdbUsb == null && matchingPhoneUsb != null) {
      return AndroidConnectionDiagnostic(
        issueType: AndroidConnectionIssueType.usbPhoneWithoutAdbInterface,
        title: 'Celular conectado na USB sem Depuração ADB ativa',
        summary:
            'O Windows reconheceu "${matchingPhoneUsb.name}" apenas como armazenamento de arquivos (MTP), sem a interface de depuração ADB.',
        steps: [
          'No celular, vá em Configurações > Sobre o telefone > Informações do software e toque 7 vezes em "Número de compilação".',
          'Entre em Configurações > Opções do desenvolvedor e ative "Depuração USB".',
          'Na notificação USB do celular, confirme o modo "Transferência de arquivos / Android Auto".',
          'Desconecte e reconecte o cabo USB (aceite o popup RSA na tela se aparecer).',
        ],
        checks: checks,
        detectedUsbDeviceName: matchingPhoneUsb.name,
        discoveredSdkPath: discoveredSdkPath,
        adbPath: adbPath,
        hasJava: hasJava,
      );
    }

    // 7. No USB ADB/phone interface AND missing Android SDK/ADB altogether!
    if (adbPath == null) {
      return AndroidConnectionDiagnostic(
        issueType: AndroidConnectionIssueType.missingAndroidSdk,
        title: 'Android SDK e ADB não encontrados neste computador',
        summary:
            'Este PC ainda não tem o Android SDK (adb.exe)${hasJava ? "" : " nem o Java JDK"} configurado para detectar ou compilar apps em celulares Android.',
        steps: [
          'Instale o Android Studio e o Java JDK 17 (use o comando PowerShell pronto abaixo ou clique em "Baixar Android Studio").',
          'Abra o Android Studio uma vez para baixar automaticamente o Android SDK e o Platform-Tools (adb.exe).',
          'Conecte seu celular Android via cabo USB de dados com a Depuração USB ativada.',
          'Clique em "Testar Conexão Novamente".',
        ],
        checks: checks,
        discoveredSdkPath: discoveredSdkPath,
        adbPath: adbPath,
        hasJava: hasJava,
        suggestedCommand: discoveredSdkPath != null
            ? 'flutter config --android-sdk "$discoveredSdkPath"'
            : 'winget install -e --id Google.AndroidStudio; winget install -e --id EclipseAdoptium.Temurin.17.JDK',
        actionUrl: 'https://developer.android.com/studio',
        actionUrlLabel: 'Baixar Android Studio',
      );
    }

    // 8. SDK & ADB are installed properly, just no Android device/emulator plugged in yet.
    return AndroidConnectionDiagnostic(
      issueType: AndroidConnectionIssueType.noDeviceConnected,
      title: 'Nenhum celular ou emulador Android conectado',
      summary:
          'O Android SDK e o ADB estão prontos neste PC, mas nenhum aparelho foi detectado na porta USB ou emulador ativo.',
      steps: const [
        'Conecte o celular com um cabo USB de transferência de dados (alguns cabos carregam mas não passam dados).',
        'Ative "Depuração USB" em Configurações > Opções do desenvolvedor.',
        'Mude o modo USB para "Transferência de arquivos" e desbloqueie a tela do aparelho.',
        'Ou inicie um Emulador Android pelo Android Studio e clique em "Testar Conexão Novamente".',
      ],
      checks: checks,
      discoveredSdkPath: discoveredSdkPath,
      adbPath: adbPath,
      hasJava: hasJava,
    );
  }

  static WindowsUsbDeviceInfo? _findMatchingPhoneSibling({
    required WindowsUsbDeviceInfo? adbInterface,
    required List<WindowsUsbDeviceInfo> phoneDevices,
  }) {
    if (phoneDevices.isEmpty) return null;
    final adbVidPid = adbInterface?.vidPidKey;
    if (adbVidPid != null) {
      for (final phone in phoneDevices) {
        if (phone.vidPidKey == adbVidPid) {
          return phone;
        }
      }
    }
    return phoneDevices.first;
  }

  static String? _formatDetectedUsbLabel({
    required WindowsUsbDeviceInfo? adbInterface,
    required WindowsUsbDeviceInfo? phoneSibling,
  }) {
    if (phoneSibling != null && adbInterface != null) {
      return '${phoneSibling.name} (${adbInterface.name})';
    }
    return phoneSibling?.name ?? adbInterface?.name;
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
      runInShell: _isWindows,
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
      if (_isWindows) {
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
