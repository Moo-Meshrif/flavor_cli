// flavor_cli: added
class TypeUtils {
  /// Returns a sensible default value for a given Dart type as a string for prompting.
  static String getDefaultValueForType(String type) {
    switch (type.trim()) {
      case 'bool':
        return 'false';
      case 'int':
        return '0';
      case 'double':
        return '0.0';
      case 'String':
        return '';
      default:
        if (type.contains('?')) return 'null';
        return '';
    }
  }

  /// Returns a sensible default value for a given Dart type as its actual literal type.
  static dynamic getDefaultTypedValueForType(String type) {
    switch (type.trim()) {
      case 'bool':
        return false;
      case 'int':
        return 0;
      case 'double':
        return 0.0;
      case 'String':
        return '';
      default:
        if (type.contains('?')) return null;
        return '';
    }
  }

  /// Parses a string value into its target type.
  static dynamic parseToType(String type, String value) {
    if (value.isEmpty) return getDefaultTypedValueForType(type);

    switch (type.trim()) {
      case 'bool':
        return value.toLowerCase() == 'true';
      case 'int':
        return int.tryParse(value) ?? 0;
      case 'double':
        return double.tryParse(value) ?? 0.0;
      case 'String':
        return value;
      default:
        if (value == 'null') return null;
        return value;
    }
  }

  /// Formats a value for use in Dart code based on its type.
  static String formatValueForDart(String type, dynamic value) {
    if (value == null) return 'null';

    // If it's already the correct type, format it
    if (type.trim() == 'bool' && value is bool) return value.toString();
    if (type.trim() == 'int' && value is int) return value.toString();
    if (type.trim() == 'double' && value is num) return value.toString();
    if (type.trim() == 'String' && value is String) {
      final escaped = value.replaceAll("'", "\\'");
      return "'$escaped'";
    }

    // Fallback if it's a string from legacy config
    final stringVal = value.toString();
    if (stringVal.isEmpty) return _getDefaultDartLiteralForType(type);

    switch (type.trim()) {
      case 'bool':
        return stringVal.toLowerCase() == 'true' ? 'true' : 'false';
      case 'int':
        return int.tryParse(stringVal)?.toString() ?? '0';
      case 'double':
        return double.tryParse(stringVal)?.toString() ?? '0.0';
      case 'String':
        final escaped = stringVal.replaceAll("'", "\\'");
        return "'$escaped'";
      default:
        if (stringVal == 'null') return 'null';
        return "'$stringVal'";
    }
  }

  static String _getDefaultDartLiteralForType(String type) {
    switch (type.trim()) {
      case 'bool':
        return 'false';
      case 'int':
        return '0';
      case 'double':
        return '0.0';
      case 'String':
        return "''";
      default:
        if (type.contains('?')) return 'null';
        return "''";
    }
  }
}
