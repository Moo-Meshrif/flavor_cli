import 'dart:io';
import 'package:path/path.dart' as p;

import '../services/config_service.dart';
import '../services/file_service.dart';
import '../services/android_service.dart';
import '../services/ios_service.dart';
import '../utils/logger.dart';
import '../utils/validation.dart';
import 'firebase_command.dart';

class ReplaceCommand {
  final AppLogger _log;

  ReplaceCommand({AppLogger? logger}) : _log = logger ?? AppLogger();

  Future<void> execute() async {
    if (!ConfigService.isValidProject(_log)) return;

    final hasAndroid =
        File(p.join(ConfigService.root, 'android/app/build.gradle'))
                .existsSync() ||
            File(p.join(ConfigService.root, 'android/app/build.gradle.kts'))
                .existsSync();

    final hasIOS = Directory(p.join(ConfigService.root, 'ios/Runner.xcodeproj'))
        .existsSync();

    if (!ConfigService.isInitialized()) {
      _log.error('❌ Error: Project not initialized. Run "init" first.');
      return;
    }

    final flavors = ConfigService.getFlavors();
    if (flavors.isEmpty) {
      _log.error('❌ No flavors found to replace. Run "init" first.');
      return;
    }

    final oldFlavor = _log.chooseOne(
      '👉 Select the flavor you want to rename:',
      choices: flavors,
    );

    // Check if replacing production flavor
    if (oldFlavor == ConfigService.getProductionFlavor()) {
      _log.warn(
          '⚠️ You are about to replace the production flavor ("$oldFlavor").');
      final confirm = _log.confirm('Are you sure you want to continue?');
      if (!confirm) {
        _log.info('Operation cancelled.');
        return;
      }
    }

    // 2. Prompt for new name
    String newFlavor;
    while (true) {
      newFlavor = _log
          .prompt(
            '👉 Enter the new name for "$oldFlavor":',
          )
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

    _log.info('🔄 Renaming flavor "$oldFlavor" to "$newFlavor"...');

    try {
      // 1. Update Config
      final isProduction = oldFlavor == ConfigService.getProductionFlavor();
      ConfigService.renameFlavor(oldFlavor, newFlavor);

      if (isProduction) {
        _log.info('💡 You are replacing the production flavor. Updating production reference...');
        ConfigService.init(productionFlavor: newFlavor);
        _log.info('✔ Production flavor is now: $newFlavor');
      }

      // 2. Update Files
      FileService.renameFlavor(
          oldName: oldFlavor, newName: newFlavor, log: _log);

      // 3. Platform Setup
      _log.info('🛠️ Updating platform configurations...');
      if (hasAndroid) {
        _safe(
            () => AndroidService.setupFlavors(logger: _log), 'Android flavors');
      }
      if (hasIOS) {
        _safe(() => IOSService.setupSchemes(logger: _log), 'iOS setup');
      }

      FileService.updateTests();

      // 4. Final Cleanup
      final orphans =
          FileService.getOrphanedFlavors(ConfigService.getFlavors());
      if (orphans.isNotEmpty) {
        _log.info('🗑️ Cleaning up orphaned files...');
        FileService.cleanupFlavors(orphans.toList());
      }

      IOSService.setupSchemes(logger: _log);
      FileService.updateVSCodeLaunchConfig();

      // Refresh Firebase injection if present
      FileService.injectFirebase(separate: ConfigService.useSeparateMains());

      _log.success(
          '✅ Flavor "$oldFlavor" replaced by "$newFlavor" successfully!');

      // Check and re-initialize Firebase if necessary
      await FirebaseCommand.checkAndReinit(_log, targetFlavor: newFlavor);
    } catch (e) {
      _log.error('❌ Failed to replace flavor: $e');
    }
  }

  void _safe(Function action, String label) {
    try {
      action();
    } catch (e) {
      _log.warn('⚠️ $label encountered an issue: $e');
    }
  }
}
