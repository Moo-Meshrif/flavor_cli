import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flavor_cli/src/services/config_service.dart';
import 'package:flavor_cli/src/services/file_service.dart';
import 'package:flavor_cli/src/utils/logger.dart';

void main() {
  late Directory tempDir;

  group('FileService', () {
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('file_test_');
      ConfigService.root = tempDir.path;

      // Create a dummy project structure
      Directory(p.join(ConfigService.root, 'lib/main')).createSync(recursive: true);
      Directory(p.join(ConfigService.root, 'ios/Flutter')).createSync(recursive: true);
      
      ConfigService.init(
        flavors: ['dev', 'prod'],
        fields: {'baseUrl': 'String'},
        appConfigPath: 'lib/app_config.dart',
        useSeparateMains: true,
      );
    });

    tearDown(() {
      ConfigService.root = '.';
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('getOrphanedFlavors detects files not in current config', () {
      // Create valid main files
      File(p.join(ConfigService.root, 'lib/main/main_dev.dart')).createSync();
      File(p.join(ConfigService.root, 'lib/main/main_prod.dart')).createSync();
      
      // Create orphan main file
      File(p.join(ConfigService.root, 'lib/main/main_staging.dart')).createSync();
      
      // Create orphan xcconfig
      File(p.join(ConfigService.root, 'ios/Flutter/old.xcconfig')).createSync();
      
      final orphans = FileService.getOrphanedFlavors(['dev', 'prod']);
      
      expect(orphans, containsAll(['staging', 'old']));
      expect(orphans, isNot(contains('dev')));
      expect(orphans, isNot(contains('prod')));
    });

    test('cleanupFlavors deletes orphaned files and empty directories', () {
      File(p.join(ConfigService.root, 'lib/main/main_staging.dart')).createSync(recursive: true);
      File(p.join(ConfigService.root, 'ios/Flutter/staging.xcconfig')).createSync(recursive: true);
      
      FileService.cleanupFlavors(['staging']);
      
      expect(File(p.join(ConfigService.root, 'lib/main/main_staging.dart')).existsSync(), isFalse);
      expect(File(p.join(ConfigService.root, 'ios/Flutter/staging.xcconfig')).existsSync(), isFalse);
      
      // Verify empty directories are gone
      expect(Directory(p.join(ConfigService.root, 'lib/main')).existsSync(), isFalse);
      expect(Directory(p.join(ConfigService.root, 'ios/Flutter')).existsSync(), isFalse);
    });

    test('integrateMainFiles correctly injects code into main.dart', () {
      final mainFile = File(p.join(ConfigService.root, 'lib/main.dart'));
      mainFile.writeAsStringSync('''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: Scaffold());
}
''');

      ConfigService.init(
        flavors: ['dev', 'prod'],
        useSeparateMains: false,
        appConfigPath: 'lib/app_config.dart',
      );

      final relativeConfigPath = p.relative('lib/app_config.dart', from: 'lib');
      FileService.integrateMainFiles(flavors: ['dev', 'prod'], separate: false);

      final content = mainFile.readAsStringSync();
      print('DEBUG CONTENT:\n$content');
      
      // Check Import
      expect(content, contains("import '$relativeConfigPath';"));
      
      // Check AppConfig.init call
      expect(content, contains('AppConfig.init(flavor);'));
      expect(content, contains("String.fromEnvironment('FLAVOR')"));
      
      // Check _getFlavor helper
      expect(content, contains('Flavor _getFlavor(String flavor)'));
      expect(content, contains("case 'dev': return Flavor.dev;"));
      expect(content, contains("case 'prod': return Flavor.prod;"));
    });

    test('integrateMainFiles refreshes _getFlavor switch on subsequent runs', () {
      final mainFile = File(p.join(ConfigService.root, 'lib/main.dart'));
      mainFile.writeAsStringSync('''
import 'app_config.dart';
import 'package:flutter/material.dart';

void main() {
  const flavorString = String.fromEnvironment('FLAVOR');
  final flavor = _getFlavor(flavorString);
  AppConfig.init(flavor);
  runApp(const MyApp());
}

Flavor _getFlavor(String flavor) {
  switch (flavor) {
    case 'dev': return Flavor.dev;
    default: return Flavor.dev;
  }
}
''');

      // Update config with NEW flavor: prod
      ConfigService.init(
        flavors: ['dev', 'prod'],
        useSeparateMains: false,
        appConfigPath: 'lib/app_config.dart',
      );

      FileService.integrateMainFiles(flavors: ['dev', 'prod'], separate: false);

      final content = mainFile.readAsStringSync();
      
      // Verify that 'prod' case was added
      expect(content, contains("case 'prod': return Flavor.prod;"));
    });

    test('integrateMainFiles avoids extra braces by correctly matching nested structures', () {
      final mainFile = File(p.join(ConfigService.root, 'lib/main.dart'));
      mainFile.writeAsStringSync('''
import 'app_config.dart';
void main() {
  _getFlavor('dev');
}

Flavor _getFlavor(String flavor) {
  switch (flavor) {
    case 'dev': return Flavor.dev;
    default: return Flavor.dev;
  }
}
''');

      ConfigService.init(
        flavors: ['dev', 'prod'],
        useSeparateMains: false,
        appConfigPath: 'lib/app_config.dart',
      );

      FileService.integrateMainFiles(flavors: ['dev', 'prod'], separate: false);

      final content = mainFile.readAsStringSync();
      
      final braceMatches = RegExp(r'}').allMatches(content).toList();
      final braceCount = braceMatches.length;

      // exactly 3: one for main(), one for switch {}, one for _getFlavor {}
      expect(braceCount, equals(3), reason: 'Should have exactly 3 closing braces');
      
      // The bug would leave 3 braces at the end (tripleNested)
      expect(content, isNot(contains('}\n}\n}')), reason: 'Should not have triple nested braces');
    });
    test('integrateMainFiles correctly handles async main.dart', () {
      final mainFile = File(p.join(ConfigService.root, 'lib/main.dart'));
      mainFile.writeAsStringSync('''
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: Scaffold());
}
''');

      ConfigService.init(
        flavors: ['dev', 'prod'],
        useSeparateMains: false,
        appConfigPath: 'lib/app_config.dart',
      );

      FileService.integrateMainFiles(flavors: ['dev', 'prod'], separate: false);

      final content = mainFile.readAsStringSync();
      
      // Check AppConfig.init call is present
      expect(content, contains('AppConfig.init(flavor);'));
      // Check async is preserved
      expect(content, contains('void main() async {'));
      // Check existing content is preserved
      expect(content, contains('WidgetsFlutterBinding.ensureInitialized();'));
    });

    test('addFlavorToAppConfig preserves existing comments and custom values', () {
      FileService.createAppConfig();
      final path = p.join(ConfigService.root, 'lib/app_config.dart');
      final file = File(path);

      file.writeAsStringSync('''
enum Flavor { dev, prod }

class AppConfig {
  static late Flavor flavor;
  static late String baseUrl;

  static void init(Flavor f) {
    flavor = f;
    // TODO: Fill in your flavor values here
    switch (f) {
      case Flavor.dev:
        baseUrl = 'https://dev.api.com'; // My custom comment
        break;
      case Flavor.prod:
        baseUrl = 'https://prod.api.com';
        break;
    }
  }
}
''');

      FileService.addFlavorToAppConfig('staging');

      final content = file.readAsStringSync();
      
      // Verify staging was added to enum
      expect(content, contains('dev, prod, staging'));
      
      // Verify existing comment and value are preserved
      expect(content, contains("baseUrl = 'https://dev.api.com'; // My custom comment"));
      
      // Verify new case was added
      expect(content, contains('case Flavor.staging:'));
      expect(content, contains('baseUrl = \'FILL_ME\';'));
    });

    test('removeFlavorFromAppConfig preserves remaining cases and comments', () {
      final path = p.join(ConfigService.root, 'lib/app_config.dart');
      final file = File(path);

      file.writeAsStringSync('''
enum Flavor { dev, prod, staging }

class AppConfig {
  static late Flavor flavor;
  static late String baseUrl;

  static void init(Flavor f) {
    flavor = f;
    switch (f) {
      case Flavor.dev:
        baseUrl = 'https://dev.api.com'; // Keep this
        break;
      case Flavor.staging:
        baseUrl = 'https://staging.api.com'; // Delete this
        break;
      case Flavor.prod:
        baseUrl = 'https://prod.api.com';
        break;
    }
  }
}
''');

      FileService.removeFlavorFromAppConfig('staging');

      final content = file.readAsStringSync();
      
      // Verify staging was removed from enum
      expect(content, isNot(contains('staging')));
      expect(content, contains('dev, prod'));
      
      // Verify existing dev case and comment are preserved
      expect(content, contains("baseUrl = 'https://dev.api.com'; // Keep this"));
      
      // Verify staging case is gone
      expect(content, isNot(contains('case Flavor.staging:')));
      expect(content, isNot(contains('https://staging.api.com')));
      
      // Verify prod case is still there
      expect(content, contains('case Flavor.prod:'));
    });

    test('renameFlavor correctly updates user-provided AppConfig content', () {
      final path = p.join(ConfigService.root, 'lib/app_config.dart');
      final file = File(path);

      file.writeAsStringSync('''
enum Flavor { dev, prod, stg }

class AppConfig {
  static late Flavor flavor;
  static late String baseUrl;
  static late bool debug;

  static void init(Flavor f) {
    flavor = f;
    // TODO: Fill in your flavor values here
    switch (f) {
      case Flavor.dev:
        baseUrl = 'svdnvljksdkvksdvsd';
        debug = false;
        break;
      case Flavor.prod:
        baseUrl = 'FILLjvsdlvkjsdlkjv_ME';
        debug = false;
        break;

      case Flavor.stg:
        baseUrl = 'lkkmskdvk;lsmdkf.n';
        debug = false;
        break;
    }
  }
}
''');

      FileService.renameFlavor(
        oldName: 'prod',
        newName: 'prodaction',
        log: AppLogger(),
      );

      final content = file.readAsStringSync();
      
      // Verify Enum update
      expect(content, contains('dev, prodaction, stg'));
      
      // Verify Switch update
      expect(content, contains('case Flavor.prodaction:'));
    });
  });
}
