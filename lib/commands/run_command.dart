import 'dart:io';
import '../services/config_service.dart';
import '../services/runtime_config_service.dart';
import '../utils/logger.dart';

/// Command to run the Flutter application with a specific flavor.
class RunCommand {
  final _log = AppLogger();

  /// Prompts for flavor and build mode if not provided, validates environment,
  /// and runs the application using the Flutter CLI.
  Future<void> execute(List<String> args) async {
    if (!ConfigService.isValidProject(_log)) return;
    if (!ConfigService.requiresInitialized(_log)) return;

    final config = ConfigService.load();
    final flavors = config.flavors;
    String? flavor;

    if (args.isNotEmpty) {
      flavor = args[0].toLowerCase().trim();
      if (!flavors.contains(flavor)) {
        _log.error('❌ flavor_cli: unknown flavor "$flavor"');
        _log.info('   → available flavors: [${flavors.join(", ")}]');
        return;
      }
    }

    flavor ??= _log.chooseOne('👉 Select a flavor to run:', choices: flavors);

    // Try to find build mode in args, otherwise prompt
    String? mode = args
        .map((a) => a.replaceAll('--', '').toLowerCase())
        .where((a) => ['debug', 'release', 'profile'].contains(a))
        .firstOrNull;

    mode ??= _log.chooseOne('👉 Select build mode:',
        choices: ['debug', 'release', 'profile']);

    // Validate ENV file and entry point
    final service = RuntimeConfigService();
    if (!service.validateFlavorReadyToRun(config, flavor, _log)) return;

    _log.info('🚀 Running $flavor ($mode)...');

    final runArgs = ['run', '--$mode', ...service.buildRunArgs(config, flavor)];

    final process = await Process.start(
      'flutter',
      runArgs,
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
    );
    exit(await process.exitCode);
  }
}
