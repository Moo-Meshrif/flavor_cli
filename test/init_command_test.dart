import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flavor_cli/src/commands/init_command.dart';
import 'package:flavor_cli/src/services/config_service.dart';
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

    test('Scenario 1: Standard Presets (dev, staging, prod) with Separate Mains', () async {
      final logger = FakeAppLogger(
        choices: [
          'dev, staging, prod',
          'Separate main files per flavor (e.g., main_dev.dart)',
        ],
        prompts: [
          'String baseUrl, bool debug', // variables
          'lib/core/config/app_config.dart', // path
        ],
      );

      InitCommand(logger: logger).execute();

      // Verify Config File
      final configFile = File(p.join(sandbox.path, '.flavor_cli.json'));
      expect(configFile.existsSync(), isTrue);
      expect(configFile.readAsStringSync(), contains('"dev"'));
      expect(configFile.readAsStringSync(), contains('"staging"'));
      expect(configFile.readAsStringSync(), contains('"prod"'));

      // Verify AppConfig
      final appConfigFile = File(p.join(sandbox.path, 'lib/core/config/app_config.dart'));
      expect(appConfigFile.existsSync(), isTrue);
      expect(appConfigFile.readAsStringSync(), contains('class AppConfig'));
      expect(appConfigFile.readAsStringSync(), contains('static late String baseUrl;'));
      expect(appConfigFile.readAsStringSync(), contains('static late bool debug;'));

      // Verify Main Files
      expect(File(p.join(sandbox.path, 'lib/main/main_dev.dart')).existsSync(), isTrue);
      expect(File(p.join(sandbox.path, 'lib/main/main_staging.dart')).existsSync(), isTrue);
      expect(File(p.join(sandbox.path, 'lib/main/main_prod.dart')).existsSync(), isTrue);
      
      // Root main.dart should be removed
      expect(File(p.join(sandbox.path, 'lib/main.dart')).existsSync(), isFalse);

      // Verify Android KTS
      final ktsFile = File(p.join(sandbox.path, 'android/app/build.gradle.kts'));
      final ktsContent = ktsFile.readAsStringSync();
      expect(ktsContent, contains('productFlavors {'));
      expect(ktsContent, contains('create("dev")'));
      expect(ktsContent, contains('create("staging")'));
      expect(ktsContent, contains('create("prod")'));
    });

    test('Scenario 2: Manual Entry & All Data Types with Single Main', () async {
      final logger = FakeAppLogger(
        choices: [
          'Enter manually',
          'Single main file for all flavors',
        ],
        prompts: [
          'alpha, beta', // flavors
          'String api, int port, bool isTest, double scale', // variables
          'lib/env.dart', // path
        ],
      );

      InitCommand(logger: logger).execute();

      // Verify AppConfig
      final appConfigFile = File(p.join(sandbox.path, 'lib/env.dart'));
      expect(appConfigFile.readAsStringSync(), contains('static late String api;'));
      expect(appConfigFile.readAsStringSync(), contains('static late int port;'));
      expect(appConfigFile.readAsStringSync(), contains('static late bool isTest;'));
      expect(appConfigFile.readAsStringSync(), contains('static late double scale;'));

      // Verify Main File Integration
      final mainFile = File(p.join(sandbox.path, 'lib/main.dart'));
      expect(mainFile.existsSync(), isTrue);
      expect(mainFile.readAsStringSync(), contains("import 'env.dart';"));
      expect(mainFile.readAsStringSync(), contains('AppConfig.init(flavor);'));
      expect(mainFile.readAsStringSync(), contains("case 'alpha': return Flavor.alpha;"));
    });

    test('Scenario 3: Multiple Runs Cleans Up Messy build.gradle.kts', () async {
      final ktsFile = File(p.join(sandbox.path, 'android/app/build.gradle.kts'));
      // Create a messy KTS with multiple productFlavors blocks
      await ktsFile.writeAsString('''
android {
    productFlavors {
        create("old") { dimension = "default" }
    }
    productFlavors {
        create("duplicate") { dimension = "default" }
    }
}
''');

      final logger = FakeAppLogger(
        choices: [
          'dev, prod',
          'Single main file for all flavors',
        ],
        prompts: [
          'String url',
          'lib/app_config.dart',
        ],
      );

      InitCommand(logger: logger).execute();

      final content = ktsFile.readAsStringSync();
      
      // Should have only ONE productFlavors block
      final matches = RegExp(r'productFlavors\s*\{').allMatches(content).toList();
      expect(matches.length, equals(1), reason: 'Should have exactly one productFlavors block');
      
      expect(content, contains('create("dev")'));
      expect(content, contains('create("prod")'));
      expect(content, isNot(contains('create("old")')));
    });

    test('Scenario 4: Path Sanitization', () async {
      final logger = FakeAppLogger(
        choices: [
          'dev, prod',
          'Single main file for all flavors',
        ],
        prompts: [
          'String url',
          'lib/core/config/', // Path with trailing slash and no filename
        ],
      );

      InitCommand(logger: logger).execute();

      expect(File(p.join(sandbox.path, 'lib/core/config/app_config.dart')).existsSync(), isTrue);
    });
  });
}
