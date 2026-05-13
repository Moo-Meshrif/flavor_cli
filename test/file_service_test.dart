import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flavor_cli/services/config_service.dart';
import 'package:flavor_cli/services/file_service.dart';
import 'package:flavor_cli/models/flavor_config.dart';
import 'package:flavor_cli/services/runtime_config_service.dart';

void main() {
  late Directory tempDir;

  group('FileService', () {
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('file_test_');
      ConfigService.root = tempDir.path;

      // Create a dummy project structure
      Directory(p.join(ConfigService.root, 'lib/main'))
          .createSync(recursive: true);
      Directory(p.join(ConfigService.root, 'ios/Flutter'))
          .createSync(recursive: true);

      final config = FlavorConfig(
        flavors: ['dev', 'prod'],
        appName: 'TestApp',
        fields: {'baseUrl': 'String'},
        flavorValues: {
          'dev': {'baseUrl': ''},
          'prod': {'baseUrl': ''}
        },
        appConfigPath: 'lib/app_config.dart',
        useSeparateMains: true,
        useSuffix: true,
        android: const AndroidConfig(applicationId: 'com.example'),
        ios: const IosConfig(bundleId: 'com.example'),
        productionFlavor: 'prod',
      );
      ConfigService.save(config);
    });

    tearDown(() {
      ConfigService.root = '.';
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('getOrphanedFlavors detects files not in current config', () {
      File(p.join(ConfigService.root, 'lib/main/main_dev.dart')).createSync();
      File(p.join(ConfigService.root, 'lib/main/main_prod.dart')).createSync();
      File(p.join(ConfigService.root, 'lib/main/main_staging.dart'))
          .createSync();
      File(p.join(ConfigService.root, 'ios/Flutter/old.xcconfig')).createSync();

      final orphans = FileService.getOrphanedFlavors(['dev', 'prod']);

      expect(orphans, containsAll(['staging', 'old']));
      expect(orphans, isNot(contains('dev')));
    });

    test('cleanupFlavors deletes orphaned files', () {
      final mainStaging =
          File(p.join(ConfigService.root, 'lib/main/main_staging.dart'));
      mainStaging.createSync(recursive: true);

      FileService.cleanupFlavors(['staging']);

      expect(mainStaging.existsSync(), isFalse);
    });

    test('integrateMainFiles correctly injects code into main.dart', () {
      final mainFile = File(p.join(ConfigService.root, 'lib/main.dart'));
      mainFile.writeAsStringSync('''
void main() {
  runApp(const MyApp());
}
''');

      final config = ConfigService.load().copyWith(useSeparateMains: false);
      ConfigService.save(config);

      RuntimeConfigService().integrateMainFile(mainFile.path, config);

      final content = mainFile.readAsStringSync();
      expect(content, contains("import 'app_config.dart';"));
      expect(content, contains('AppConfig.init(flavor);'));
      expect(content, contains('await dotenv.load'));
    });

    test('RuntimeConfigService generates valid ENV-based AppConfig', () {
      final config = ConfigService.load();
      RuntimeConfigService().generateAppConfig(config);
      final path = p.join(ConfigService.root, 'lib/app_config.dart');
      final file = File(path);

      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('enum Flavor { dev, prod }'));
      expect(content, contains('static String get baseUrl => dotenv.env[\'BASE_URL\'] ?? \'\';'));
      expect(content, isNot(contains('case Flavor.dev:')));
    });
  });
}
