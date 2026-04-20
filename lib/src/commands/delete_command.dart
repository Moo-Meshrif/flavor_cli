import '../services/config_service.dart';
import '../services/file_service.dart';
import '../services/android_service.dart';
import '../services/ios_service.dart';
import '../services/reset_service.dart';
import '../utils/logger.dart';
import '../utils/validation.dart';

class DeleteCommand {
  final _log = AppLogger();

  void execute(List<String> args) {
    if (!ConfigService.isValidProject(_log)) return;

    // 1. Check if initialized
    if (!ConfigService.isInitialized()) {
      _log.error('❌ Error: Project not initialized. Run "init" first.');
      return;
    }

    final flavors = ConfigService.getFlavors();
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
        _log.error(
            '❌ Error: "$flavorToDelete" is not a valid Dart identifier.');
        return;
      }

      if (!flavors.contains(flavorToDelete)) {
        _log.error('❌ Error: Flavor "$flavorToDelete" does not exist.');
        return;
      }
    }

    // 2. pen-ultimate flavor check
    if (flavors.length == 2) {
      _log.warn(
          '⚠️ Warning: Deleting this flavor will leave only one flavor ("${flavors.where((f) => f != flavorToDelete).first}").');
      _log.warn(
          'This will damage the flavor system and clear all configurations.');
      final confirmed = _log.confirm(
          'Are you sure you want to return the app to original state without any flavors?');
      if (confirmed) {
        ResetService.reset();
        return;
      } else {
        _log.info('Operation cancelled.');
        return;
      }
    }

    _log.info('🗑️ Deleting flavor: $flavorToDelete...');

    try {
      // 2. Remove from Config
      final isProduction =
          flavorToDelete == ConfigService.getProductionFlavor();
      ConfigService.removeFlavor(flavorToDelete);
      final remainingFlavors = ConfigService.getFlavors();

      if (isProduction && remainingFlavors.isNotEmpty) {
        _log.warn('⚠️ You deleted the production flavor.');
        final newProd = _log.chooseOne(
          '👉 Please select a new production flavor:',
          choices: remainingFlavors,
        );
        ConfigService.init(productionFlavor: newProd);
        _log.info('✔ Production flavor updated to: $newProd');
      }

      if (remainingFlavors.isEmpty) {
        _log.warn(
            '⚠️ Warning: No flavors left. You should probably run "init" again or add a flavor.');
      }

      // 3. Update File Structure
      FileService.removeFlavorFromAppConfig(
          flavorToDelete); // Surgically remove flavor

      final useSeparate = ConfigService.useSeparateMains();

      // Cleanup files (main file and xcconfig)
      FileService.cleanupFlavors([flavorToDelete]);

      if (!useSeparate) {
        // Update the switch case in single main file
        FileService.integrateMainFiles(
            flavors: remainingFlavors, separate: false);
      }

      // 4. Update Platforms
      AndroidService.setupFlavors(logger: _log); // Regenerates productFlavors
      FileService.updateTests();
      FileService.updateVSCodeLaunchConfig();

      // Refresh Firebase injection if present
      FileService.injectFirebase(separate: useSeparate);
      FileService.cleanupFirebaseConfig(flavorToDelete);

      _log.success('✅ Flavor "$flavorToDelete" removed successfully!');

      // 5. iOS Cleanup
      _log.info('🗑️ Running iOS automation cleanup...');
      IOSService.removeFlavorSchemes(flavorToDelete, logger: _log);
    } catch (e) {
      _log.error('❌ Failed to delete flavor: $e');
    }
  }
}
