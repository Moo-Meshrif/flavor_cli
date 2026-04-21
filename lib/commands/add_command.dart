import '../services/config_service.dart';
import '../utils/logger.dart';
import '../utils/validation.dart';
import '../runner/setup_runner.dart';

class AddCommand {
  final _log = AppLogger();

  Future<void> execute(List<String> args) async {
    if (!ConfigService.isValidProject(_log)) return;

    if (!ConfigService.isInitialized()) {
      _log.error('❌ Error: Project not initialized. Run "init" first.');
      return;
    }

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
      await SetupRunner(logger: _log).run(ConfigService.load());

      _log.success('✅ Flavor "$newFlavor" added successfully!');
    } catch (e) {
      _log.error('❌ Failed to add flavor: $e');
    }
  }
}
