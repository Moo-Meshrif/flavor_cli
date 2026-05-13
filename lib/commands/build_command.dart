import 'dart:io';
import '../services/config_service.dart';
import '../services/runtime_config_service.dart';
import '../utils/logger.dart';

/// Command to build the Flutter application for a specific platform and flavor.
class BuildCommand {
  final _log = AppLogger();

  /// Prompts for build target and flavor if not provided, validates environment,
  /// and builds the application using the Flutter CLI.
  Future<void> execute(List<String> args) async {
    if (!ConfigService.isValidProject(_log)) return;
    if (!ConfigService.requiresInitialized(_log)) return;

    final config = ConfigService.load();
    final flavors = config.flavors;

    // 1. Resolve Target Type
    const validTargets = ['apk', 'appbundle', 'ios', 'ipa'];
    String? targetType = args
        .where((a) => validTargets.contains(a.toLowerCase()))
        .map((a) => a.toLowerCase())
        .firstOrNull;

    targetType ??=
        _log.chooseOne('👉 Select build target:', choices: validTargets);

    // 2. Resolve Flavor
    String? flavor = args
        .where((a) => flavors.contains(a.toLowerCase()))
        .map((a) => a.toLowerCase())
        .firstOrNull;

    if (flavor == null) {
      flavor = _log.chooseOne('👉 Select a flavor to build:', choices: flavors);
    } else if (!flavors.contains(flavor)) {
      _log.error('❌ flavor_cli: unknown flavor "$flavor"');
      _log.info('   → available flavors: [${flavors.join(", ")}]');
      return;
    }

    // 3. Validate ENV file and entry point
    final service = RuntimeConfigService();
    if (!service.validateFlavorReadyToRun(config, flavor, _log)) return;

    _log.info('🏗️ Building $targetType for flavor: $flavor...');

    final processArgs = [
      'build',
      targetType,
      '--release',
      ...service.buildRunArgs(config, flavor),
    ];

    final process = await Process.start(
      'flutter',
      processArgs,
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
    );
    exit(await process.exitCode);
  }
}
