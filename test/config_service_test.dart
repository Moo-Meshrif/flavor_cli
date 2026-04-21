import 'dart:io';
import 'package:test/test.dart';
import 'package:flavor_cli/services/config_service.dart';
import 'package:flavor_cli/models/flavor_config.dart';

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

    test('save and load config correctly', () {
      final config = FlavorConfig(
        flavors: ['dev', 'prod'],
        appName: 'TestApp',
        fields: {'baseUrl': 'String'},
        flavorValues: {
          'dev': {'baseUrl': 'dev.api.com'},
          'prod': {'baseUrl': 'api.com'},
        },
        appConfigPath: 'lib/config.dart',
        useSeparateMains: false,
        useSuffix: true,
        android: const AndroidConfig(applicationId: 'com.example.test'),
        ios: const IosConfig(bundleId: 'com.example.test'),
        productionFlavor: 'prod',
      );

      ConfigService.save(config);

      final loaded = ConfigService.load();
      expect(loaded.flavors, equals(['dev', 'prod']));
      expect(loaded.appName, equals('TestApp'));
      expect(loaded.flavorValues['dev']?['baseUrl'], equals('dev.api.com'));
      expect(loaded.appConfigPath, equals('lib/config.dart'));
    });

    test('addFlavor updates config and values', () {
      final config = FlavorConfig(
        flavors: ['dev'],
        appName: 'TestApp',
        fields: {'apiKey': 'String'},
        flavorValues: {
          'dev': {'apiKey': '123'}
        },
        appConfigPath: 'lib/config.dart',
        useSeparateMains: false,
        useSuffix: true,
        android: const AndroidConfig(applicationId: 'com.example.test'),
        ios: const IosConfig(bundleId: 'com.example.test'),
        productionFlavor: 'dev',
      );
      ConfigService.save(config);

      final result = ConfigService.addFlavor('prod');
      expect(result, isTrue);

      final updated = ConfigService.load();
      expect(updated.flavors, containsAll(['dev', 'prod']));
      expect(updated.flavorValues.containsKey('prod'), isTrue);
      expect(
          updated.flavorValues['prod']?['apiKey'], equals('')); // Default empty
    });

    test('removeFlavor updates config', () {
      final config = FlavorConfig(
        flavors: ['dev', 'stage'],
        appName: 'TestApp',
        fields: {},
        flavorValues: {'dev': {}, 'stage': {}},
        appConfigPath: 'lib/config.dart',
        useSeparateMains: false,
        useSuffix: true,
        android: const AndroidConfig(applicationId: 'a'),
        ios: const IosConfig(bundleId: 'a'),
        productionFlavor: 'dev',
      );
      ConfigService.save(config);

      ConfigService.removeFlavor('stage');

      final updated = ConfigService.load();
      expect(updated.flavors, equals(['dev']));
      expect(updated.flavorValues.containsKey('stage'), isFalse);
    });

    test('renameFlavor updates config and values', () {
      final config = FlavorConfig(
        flavors: ['dev', 'old'],
        appName: 'TestApp',
        fields: {'key': 'String'},
        flavorValues: {
          'dev': {'key': 'd'},
          'old': {'key': 'o'},
        },
        appConfigPath: 'lib/config.dart',
        useSeparateMains: false,
        useSuffix: true,
        android: const AndroidConfig(applicationId: 'a'),
        ios: const IosConfig(bundleId: 'a'),
        productionFlavor: 'old',
      );
      ConfigService.save(config);

      ConfigService.renameFlavor('old', 'new');

      final updated = ConfigService.load();
      expect(updated.flavors, equals(['dev', 'new']));
      expect(updated.flavorValues.containsKey('new'), isTrue);
      expect(updated.flavorValues['new']?['key'], equals('o'));
      expect(updated.productionFlavor, equals('new'));
    });
  });
}
