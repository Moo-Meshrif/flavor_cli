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

    final config = ConfigService.load();
    final flavors = config.flavors;

    // 1. Resolve Target Type
    String? targetType;
    const validTargets = ['apk', 'appbundle', 'ios', 'ipa'];
    for (final arg in args) {
      if (validTargets.contains(arg.toLowerCase())) {
        targetType = arg.toLowerCase();
        break;
      }
    }

    if (targetType == null) {
      targetType = _log.chooseOne('👉 Select build target:',
          choices: validTargets);
    }

    // 2. Resolve Flavor
    String? flavor;
    for (final arg in args) {
      if (flavors.contains(arg.toLowerCase())) {
        flavor = arg.toLowerCase();
        break;
      }
    }

    if (flavor == null) {
      flavor = _log.chooseOne('👉 Select a flavor to build:', choices: flavors);
    } else {
       // Validate explicitly if it was passed
       if (!flavors.contains(flavor)) {
         _log.error('❌ flavor_cli: unknown flavor "$flavor"');
         _log.info('   → available flavors: [${flavors.join(", ")}]');
         return;
       }
    }

    final separate = config.useSeparateMains;
    final targetPath =
        separate ? 'lib/main/main_$flavor.dart' : 'lib/main.dart';

    if (!File(targetPath).existsSync()) {
      _log.error('❌ Error: Entry point not found: $targetPath');
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
      '--dart-define=FLAVOR=$flavor',
    ];

    // Add custom fields
    final values = config.flavorValues[flavor] ?? {};
    for (final entry in values.entries) {
      if (entry.value.isNotEmpty) {
        processArgs.add('--dart-define=${entry.key}=${entry.value}');
      }
    }

    final process = await Process.start(
      'flutter', 
      processArgs, 
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
    );
    exit(await process.exitCode);
  }
}
