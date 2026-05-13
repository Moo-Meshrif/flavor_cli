// flavor_cli: added
import 'dart:io';
import 'package:yaml/yaml.dart';
import '../models/config_validator.dart';
import '../runner/setup_runner.dart';
import '../utils/logger.dart';
import '../utils/yaml_utils.dart';
import '../utils/exceptions.dart';

class InitFromFile {
  final AppLogger _log;

  InitFromFile({AppLogger? logger}) : _log = logger ?? AppLogger();

  Future<void> execute(String filePath) async {
    final file = File(filePath);

    if (!file.existsSync()) {
      _log.error('❌ Error: Config file "$filePath" not found.');
      return;
    }

    try {
      final content = await file.readAsString();
      final yamlMap = loadYaml(content);
      final jsonMap = YamlUtils.yamlToMap(yamlMap);

      // Validate schema and required fields perfectly
      final config = ConfigValidator.validate(jsonMap);

      // Run the unified setup runner
      await SetupRunner(logger: _log).run(config);
    } on FormatException catch (e) {
      // ConfigValidator throws FormatException with the exact error details
      _log.error(e.message);
    } catch (e) {
      if (e is CliException && e.isLogged) return;
      _log.error('❌ Error: Failed to parse "$filePath" as YAML.\n$e');
    }
  }
}
