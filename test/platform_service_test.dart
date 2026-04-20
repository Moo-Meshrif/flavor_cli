import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flavor_cli/src/services/config_service.dart';
import 'package:flavor_cli/src/services/android_service.dart';
import 'package:flavor_cli/src/services/ios_service.dart';

void main() {
  late Directory tempDir;

  group('PlatformServices', () {
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('platform_test_');
      ConfigService.root = tempDir.path;

      Directory(p.join(ConfigService.root, 'android/app'))
          .createSync(recursive: true);
      Directory(p.join(ConfigService.root, 'ios/Runner.xcodeproj'))
          .createSync(recursive: true);
      Directory(p.join(ConfigService.root, 'ios/Runner'))
          .createSync(recursive: true);
      
      File(p.join(ConfigService.root, 'ios/Runner/Info.plist')).writeAsStringSync('<dict></dict>');

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

    test('AndroidService generates dynamic flavors in Groovy', () {
      final buildGradle =
          File(p.join(ConfigService.root, 'android/app/build.gradle'));
      buildGradle.writeAsStringSync('''
android {
    defaultConfig {
        applicationId "com.example.app"
    }
}
''');

      AndroidService.setupFlavors();

      final content = buildGradle.readAsStringSync();
      expect(content, contains('productFlavors {'));
      expect(content, contains('dev {'));
      expect(content, contains('prod {'));
      expect(content, isNot(contains('staging {')));
    });

    test('AndroidService generates dynamic flavors in KTS', () {
      final buildGradle =
          File(p.join(ConfigService.root, 'android/app/build.gradle.kts'));
      buildGradle.writeAsStringSync('''
android {
    defaultConfig {
        applicationId = "com.example.app"
    }
}
''');

      AndroidService.setupFlavors();

      final content = buildGradle.readAsStringSync();
      expect(content, contains('productFlavors {'));
      expect(content, contains('create("dev")'));
      expect(content, contains('create("prod")'));
      expect(content, isNot(contains('create("staging")')));
    });

    test('IOSService prepares project for automation (Zero-XCConfig)', () {
      // Catch all errors from setupSchemes() because we know it will fail 
      // in the Ruby phase due to the minimal sandbox environment.
      try {
        IOSService.setupSchemes();
      } catch (_) {
        // Expected failure in Ruby phase
      }

      // 1. Verify Info.plist update with literal dollar sign
      final plistContent =
          File(p.join(ConfigService.root, 'ios/Runner/Info.plist'))
              .readAsStringSync();
      expect(plistContent, contains('\u0024(APP_NAME)'));
    });

    group('Cleanup logic in Services', () {
      test('AndroidService addFlavor adds a new flavor to existing block', () {
        final buildGradle =
            File(p.join(ConfigService.root, 'android/app/build.gradle'));
        buildGradle.writeAsStringSync('''
android {
    defaultConfig {
        applicationId "com.example.app"
    }
    productFlavors {
        dev {
            dimension "default"
        }
    }
}
''');

        AndroidService.addFlavor('prod');
        final content = buildGradle.readAsStringSync();
        expect(content, contains('productFlavors {'));
        expect(content, contains('dev {'));
        expect(content, contains('prod {'));
      });
    });
  });
}
