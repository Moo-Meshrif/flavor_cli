import '../runner/setup_runner.dart';
import '../utils/logger.dart';
import '../services/config_service.dart';

class ResetCommand {
  final AppLogger _log;

  ResetCommand({AppLogger? logger}) : _log = logger ?? AppLogger();

  void execute() {
    if (!ConfigService.isValidProject(_log)) return;

    final confirmed = _log.confirm(
      '⚠️ This will remove all flavor configurations and return the project to its original state. Are you sure you want to proceed?',
      defaultValue: false,
    );

    if (!confirmed) {
      _log.info('❌ Reset cancelled.');
      return;
    }

    try {
      SetupRunner(logger: _log).reset(true);
    } catch (e) {
      _log.error('❌ Failed to reset project: $e');
    }
  }
}
