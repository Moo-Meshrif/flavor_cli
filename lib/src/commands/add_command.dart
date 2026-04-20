import '../services/config_service.dart';
import '../services/file_service.dart';
import '../services/android_service.dart';
import '../services/ios_service.dart';
import '../utils/logger.dart';
import '../utils/validation.dart';
import 'firebase_command.dart';

class AddCommand {
  final _log = AppLogger();

  Future<void> execute(List<String> args) async {
    if (!ConfigService.isValidProject(_log)) return;

    if (args.isEmpty) {
      _log.error(
          '❌ Error: Please specify a flavor name (e.g., dart run flavor_cli add staging)');
      return;
    }

    final newFlavor = args[0].toLowerCase().trim();

    if (!ValidationUtils.isValidIdentifier(newFlavor)) {
      _log.error(
          '❌ Error: "$newFlavor" is not a valid Dart identifier. It must start with a letter and contain only alphanumeric characters or underscores.');
      return;
    }

    // 1. Check if initialized
    if (!ConfigService.isInitialized()) {
      _log.error('❌ Error: Project not initialized. Run "init" first.');
      return;
    }

    final flavors = ConfigService.getFlavors();
    if (flavors.contains(newFlavor)) {
      _log.warn('⚠️ Flavor "$newFlavor" already exists.');
      return;
    }

    _log.info('➕ Adding flavor: $newFlavor...');

    try {
      // 2. Update Config
      ConfigService.addFlavor(newFlavor);
      final updatedFlavors = ConfigService.getFlavors();

      // 3. Update File Structure
      FileService.addFlavorToAppConfig(newFlavor); // Surgically add flavor

      final useSeparate = ConfigService.useSeparateMains();
      if (useSeparate) {
        FileService.createMainFiles(
            overwrite: false); // Create only the new one
      } else {
        FileService.integrateMainFiles(
            flavors: updatedFlavors, separate: false);
      }

      // 4. Update Platforms
      AndroidService.setupFlavors();
      IOSService.setupSchemes();
      FileService.updateVSCodeLaunchConfig();

      _log.success('✅ Flavor "$newFlavor" added successfully!');

      if (useSeparate) {
        _log.info('New main file created: lib/main/main_$newFlavor.dart');
      }
      _log.info('iOS XCConfig created: ios/Flutter/$newFlavor.xcconfig');

      // Check and re-initialize Firebase if necessary
      await FirebaseCommand.checkAndReinit(_log, targetFlavor: newFlavor);
    } catch (e) {
      _log.error('❌ Failed to add flavor: $e');
    }
  }
}
