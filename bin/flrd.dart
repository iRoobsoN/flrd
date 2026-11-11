import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:flrd/features/generator/pipeline/project_generator.dart';
import 'package:flrd/features/wizard/models/project_config.dart';

void main(List<String> arguments) async {
  void addSharedOptions(ArgParser p) {
    p
      ..addOption('org', abbr: 'o', defaultsTo: 'com.example', help: 'Organization / Reverse domain identifier')
      ..addOption('preset', abbr: 'p', defaultsTo: 'saas', allowed: ['saas', 'clean-lite', 'offline'], help: 'Architectural preset')
      ..addOption('nav', abbr: 'n', defaultsTo: 'tabs', allowed: ['tabs', 'drawer', 'adaptive'], help: 'Navigation shell style')
      ..addOption('path', defaultsTo: '.', help: 'Target parent directory')
      ..addMultiOption('permissions', help: 'Comma-separated permissions: camera,location,notifications,photos,biometrics')
      ..addFlag('interactive', abbr: 'i', defaultsTo: false, help: 'Run interactive question wizard')
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage help');
  }

  final parser = ArgParser();
  addSharedOptions(parser);
  parser.addFlag('version', abbr: 'v', negatable: false, help: 'Show FLRD version');

  final createCmd = parser.addCommand('create');
  addSharedOptions(createCmd);

  try {
    final results = parser.parse(arguments);

    final isHelp = results['help'] == true || (results.command != null && results.command!['help'] == true);
    if (isHelp) {
      _printBanner();
      _printHelp(parser);
      exit(0);
    }

    if (results['version'] == true) {
      stdout.writeln('⚡ FLRD CLI v0.2.1 (Flutter Rapid Deployment)');
      exit(0);
    }

    _printBanner();

    // Check if arguments or create command were provided
    final command = results.command?.name;
    final rest = results.command?.rest ?? results.rest;
    String? projectName = rest.isNotEmpty ? rest.first : null;

    final isInteractive = results['interactive'] == true ||
        (results.command != null && results.command!['interactive'] == true) ||
        (command == null && projectName == null);

    ProjectConfig config;

    if (isInteractive) {
      config = await _runInteractiveWizard(projectName);
    } else {
      projectName ??= 'my_flrd_app';

      final nameErr = ProjectNameValidator.validate(projectName);
      if (nameErr != null) {
        stderr.writeln('\n\x1B[1;31m❌ Validation Error: $nameErr\x1B[0m\n');
        _printHelp(parser);
        exit(1);
      }

      config = _buildConfigFromArgs(results, projectName);

      final orgErr = OrgIdValidator.validate(config.orgId);
      if (orgErr != null) {
        stderr.writeln('\n\x1B[1;31m❌ Validation Error: $orgErr\x1B[0m\n');
        exit(1);
      }
    }

    final targetLocation = p.normalize(
      p.join(
        config.outputPath.isEmpty ? '.' : config.outputPath,
        config.projectName,
      ),
    );

    stdout.writeln('\n\x1B[1;36m⚙️  Executing FLRD Scaffolding Pipeline...\x1B[0m');
    stdout.writeln('   Project: \x1B[32m${config.projectName}\x1B[0m');
    stdout.writeln('   Org ID:  \x1B[32m${config.orgId}\x1B[0m');
    stdout.writeln('   Preset:  \x1B[35m${config.preset.name}\x1B[0m');
    stdout.writeln('   Nav:     \x1B[33m${config.navigationStyle.title}\x1B[0m');
    stdout.writeln('   Target:  \x1B[34m$targetLocation\x1B[0m\n');

    final generator = ProjectGenerator(
      config: config,
      onLog: (msg) => stdout.writeln('  $msg'),
    );

    final success = await generator.execute();

    if (success) {
      _printSuccessBox(config, targetLocation);
    } else {
      stderr.writeln('\n\x1B[1;31m❌ Scaffolding encountered errors. See logs above.\x1B[0m\n');
      exit(1);
    }
  } catch (e) {
    stderr.writeln('\x1B[31mError: $e\x1B[0m');
    _printHelp(parser);
    exit(1);
  }
}

void _printBanner() {
  stdout.writeln('''
\x1B[1;35m  ███████╗██╗     ██████╗ ██████╗ 
  ██╔════╝██║     ██╔══██╗██╔══██╗
  █████╗  ██║     ██████╔╝██║  ██║
  ██╔══╝  ██║     ██╔══██╗██║  ██║
  ██║     ███████╗██║  ██║██████╔╝
  ╚═╝     ╚══════╝╚═╝  ╚═╝╚═════╝ \x1B[0m
  \x1B[1;36m⚡ Flutter Rapid Deployment (by Robson David)\x1B[0m
  \x1B[90m--------------------------------------------------\x1B[0m''');
}

void _printHelp(ArgParser parser) {
  stdout.writeln('''
Usage: flrd <command> [options]

Commands:
  create <app_name>     Scaffold a new production-ready Flutter app

Options:
${parser.usage}

Examples:
  flrd create my_saas_app --preset=saas --nav=tabs
  flrd create enterprise_app --preset=clean-lite --nav=adaptive --org=com.mycorp
  flrd --interactive
''');
}

