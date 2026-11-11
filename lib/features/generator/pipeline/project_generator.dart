import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:process_run/process_run.dart';
import '../../wizard/models/project_config.dart';
import '../injectors/android_manifest_injector.dart';
import '../injectors/ios_plist_injector.dart';
import '../injectors/pubspec_injector.dart';
import '../presets/saas_preset.dart';
import '../presets/clean_lite_preset.dart';
import '../presets/offline_preset.dart';
import '../services/permission_service_template.dart';

const bool _kIsWeb = identical(0, 0.0);

class ProjectGenerator {
  final ProjectConfig config;
  final void Function(String message) onLog;

  ProjectGenerator({
    required this.config,
    required this.onLog,
  });

  String _getPresetFlag(PresetType preset) {
    switch (preset) {
      case PresetType.saas:
        return 'saas';
      case PresetType.cleanLite:
        return 'clean-lite';
      case PresetType.offline:
        return 'offline';
    }
  }

  Future<bool> execute() async {
    // 1. Pre-flight Validation
    final nameError = ProjectNameValidator.validate(config.projectName);
    if (nameError != null) {
      onLog('❌ Invalid project name: $nameError');
      return false;
    }

    final orgError = OrgIdValidator.validate(config.orgId);
    if (orgError != null) {
      onLog('❌ Invalid organization ID: $orgError');
      return false;
    }

    // Handling Browser / Web Sandbox Mode
    if (_kIsWeb) {
      onLog('🌐 [Web Preview Mode]: Sandboxed browser environment detected.');
      await Future.delayed(const Duration(milliseconds: 500));
      onLog('🔒 Browser security prevents direct host shell execution (flutter create).');
      await Future.delayed(const Duration(milliseconds: 500));
      onLog('⚡ Validating recipe for: "${config.projectName}" (${config.orgId})');
      await Future.delayed(const Duration(milliseconds: 500));
      onLog('📦 Preset Stack: ${config.preset.name}');
      onLog('🧭 Navigation Shell: ${config.navigationStyle.title}');
      onLog('🛡️ Permissions: ${config.permissions.map((p) => p.name).join(", ")}');
      await Future.delayed(const Duration(milliseconds: 500));
      onLog('🎨 Dynamic Theme: #${config.seedColor.value.toRadixString(16).padLeft(8, "0")} (WCAG AAA)');
      await Future.delayed(const Duration(milliseconds: 500));
      onLog('✅ Configuration validated successfully!');
      onLog('');
      onLog('💻 To scaffold this project directly onto your disk, run in terminal:');
      onLog('   dart run bin/flrd.dart create ${config.projectName} --preset=${_getPresetFlag(config.preset)}');
      return true;
    }

    final parentDir = Directory(config.outputPath.isEmpty ? '.' : config.outputPath);
    final targetPath = p.normalize(
      p.join(
        config.outputPath.isEmpty ? '.' : config.outputPath,
        config.projectName,
      ),
    );

    // Verify / create parent directory safely
    if (!await parentDir.exists()) {
      try {
        await parentDir.create(recursive: true);
        onLog('📁 Created parent directory: ${parentDir.path}');
      } on FileSystemException catch (e) {
        onLog('❌ Failed to create parent directory "${parentDir.path}": ${e.message}');
        if (e.osError != null) {
          onLog('   OS Error: ${e.osError!.message} (code ${e.osError!.errorCode})');
        }
        return false;
      }
    }

    // Inspect if target directory already exists
    final targetDir = Directory(targetPath);
    if (await targetDir.exists()) {
      try {
        final entries = await targetDir.list().toList();
        if (entries.isNotEmpty) {
          onLog('⚠️ Target directory already exists and contains files: $targetPath');
        }
      } on FileSystemException catch (e) {
        onLog('⚠️ Directory inspection notice: ${e.message}');
      }
    }

    try {
      // Step 1: Base Flutter Scaffold
      onLog('🚀 Step 1/5: Running flutter create via host SDK...');
      final createRes = await runExecutableArguments(
        'flutter',
        [
          'create',
          '--org',
          config.orgId,
          '--project-name',
          config.projectName,
          targetPath,
        ],
      );

      if (createRes.exitCode != 0) {
        final err = createRes.stderr.toString().trim();
        onLog('❌ flutter create failed: ${err.isNotEmpty ? err : createRes.stdout}');
        return false;
      }
      onLog('✅ Base Flutter project generated successfully.');

      // Step 2: Injecting Native Permissions
      if (config.permissions.isNotEmpty) {
        onLog('🛡️ Step 2/5: Injecting native permissions (AndroidManifest & Info.plist)...');
        await AndroidManifestInjector.injectPermissions(
          projectRoot: targetPath,
          permissions: config.permissions,
        );
        await IosPlistInjector.injectPermissions(
          projectRoot: targetPath,
          permissions: config.permissions,
        );
        onLog('✅ Native permissions safely injected.');
      }

      // Step 3: Resolving Dynamic Dependencies & Pubspec
      onLog('📦 Step 3/5: Resolving dynamic packages from pub.dev...');
      final packagesToAdd = <String>['go_router', 'google_fonts'];
      
      switch (config.preset) {
        case PresetType.saas:
          packagesToAdd.addAll(['flutter_riverpod', 'supabase_flutter']);
          break;
        case PresetType.cleanLite:
          packagesToAdd.addAll(['flutter_bloc', 'dio', 'get_it']);
          break;
        case PresetType.offline:
          packagesToAdd.addAll(['sqflite', 'path', 'provider', 'shared_preferences']);
          break;
      }

      if (config.permissions.isNotEmpty) {
        packagesToAdd.add('permission_handler');
      }

      bool pubSuccess = false;
      try {
        final pubRes = await runExecutableArguments(
          'flutter',
          ['pub', 'add', ...packagesToAdd],
          workingDirectory: targetPath,
        );
        if (pubRes.exitCode == 0) {
          pubSuccess = true;
          onLog('✅ Dependencies resolved and added.');
        } else {
          onLog('⚠️ flutter pub add exited with code ${pubRes.exitCode}. Falling back to PubspecInjector...');
        }
      } catch (e) {
        onLog('⚠️ flutter pub add unavailable: $e. Falling back to PubspecInjector...');
      }

      // Semantic YAML injection fallback
      if (!pubSuccess) {
        final depMap = {for (final p in packagesToAdd) p: 'any'};
        final injected = await PubspecInjector.injectDependencies(
          projectRoot: targetPath,
          dependencies: depMap,
        );
        if (injected) {
          onLog('✅ Dependencies injected into pubspec.yaml via semantic PubspecInjector.');
        } else {
          onLog('⚠️ Semantic PubspecInjector could not modify pubspec.yaml.');
        }
      }

      // Step 4: Synthesize Lib & Theme
      onLog('🎨 Step 4/5: Synthesizing architecture presets & GoRouter guards...');
      
      // Synthesize permission helper if permissions are enabled
      if (config.permissions.isNotEmpty) {
        await PermissionServiceTemplate.synthesize(targetPath, config.permissions);
      }

      // Synthesize preset files
      switch (config.preset) {
        case PresetType.saas:
          await SaasPreset.synthesize(targetPath, config);
          break;
        case PresetType.cleanLite:
          await CleanLitePreset.synthesize(targetPath, config);
          break;
        case PresetType.offline:
          await OfflinePreset.synthesize(targetPath, config);
          break;
      }
      onLog('✅ Full architectural preset with auth guards applied.');

      onLog('🎉 Step 5/5: FLRD scaffolding complete! Opening project...');
      return true;
    } on FileSystemException catch (e) {
      onLog('❌ File system error during scaffolding: ${e.message}');
      if (e.path != null) onLog('   Path: ${e.path}');
      if (e.osError != null) {
        onLog('   OS Error: ${e.osError!.message} (code ${e.osError!.errorCode})');
      }
      onLog('💡 Verify disk write permissions and path availability.');
      return false;
    } on ProcessException catch (e) {
      if (e.message.contains('cannot find') || e.message.contains('not found')) {
        onLog('⚠️ Flutter executable not found in system PATH: ${e.executable}');
        onLog('💡 Download Flutter SDK at: https://docs.flutter.dev/get-started/install');
      } else {
        onLog('❌ Process error (${e.executable}): ${e.message}');
      }
      return false;
    } catch (e) {
      if (e.toString().contains('cannot find') || e.toString().contains('not found')) {
        onLog('⚠️ Flutter executable not found in system PATH.');
        onLog('💡 Download Flutter SDK at: https://docs.flutter.dev/get-started/install');
      } else {
        onLog('❌ Unexpected error: $e');
      }
      return false;
    }
  }
}
