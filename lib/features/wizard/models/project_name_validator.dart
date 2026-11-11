/// Comprehensive validator for Flutter / Dart package names and organization identifiers.
class ProjectNameValidator {
  ProjectNameValidator._();

  /// Standard Dart keywords, built-in identifiers, and contextual reserved words.
  static const Set<String> dartReservedWords = {
    // Reserved words
    'assert',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'if',
    'in',
    'is',
    'new',
    'null',
    'rethrow',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'var',
    'void',
    'while',
    'with',

    // Built-in identifiers and core type names
    'abstract',
    'as',
    'bool',
    'covariant',
    'deferred',
    'double',
    'dynamic',
    'export',
    'extension',
    'external',
    'factory',
    'function',
    'get',
    'implements',
    'import',
    'int',
    'interface',
    'late',
    'library',
    'macro',
    'mixin',
    'never',
    'num',
    'object',
    'operator',
    'part',
    'record',
    'required',
    'set',
    'static',
    'string',
    'typedef',

    // Contextual keywords
    'async',
    'await',
    'yield',
    'base',
    'sealed',
    'when',
  };

  /// Reserved Flutter framework packages that cause circular or collision errors.
  static const Set<String> flutterReservedNames = {
    'flutter',
    'flutter_test',
    'sky_engine',
  };

  /// Validates a project / package name for Flutter standards.
  ///
  /// Returns `null` if valid, or a descriptive error string if invalid.
  static String? validate(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Project name cannot be empty.';
    }

    final trimmed = name.trim();

    if (trimmed.contains(' ')) {
      return 'Project name cannot contain whitespace.';
    }

    if (trimmed != trimmed.toLowerCase()) {
      final suggestion = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
      return 'Project name must be all lowercase (e.g. "$suggestion").';
    }

    if (trimmed.contains('-')) {
      final suggestion = trimmed.replaceAll('-', '_');
      return 'Project name cannot contain hyphens. Use underscores instead (e.g. "$suggestion").';
    }

    final firstChar = trimmed[0];
    if (RegExp(r'[0-9]').hasMatch(firstChar)) {
      return 'Project name cannot start with a digit.';
    }

    if (firstChar == '_') {
      return 'Project name must start with a lowercase letter, not an underscore.';
    }

    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(trimmed)) {
      return 'Project name contains invalid characters. Use only lowercase letters, digits, and underscores.';
    }

    if (dartReservedWords.contains(trimmed)) {
      return '"$trimmed" is a Dart reserved keyword and cannot be used as a package name.';
    }

    if (flutterReservedNames.contains(trimmed)) {
      return '"$trimmed" is reserved by the Flutter framework and cannot be used as a package name.';
    }

    return null;
  }
}

/// Validator for Reverse-Domain Organization / Bundle Identifiers (e.g. `com.example`, `dev.company`).
class OrgIdValidator {
  OrgIdValidator._();

  /// Validates reverse-domain organization identifier.
  ///
  /// Returns `null` if valid, or a descriptive error string if invalid.
  static String? validate(String? orgId) {
    if (orgId == null || orgId.trim().isEmpty) {
      return 'Organization ID cannot be empty.';
    }

    final trimmed = orgId.trim();

    if (trimmed.contains(' ')) {
      return 'Organization ID cannot contain whitespace.';
    }

    final segments = trimmed.split('.');
    if (segments.length < 2) {
      return 'Organization ID must have at least two segments (e.g. "com.example").';
    }

    for (final segment in segments) {
      if (segment.isEmpty) {
        return 'Organization ID cannot contain empty segments (e.g. "..").';
      }

      if (RegExp(r'^[0-9]').hasMatch(segment)) {
        return 'Segment "$segment" in Organization ID cannot start with a digit.';
      }

      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(segment)) {
        return 'Segment "$segment" in Organization ID contains invalid characters.';
      }

      if (ProjectNameValidator.dartReservedWords.contains(segment.toLowerCase())) {
        return 'Segment "$segment" in Organization ID cannot be a Dart reserved keyword.';
      }
    }

    return null;
  }
}
