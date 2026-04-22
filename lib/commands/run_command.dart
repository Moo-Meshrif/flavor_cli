import 'dart:io';
import '../services/config_service.dart';
import '../utils/logger.dart';

class RunCommand {
  final _log = AppLogger();

  Future<void> execute(List<String> args) async {
    if (!ConfigService.isValidProject(_log)) return;

    if (!ConfigService.isInitialized()) {
      _log.error('❌ Error: Project not initialized. Run "init" first.');
      return;
    }

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

    if (flavor == null) {
      flavor = _log.chooseOne('👉 Select a flavor to run:', choices: flavors);
    }

    // Try to find build mode in args, otherwise prompt
    String? mode;
    for (final arg in args) {
      final clean = arg.replaceAll('--', '').toLowerCase();
      if (['debug', 'release', 'profile'].contains(clean)) {
        mode = clean;
        break;
      }
    }
    
    mode ??= _log.chooseOne('👉 Select build mode:',
        choices: ['debug', 'release', 'profile']);

    final separate = config.useSeparateMains;
    final target = separate ? 'lib/main/main_$flavor.dart' : 'lib/main.dart';

    if (!File(target).existsSync()) {
      _log.error('❌ Error: Entry point not found: $target');
      return;
    }

    _log.info('🚀 Running $flavor ($mode)...');

    // Build arguments
    final runArgs = [
      'run',
      '--flavor',
      flavor,
      '-t',
      target,
      '--$mode',
      '--dart-define=FLAVOR=$flavor',
    ];

    // Add custom fields as dart-defines
    final values = config.flavorValues[flavor] ?? {};
    for (final entry in values.entries) {
      final value = entry.value;
      if (value is! String || value.isNotEmpty) {
        runArgs.add('--dart-define=${entry.key}=$value');
      }
    }

    final process = await Process.start(
      'flutter', 
      runArgs, 
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
    );
    exit(await process.exitCode);
  }
}
