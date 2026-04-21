import '../services/config_service.dart';
import '../runner/setup_runner.dart';
import '../utils/logger.dart';
import '../utils/validation.dart';

class DeleteCommand {
  final _log = AppLogger();

  Future<void> execute(List<String> args) async {
    if (!ConfigService.isValidProject(_log)) return;

    if (!ConfigService.isInitialized()) {
      _log.error('❌ Error: Project not initialized. Run "init" first.');
      return;
    }

    final flavors = ConfigService.load().flavors;
    if (flavors.isEmpty) {
      _log.error('❌ Error: No flavors found in configuration to delete.');
      return;
    }

    String flavorToDelete;
    if (args.isEmpty) {
      flavorToDelete =
          _log.chooseOne('👉 Select a flavor to delete:', choices: flavors);
    } else {
      flavorToDelete = args[0].toLowerCase().trim();

      if (!ValidationUtils.isValidIdentifier(flavorToDelete)) {
        _log.error('❌ Error: "$flavorToDelete" is not a valid Dart identifier.');
        return;
      }

      if (!flavors.contains(flavorToDelete)) {
        _log.error('❌ Error: Flavor "$flavorToDelete" does not exist.');
        return;
      }
    }

    if (flavors.length == 2) {
      _log.warn('⚠️ Warning: Deleting this flavor will leave only one flavor.');
      _log.warn('This is not recommended. You should perform a full reset instead.');
      final confirmed = _log.confirm('Would you like to completely reset the project instead?');
      if (confirmed) {
        SetupRunner(logger: _log).reset();
        return;
      } else {
        _log.info('Operation cancelled.');
        return;
      }
    }

    _log.info('🗑️ Deleting flavor: $flavorToDelete...');

    try {
      final isProduction = flavorToDelete == ConfigService.load().productionFlavor;
      ConfigService.removeFlavor(flavorToDelete);
      final remainingFlavors = ConfigService.load().flavors;

      if (isProduction && remainingFlavors.isNotEmpty) {
        _log.warn('⚠️ You deleted the production flavor.');
        final newProd = _log.chooseOne(
          '👉 Please select a new production flavor:',
          choices: remainingFlavors,
        );
        ConfigService.save(ConfigService.load().copyWith(productionFlavor: newProd));
        _log.info('✔ Production flavor updated to: $newProd');
      }
      
      // Delegate completely to SetupRunner. It handles deleting orphaned files.
      await SetupRunner(logger: _log).run(ConfigService.load());

      _log.success('✅ Flavor "$flavorToDelete" removed successfully!');
    } catch (e) {
      _log.error('❌ Failed to delete flavor: $e');
    }
  }
}
