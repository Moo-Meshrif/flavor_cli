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

    final flavors = ConfigService.getFlavors();
    String? flavor;

    if (args.isNotEmpty) {
      flavor = args[0];
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
      flavor = _log.chooseOne('👉 Select a flavor to run:', choices: flavors);
    }

    final mode = _log.chooseOne('👉 Select build mode:',
        choices: ['debug', 'release', 'profile']);

    final separate = ConfigService.useSeparateMains();
    final target = separate ? 'lib/main/main_$flavor.dart' : 'lib/main.dart';

    if (!File(target).existsSync()) {
      _log.error('❌ Error: Main file not found for flavor "$flavor": $target');
      return;
    }

    _log.info('🚀 Running flavor: $flavor ($mode)...');

    final runArgs = ['run', '--flavor', flavor, '-t', target, '--$mode'];
    if (!separate) {
      runArgs.add('--dart-define=FLAVOR=$flavor');
    }

    final process = await Process.start('flutter', runArgs, mode: ProcessStartMode.inheritStdio);
    exit(await process.exitCode);
  }
}
