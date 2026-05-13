import 'package:mason_logger/mason_logger.dart';
import 'validation.dart';

/// A wrapper around [Logger] to provide consistent logging and user prompts
/// across the application, with added validation (e.g., Arabic character detection).
class AppLogger {
  final Logger _logger = Logger();

  void info(String message) => _logger.info(message);
  void success(String message) => _logger.success(message);
  void error(String message) => _logger.err(message);
  void warn(String message) => _logger.warn(message);

  /// Prompts the user for input with an optional [defaultValue].
  /// Retries if the input contains invalid characters (e.g., Arabic).
  String prompt(String message, {String? defaultValue}) {
    while (true) {
      final input = _logger.prompt(message, defaultValue: defaultValue);
      if (ValidationUtils.hasArabic(input)) {
        error('❌ Error: Arabic input is not allowed in this tool.');
        info('   Please enter the value using Latin characters.');
        continue;
      }
      return input;
    }
  }

  /// Prompts the user for a Yes/No confirmation.
  bool confirm(String message, {bool defaultValue = false}) {
    final selection = _logger.chooseOne(
      message,
      choices: ['Yes', 'No'],
      defaultValue: defaultValue ? 'Yes' : 'No',
    );
    return selection == 'Yes';
  }

  String chooseOne(String message,
          {required List<String> choices, String? defaultValue}) =>
      _logger.chooseOne(message, choices: choices, defaultValue: defaultValue);

  List<String> chooseAny(String message,
          {required List<String> choices, List<String>? defaultValues}) =>
      _logger.chooseAny(message,
          choices: choices, defaultValues: defaultValues);
}
