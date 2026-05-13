import '../services/config_service.dart';
import '../runner/setup_runner.dart';
import '../utils/logger.dart';
import '../utils/validation.dart';
import '../utils/exceptions.dart';

class ReplaceCommand {
  final AppLogger _log;

  ReplaceCommand({AppLogger? logger}) : _log = logger ?? AppLogger();

  Future<void> execute() async {
    if (!ConfigService.isValidProject(_log)) return;
    if (!ConfigService.requiresInitialized(_log)) return;

    final config = ConfigService.load();
    final flavors = config.flavors;
    if (flavors.isEmpty) {
      _log.error('❌ No flavors found to replace. Run "init" first.');
      return;
    }

    final oldFlavor = _log.chooseOne(
      '👉 Select the flavor you want to rename:',
      choices: flavors,
    );

    if (oldFlavor == config.productionFlavor) {
      _log.warn(
          '⚠️ You are about to replace the production flavor ("$oldFlavor").');
      final confirm = _log.confirm('Are you sure you want to continue?');
      if (!confirm) {
        _log.info('Operation cancelled.');
        return;
      }
    }

    String newFlavor;
    while (true) {
      newFlavor = _log
          .prompt('👉 Enter the new name for "$oldFlavor":')
          .trim()
          .toLowerCase();

      if (newFlavor.isEmpty) {
        _log.error('❌ New flavor name cannot be empty.');
        continue;
      }

      if (!ValidationUtils.isValidIdentifier(newFlavor)) {
        _log.error(
            '❌ Invalid flavor name: "$newFlavor". Must be a valid Dart identifier.');
        continue;
      }

      if (flavors.contains(newFlavor)) {
        _log.error('❌ Flavor "$newFlavor" already exists.');
        continue;
      }

      break;
    }

    _log.info(
        '🔄 Orchestrating rename of "$oldFlavor" to "$newFlavor" (Tx)...');

    try {
      await SetupRunner(logger: _log).replaceFlavor(
        oldFlavor: oldFlavor,
        newFlavor: newFlavor,
      );
    } catch (e) {
      if (e is CliException && e.isLogged) return;
      _log.error('❌ Failed to replace flavor: $e');
    }
  }
}
