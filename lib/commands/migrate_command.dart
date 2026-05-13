import 'dart:io';
import 'package:path/path.dart' as p;
import '../services/config_service.dart';
import '../services/runtime_config_service.dart';
import '../services/dependency_service.dart';
import '../utils/logger.dart';

class MigrateCommand {
  final _log = AppLogger();

  Future<void> execute() async {
    _log.info('🔄 Starting migration to the latest configuration format...');

    if (!ConfigService.isInitialized()) {
      _log.error('❌ Error: Project not initialized. Run "init" first.');
      return;
    }

    final config = ConfigService.loadLenient();
    if (config == null) {
      _log.error(
          '❌ Error: Could not find or parse flavor_cli.yaml (or legacy .flavor_cli.json).');
      return;
    }

    // 1. Sync values to .env files if they still exist in the config object
    final runtimeService = RuntimeConfigService();
    if (config.flavorValues.isNotEmpty) {
      _log.info('\n📝 Migrating per-flavor field values to .env files:');

      for (final flavor in config.flavors) {
        final values = config.flavorValues[flavor];
        if (values != null && values.isNotEmpty) {
          _log.info('   → flavor: $flavor');
          runtimeService.updateEnvFile(flavor, values);
        }
      }
    }

    // 2. Generate AppConfig.dart and integrate main files
    _log.info('\n🚀 Updating app entry points and configuration...');
    runtimeService.generateAppConfig(config);

    if (config.useSeparateMains) {
      for (final flavor in config.flavors) {
        final path = p.join(ConfigService.root, 'lib/main/main_$flavor.dart');
        runtimeService.integrateMainFile(path, config, flavor: flavor);
      }
    } else {
      runtimeService.integrateMainFile(
          p.join(ConfigService.root, 'lib/main.dart'), config);
    }

    // 3. Save config (this will automatically remove 'values' from the YAML/JSON output)
    ConfigService.save(config);

    // 4. Ensure dependencies and assets are configured in pubspec.yaml
    DependencyService.ensureEnvDependencies(config, _log);

    // 5. Delete legacy JSON if it exists
    final legacyFile = File(p.join(ConfigService.root, '.flavor_cli.json'));
    if (legacyFile.existsSync()) {
      legacyFile.deleteSync();
      _log.info('🗑️ Deleted legacy .flavor_cli.json');
    }

    _log.info('\n✅ flavor_cli.yaml has been migrated to the latest version!');
    _log.info(
        '💡 Tip: Run "dart run flavor_cli init --from flavor_cli.yaml" now to synchronize your project with the new configuration.');
  }
}
