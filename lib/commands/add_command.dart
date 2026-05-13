import '../services/config_service.dart';
import '../utils/logger.dart';
import '../utils/validation.dart';
import '../runner/setup_runner.dart';
import '../utils/exceptions.dart';

/// Command to add a new flavor to the project.
class AddCommand {
  final _log = AppLogger();

  /// Prompts the user for a flavor name if not provided in [args],
  /// validates it, and sets up the project structure for the new flavor.
  Future<void> execute(List<String> args) async {
    if (!ConfigService.isValidProject(_log)) return;
    if (!ConfigService.requiresInitialized(_log)) return;

    String newFlavor;
    if (args.isEmpty) {
      newFlavor = _log
          .prompt('👉 Enter the name for the new flavor:')
          .toLowerCase()
          .trim();
      if (newFlavor.isEmpty) {
        _log.error('❌ Error: Name cannot be empty.');
        return;
      }
    } else {
      newFlavor = args[0].toLowerCase().trim();
    }

    if (!ValidationUtils.isValidIdentifier(newFlavor)) {
      _log.error(
          '❌ Error: "$newFlavor" is not a valid Dart identifier. It must start with a letter and contain only alphanumeric characters or underscores.');
      return;
    }

    final config = ConfigService.load();
    if (config.flavors.contains(newFlavor)) {
      _log.warn('⚠️ Flavor "$newFlavor" already exists.');
      return;
    }

    _log.info('➕ Adding flavor: $newFlavor...');

    try {
      // 1. Update Config Native Mutation
      ConfigService.addFlavor(newFlavor);

      // 2. Delegate all file structure and platform injections to SetupRunner natively
      await SetupRunner(logger: _log)
          .run(ConfigService.load(), newFlavor: newFlavor);

      _log.success('✅ Flavor "$newFlavor" added successfully!');
    } catch (e) {
      if (e is CliException && e.isLogged) return;
      _log.error('❌ Failed to add flavor: $e');
    }
  }
}
