class ValidationUtils {
  /// Checks if a string is a valid Dart identifier.
  /// - Must start with a letter or underscore.
  /// - Must contain only letters, numbers, and underscores.
  /// - Must not be a Dart reserved keyword.
  static bool isValidIdentifier(String name) {
    if (name.isEmpty) return false;
    
    // Check regex: start with [a-zA-Z_], followed by [a-zA-Z0-9_]*
    final identifierRegex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
    if (!identifierRegex.hasMatch(name)) return false;

    // Check reserved keywords
    return !_reservedKeywords.contains(name);
  }

  static const _reservedKeywords = {
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
    'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
    'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
    'factory', 'false', 'final', 'finally', 'for', 'get', 'if', 'implements',
    'import', 'in', 'is', 'late', 'library', 'mixin', 'new', 'null', 'operator',
    'part', 'rethrow', 'return', 'set', 'show', 'static', 'super', 'switch',
    'sync', 'this', 'throw', 'true', 'try', 'typedef', 'var', 'void', 'while',
    'with', 'yield'
  };

  /// Checks if a string contains Arabic characters.
  static bool hasArabic(String text) {
    if (text.isEmpty) return false;
    // Main Arabic range
    return RegExp('[\u0600-\u06FF]').hasMatch(text);
  }
}
