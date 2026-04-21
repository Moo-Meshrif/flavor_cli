// flavor_cli: modified
import 'package:args/args.dart';
import '../services/config_service.dart';
import '../utils/logger.dart';
import 'init_from_file.dart';
import 'init_wizard.dart';

class InitCommand {
  final AppLogger _log;

  InitCommand({AppLogger? logger}) : _log = logger ?? AppLogger();

  Future<void> execute(List<String> args) async {
    if (!ConfigService.isValidProject(_log)) return;

    final parser = ArgParser()
      ..addOption(
        'from',
        help: 'Path to a JSON config file to initialize without prompts.',
      );

    try {
      final results = parser.parse(args);

      if (results.wasParsed('from')) {
        final filePath = results['from'] as String;
        await InitFromFile(logger: _log).execute(filePath);
      } else {
        await InitWizard(logger: _log).execute();
      }
    } on FormatException catch (e) {
      _log.error('❌ Error parsing arguments: ${e.message}');
    } catch (e) {
      _log.error('❌ Unexpected error: $e');
    }
  }
}
