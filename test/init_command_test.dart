import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flavor_cli/commands/init_command.dart';
import 'package:flavor_cli/services/config_service.dart';
import 'test_utils.dart';

void main() {
  group('InitCommand Integration Tests', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await createTestSandbox();
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
      ConfigService.root = '.';
    });

    test('Full Wizard Flow', () async {
      final logger = FakeAppLogger(
        choices: [
          'dev, prod', // Flavors
          'Separate main files per flavor (e.g., main_dev.dart)', // Strategy
          'Unique IDs per flavor (recommended) — appends .flavorName to non-production flavors', // ID Strategy
        ],
        prompts: [
          'String baseUrl', // variables
          'lib/core/config/app_config.dart', // path
          'TestApp', // App Name
          'com.example.test', // Production Package ID
          'dev-url', // Value for baseUrl (dev)
          'prod-url', // Value for baseUrl (prod)
        ],
      );

      final cmd = InitCommand(logger: logger);
      await cmd.execute([]);

      // Verify Config File
      final configFile = File(p.join(sandbox.path, 'flavor_cli.yaml'));
      expect(configFile.existsSync(), isTrue);

      final config = ConfigService.load();
      expect(config.flavors, equals(['dev', 'prod']));
      expect(config.appName, equals('TestApp'));
      // Values are no longer persisted in yaml, so we check .env files
      final envFile = File(p.join(sandbox.path, '.env.dev'));
      expect(envFile.existsSync(), isTrue);
      expect(envFile.readAsStringSync(), contains('BASE_URL=dev-url'));

      // Verify AppConfig
      final appConfigFile =
          File(p.join(sandbox.path, 'lib/core/config/app_config.dart'));
      expect(appConfigFile.existsSync(), isTrue);
      expect(appConfigFile.readAsStringSync(),
          contains('static String get baseUrl => dotenv.env[\'BASE_URL\'] ?? \'\';'));

      // Verify Main Files
      expect(File(p.join(sandbox.path, 'lib/main/main_dev.dart')).existsSync(),
          isTrue);
      expect(File(p.join(sandbox.path, 'lib/main/main_prod.dart')).existsSync(),
          isTrue);
    });

    test('Init from file', () async {
      final configFile = File(p.join(sandbox.path, 'flavor_cli.yaml'));
      await configFile.writeAsString('''
flavors:
  - dev
  - prod
app_name: TestApp
fields:
  api: String
values:
  dev:
    api: dev
  prod:
    api: prod
app_config_path: lib/app_config.dart
use_separate_mains: false
use_suffix: true
android:
  application_id: com.ex
ios:
  bundle_id: com.ex
production_flavor: prod
''');

      final logger = FakeAppLogger(prompts: [], choices: []);
      final cmd = InitCommand(logger: logger);
      await cmd.execute(
          ['--from', configFile.path]); // Use flag to trigger InitFromFile

      final appConfigFile = File(p.join(sandbox.path, 'lib/app_config.dart'));
      expect(appConfigFile.existsSync(), isTrue);
      expect(appConfigFile.readAsStringSync(),
          contains('static String get api => dotenv.env[\'API\'] ?? \'\';'));
    });
  });
}
