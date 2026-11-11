import 'dart:io';
import 'package:path/path.dart' as p;

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
}
