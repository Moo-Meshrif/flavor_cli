// flavor_cli: modified
import 'package:args/args.dart';
import '../services/config_service.dart';
import '../utils/logger.dart';
import 'init_from_file.dart';
import 'init_wizard.dart';
import '../utils/exceptions.dart';

/// Command to initialize the project with flavor configuration.
class InitCommand {
  final AppLogger _log;

  /// Creates a new [InitCommand] with an optional [logger].
  InitCommand({AppLogger? logger}) : _log = logger ?? AppLogger();

  /// Starts the initialization wizard or loads from a file if the '--from' flag is provided.
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
      if (e is CliException && e.isLogged) {
        // Already reported, just exit gracefully
        return;
      }
      final msg = e is CliException ? '$e' : 'Unexpected error: $e';
      _log.error('❌ $msg');
    }
  }
}
