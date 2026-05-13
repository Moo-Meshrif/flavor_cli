import '../models/flavor_config.dart';
import '../services/gitignore_service.dart';
import '../services/pubspec_service.dart';
import '../utils/logger.dart';

/// Centralises pubspec / .gitignore mutation that was previously duplicated
/// between [SetupRunner] and [MigrateCommand].
class DependencyService {
  static void ensureEnvDependencies(FlavorConfig config, AppLogger log) {
    if (!PubspecService.hasDependency('flutter_dotenv')) {
      PubspecService.addDependency('flutter_dotenv', '^5.1.0');
      log.info('   ✔ Added flutter_dotenv: ^5.1.0 to pubspec.yaml');
    }

    final assetPaths = config.flavors.map((f) => '.env.$f').toList();
    PubspecService.addAssets(assetPaths);
    log.info('   ✔ Added .env asset entries to pubspec.yaml');

    GitignoreService.addEntries(['.env', '.env.*']);
    log.info('   ✔ Added .env and .env.* to .gitignore');
  }
}
