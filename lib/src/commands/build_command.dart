import 'dart:io';
import '../services/config_service.dart';
import '../utils/logger.dart';

class BuildCommand {
  final _log = AppLogger();

  Future<void> execute(List<String> args) async {
    if (!ConfigService.isValidProject(_log)) return;

    if (!ConfigService.isInitialized()) {
      _log.error('❌ Error: Project not initialized. Run "init" first.');
      return;
    }

    String? targetType;
    if (args.isNotEmpty) {
      targetType = args[0];
      const validTargets = ['apk', 'appbundle', 'ios', 'ipa'];
      if (!validTargets.contains(targetType)) {
        _log.warn(
            '⚠️ Target "$targetType" is not standard. Valid targets: apk, appbundle, ios, ipa');
      }
    }

    if (targetType == null) {
      targetType = _log.chooseOne('👉 Select build target:',
          choices: ['apk', 'appbundle', 'ios', 'ipa']);
    }

    final flavors = ConfigService.getFlavors();
    String? flavor;

    if (args.length > 1) {
      flavor = args[1];
      if (!flavors.contains(flavor)) {
        _log.warn('⚠️ Flavor "$flavor" not found in configuration.');
        flavor = null;
      }
    }

    if (flavor == null) {
      if (flavors.isEmpty) {
        _log.error(
            '❌ Error: No flavors found in .flavor_cli.json. Please run "init" first.');
        return;
      }
      flavor = _log.chooseOne('👉 Select a flavor to build:', choices: flavors);
    }

    final separate = ConfigService.useSeparateMains();
    final targetPath =
        separate ? 'lib/main/main_$flavor.dart' : 'lib/main.dart';

    if (!File(targetPath).existsSync()) {
      _log.error('❌ Error: Entry file not found: $targetPath');
      return;
    }

    _log.info('🏗️ Building $targetType for flavor: $flavor...');

    final processArgs = [
      'build',
      targetType,
      '--flavor',
      flavor,
      '-t',
      targetPath,
      '--release',
    ];

    if (targetType == 'apk') {
      processArgs.addAll(
          ['--no-tree-shake-icons', '--target-platform', 'android-arm64']);
    }

    final process = await Process.start('flutter', processArgs, mode: ProcessStartMode.inheritStdio);
    exit(await process.exitCode);
  }
}
