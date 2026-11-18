import 'dart:io';
import 'package:path/path.dart' as p;

import '../../wizard/models/project_config.dart';

/// Resilient file writer for scaffolded presets.
///
/// Normalizes Windows vs POSIX path separators, creates parent directories
/// recursively, and provides actionable FileSystemException diagnostics.
class PresetFileHelper {
  PresetFileHelper._();

  /// Writes [content] to [relativePath] inside [projectRoot], ensuring parent
  /// directories exist and catching any FileSystemException.
  static Future<void> writeFile({
    required String projectRoot,
    required String relativePath,
    required String content,
  }) async {
    final fullPath = p.normalize(
      p.join(projectRoot.isEmpty ? '.' : projectRoot, relativePath),
    );
    final file = File(fullPath);

    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Failed to write scaffolded preset file "$fullPath": ${e.message}',
        fullPath,
        e.osError,
      );
    }
  }

  /// Generates `lib/core/theme/app_theme.dart` respecting whether
  /// `google_fonts` was kept or excluded by advanced user options.
  static Future<void> writeAppTheme({
    required String targetPath,
    required ProjectConfig config,
  }) async {
    final seedHex = config.seedColor.value.toRadixString(16).padLeft(8, '0');
    final useGoogleFonts =
        config.resolvedPackagesToInstall.contains('google_fonts');

    final fontImport = useGoogleFonts
        ? "import 'package:google_fonts/google_fonts.dart';\n"
        : '';
    // Use fontFamily (String?) rather than GoogleFonts.*TextTheme(ThemeData...)
    // to avoid TextTheme type conflicts between flutter/material.dart and material_ui.
    final lightFontFamily = useGoogleFonts
        ? '      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,\n'
        : '';
    final darkFontFamily = useGoogleFonts
        ? '      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,\n'
        : '';

    await writeFile(
      projectRoot: targetPath,
      relativePath: 'lib/core/theme/app_theme.dart',
      content: '''
import 'package:flutter/material.dart';
$fontImport
class AppTheme {
  AppTheme._();

  static const Color seedColor = Color(0x$seedHex);

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
$lightFontFamily      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
$darkFontFamily      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}
''',
    );
  }

  /// Generates a clean minimal entry point + theme without template boilerplate
  /// when the user chooses minimal scaffold or excludes template packages.
  static Future<void> synthesizeMinimalApp({
    required String targetPath,
    required ProjectConfig config,
  }) async {
    await writeAppTheme(targetPath: targetPath, config: config);

    final escapedName = config.projectName.replaceAll("'", "\\'");
    final darkThemeLine =
        config.enableDarkTheme ? '      darkTheme: AppTheme.darkTheme,\n' : '';
    final themeMode =
        config.enableDarkTheme ? 'ThemeMode.system' : 'ThemeMode.light';

    await writeFile(
      projectRoot: targetPath,
      relativePath: 'lib/main.dart',
      content: '''
import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$escapedName',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
$darkThemeLine      themeMode: $themeMode,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$escapedName')),
      body: const Center(
        child: Text('Estrutura limpa pronta para desenvolver.'),
      ),
    );
  }
}
''',
    );
  }
}
