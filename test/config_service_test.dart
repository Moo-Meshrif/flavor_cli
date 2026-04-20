import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flavor_cli/src/services/config_service.dart';

void main() {
  late Directory tempDir;

  group('ConfigService', () {
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('config_test_');
      ConfigService.root = tempDir.path;
    });

    tearDown(() {
      ConfigService.root = '.';
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('init creates config file with default values', () {
      ConfigService.init(
        flavors: ['dev', 'prod'],
        fields: {'baseUrl': 'String'},
        appConfigPath: 'lib/config.dart',
        useSeparateMains: false,
      );

      final configPath = p.join(ConfigService.root, '.flavor_cli.json');
      expect(File(configPath).existsSync(), isTrue);
      final content = jsonDecode(File(configPath).readAsStringSync());
      expect(content['flavors'], equals(['dev', 'prod']));
      expect(content['app_config_path'], equals('lib/config.dart'));
      expect(content['use_separate_mains'], isFalse);
    });

    test('getFlavors returns flavors from config', () {
      final flavors = ['x', 'y'];
      ConfigService.init(flavors: flavors);
      
      expect(ConfigService.getFlavors(), equals(flavors));
    });

    test('addFlavor updates the config', () {
      ConfigService.init(flavors: ['dev']);
      final result = ConfigService.addFlavor('prod');
      
      expect(result, isTrue);
      expect(ConfigService.getFlavors(), containsAll(['dev', 'prod']));
    });

    test('addFlavor fails for duplicate', () {
      ConfigService.init(flavors: ['dev']);
      final result = ConfigService.addFlavor('dev');
      
      expect(result, isFalse);
      expect(ConfigService.getFlavors(), equals(['dev']));
    });

    test('removeFlavor updates the config', () {
      ConfigService.init(flavors: ['dev', 'staging']);
      ConfigService.removeFlavor('staging');
      
      expect(ConfigService.getFlavors(), equals(['dev']));
    });
  });
}