ProjectConfig _buildConfigFromArgs(ArgResults results, String projectName) {
  // Read option either from command or root parser
  T getOption<T>(String key, T defaultValue) {
    if (results.command != null && results.command!.wasParsed(key)) {
      return results.command![key] as T;
    }
    if (results.wasParsed(key)) {
      return results[key] as T;
    }
    if (results.command != null && results.command![key] != null) {
      return results.command![key] as T;
    }
    return (results[key] as T?) ?? defaultValue;
  }

  final presetStr = getOption<String>('preset', 'saas');
  final navStr = getOption<String>('nav', 'tabs');
  final org = getOption<String>('org', 'com.example');
  final path = getOption<String>('path', '.');

  PresetType preset;
  switch (presetStr) {
    case 'clean-lite':
      preset = PresetType.cleanLite;
      break;
    case 'offline':
      preset = PresetType.offline;
      break;
    case 'saas':
    default:
      preset = PresetType.saas;
  }

  NavigationStyle nav;
  switch (navStr) {
    case 'drawer':
      nav = NavigationStyle.drawer;
      break;
    case 'adaptive':
      nav = NavigationStyle.adaptiveRail;
      break;
    case 'tabs':
    default:
      nav = NavigationStyle.tabs;
  }

  final permList = getOption<List<String>>('permissions', []);
  final permissions = <DevicePermission>{};
  for (final p in permList) {
    switch (p.toLowerCase().trim()) {
      case 'camera':
        permissions.add(DevicePermission.camera);
        break;
      case 'location':
        permissions.add(DevicePermission.location);
        break;
      case 'notifications':
        permissions.add(DevicePermission.notifications);
        break;
      case 'photos':
        permissions.add(DevicePermission.photoLibrary);
        break;
      case 'biometrics':
        permissions.add(DevicePermission.biometrics);
        break;
    }
  }

  return ProjectConfig(
    projectName: projectName,
    orgId: org,
    outputPath: path,
    preset: preset,
    navigationStyle: nav,
    permissions: permissions.isEmpty ? {DevicePermission.notifications} : permissions,
  );
}

Future<ProjectConfig> _runInteractiveWizard(String? prefillName) async {
  stdout.writeln('\x1B[1m\nInteractive Project Wizard:\x1B[0m');

  // 1. Project Name with validation loop
  String name = prefillName ?? '';
  while (true) {
    if (name.isNotEmpty) {
      final err = ProjectNameValidator.validate(name);
      if (err == null) break;
      stdout.writeln('  \x1B[31m⚠️ $err\x1B[0m');
    }
    stdout.write('? Project Name (e.g. my_awesome_app) [my_flrd_app]: ');
    final input = stdin.readLineSync()?.trim();
    name = (input != null && input.isNotEmpty) ? input : 'my_flrd_app';
  }

  // 2. Organization ID with validation loop
  String org = 'com.example';
  while (true) {
    stdout.write('? Organization / Bundle ID [com.example]: ');
    final orgInput = stdin.readLineSync()?.trim();
    org = (orgInput != null && orgInput.isNotEmpty) ? orgInput : 'com.example';
    final err = OrgIdValidator.validate(org);
    if (err == null) break;
    stdout.writeln('  \x1B[31m⚠️ $err\x1B[0m');
  }

  // 3. Preset
  stdout.writeln('\n? Choose an Architectural Preset:');
  stdout.writeln('  [1] SaaS / Indie Hacker (Riverpod + Supabase + Router Guards)');
  stdout.writeln('  [2] Clean-Lite (BLoC 8.x + Dio + GetIt DI)');
  stdout.writeln('  [3] Offline-First Utility (SQLite / Drift + Provider)');
  stdout.write('Enter choice [1]: ');
  final presetChoice = stdin.readLineSync()?.trim();
  PresetType preset = PresetType.saas;
  if (presetChoice == '2') preset = PresetType.cleanLite;
  if (presetChoice == '3') preset = PresetType.offline;

  // 4. Navigation Style
  stdout.writeln('\n? Choose a Navigation Layout:');
  stdout.writeln('  [1] Modern Tabs (Bottom Navigation Bar)');
  stdout.writeln('  [2] Navigation Drawer');
  stdout.writeln('  [3] Adaptive Shell (Tabs on Mobile, Rail on Desktop/Tablet)');
  stdout.write('Enter choice [1]: ');
  final navChoice = stdin.readLineSync()?.trim();
  NavigationStyle nav = NavigationStyle.tabs;
  if (navChoice == '2') nav = NavigationStyle.drawer;
  if (navChoice == '3') nav = NavigationStyle.adaptiveRail;

  // 5. Target Directory
  stdout.write('\n? Target parent directory [.]: ');
  final dirInput = stdin.readLineSync()?.trim();
  final path = (dirInput != null && dirInput.isNotEmpty) ? dirInput : '.';

  return ProjectConfig(
    projectName: name,
    orgId: org,
    outputPath: path,
    preset: preset,
    navigationStyle: nav,
    permissions: const {DevicePermission.notifications},
  );
}

void _printSuccessBox(ProjectConfig config, String target) {
  stdout.writeln('''
\x1B[1;32m┌─────────────────────────────────────────────────────────────┐
│  🎉 PROJECT SCAFFOLDED SUCCESSFULLY WITH FLRD! ⚡           │
├─────────────────────────────────────────────────────────────┤\x1B[0m
  Location: \x1B[34m$target\x1B[0m
  Preset:   \x1B[35m${config.preset.name}\x1B[0m
  Nav:      \x1B[33m${config.navigationStyle.title}\x1B[0m

  \x1B[1mNext Steps:\x1B[0m
    \x1B[36mcd $target\x1B[0m
    \x1B[36mflutter run\x1B[0m

  \x1B[90mStar on GitHub: https://github.com/iRoobsoN/flrd 💙\x1B[0m
\x1B[1;32m└─────────────────────────────────────────────────────────────┘\x1B[0m
''');
}
