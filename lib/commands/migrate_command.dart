import '../services/config_service.dart';
import '../utils/logger.dart';
import '../utils/type_utils.dart';

class MigrateCommand {
  final AppLogger _log;

  MigrateCommand({AppLogger? logger}) : _log = logger ?? AppLogger();

  Future<void> execute() async {
    _log.info('🔄 Starting migration to the latest configuration format...');

    final oldConfig = ConfigService.loadLenient();
    if (oldConfig == null) {
      _log.error('❌ Error: Could not find or parse .flavor_cli.json.');
      return;
    }

    final fields = oldConfig.fields;
    final flavors = oldConfig.flavors;
    final flavorValues =
        Map<String, Map<String, dynamic>>.from(oldConfig.flavorValues);

    if (fields.isEmpty) {
      _log.info('✨ No fields defined. Migration is just a format update.');
    } else {
      _log.info('\n📝 Migrating per-flavor field values:');

      for (final fieldName in fields.keys) {
        final type = fields[fieldName]!;
        _log.info('Variable: $fieldName ($type)');
        for (final flavor in flavors) {
          // If value already exists, skip
          if (flavorValues.containsKey(flavor) &&
              flavorValues[flavor]!.containsKey(fieldName)) {
            continue;
          }

          final defaultValue = TypeUtils.getDefaultValueForType(type);
          final input = _log
              .prompt(
                '   → Enter value for $fieldName ($flavor):',
                defaultValue: defaultValue,
              )
              .trim();

          final typedVal = TypeUtils.parseToType(type, input);
          flavorValues.putIfAbsent(flavor, () => {})[fieldName] = typedVal;
        }
      }
    }

    final newConfig = oldConfig.copyWith(flavorValues: flavorValues);
    ConfigService.save(newConfig);

    _log.success('✅ .flavor_cli.json has been migrated to the latest version!');
    _log.info(
        '\n💡 Tip: Run "dart run flavor_cli init --from .flavor_cli.json" now to synchronize your project with the new configuration.');
  }
}
