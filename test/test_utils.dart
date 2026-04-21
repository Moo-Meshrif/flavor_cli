import 'dart:io';
import 'package:flavor_cli/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:flavor_cli/services/config_service.dart';

class FakeAppLogger implements AppLogger {
  final List<String> prompts;
  final List<String> choices;
  int _promptIndex = 0;
  int _choiceIndex = 0;

  final List<String> logs = [];

  FakeAppLogger({
    required this.prompts,
    required this.choices,
  });

  @override
  void info(String message) => logs.add('[INFO] $message');
  @override
  void success(String message) => logs.add('[SUCCESS] $message');
  @override
  void error(String message) => logs.add('[ERROR] $message');
  @override
  void warn(String message) => logs.add('[WARN] $message');

  @override
  String prompt(String message, {String? defaultValue}) {
    logs.add('[PROMPT] $message (default: $defaultValue)');
    if (_promptIndex < prompts.length) {
      return prompts[_promptIndex++];
    }
    return defaultValue ?? '';
  }

  @override
  String chooseOne(String message,
      {required List<String> choices, String? defaultValue}) {
    logs.add('[CHOOSE] $message | Choices: ${choices.join(", ")} (default: $defaultValue)');
    if (_choiceIndex < this.choices.length) {
      return this.choices[_choiceIndex++];
    }
    return defaultValue ?? choices.first;
  }

  @override
  bool confirm(String message, {bool defaultValue = false}) {
    logs.add('[CONFIRM] $message');
    return defaultValue;
  }

  @override
  List<String> chooseAny(String message,
      {required List<String> choices, List<String>? defaultValues}) {
    logs.add('[CHOOSE_ANY] $message | Choices: ${choices.join(", ")}');
    return defaultValues ?? [];
  }
}

Future<Directory> createTestSandbox() async {
  final tempDir = await Directory.systemTemp.createTemp('flavor_test_');
  ConfigService.root = tempDir.path;

  // Create minimal pubspec
  await File(p.join(tempDir.path, 'pubspec.yaml'))
      .writeAsString('name: test_app');

  // Create minimal android structure
  await Directory(p.join(tempDir.path, 'android/app')).create(recursive: true);
  await File(p.join(tempDir.path, 'android/app/build.gradle.kts'))
      .writeAsString('''
plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.test"
    defaultConfig {
        applicationId = "com.example.test"
    }
}
''');

  // Create minimal ios structure
  await Directory(p.join(tempDir.path, 'ios/Runner')).create(recursive: true);
  await Directory(p.join(tempDir.path, 'ios/Flutter')).create(recursive: true);
  await File(p.join(tempDir.path, 'ios/Runner/Info.plist')).writeAsString(
      '<plist><dict><key>CFBundleName</key><string>TestApp</string></dict></plist>');
  await File(p.join(tempDir.path, 'ios/Runner.xcodeproj/project.pbxproj'))
      .create(recursive: true);

  // Create lib/main.dart
  await Directory(p.join(tempDir.path, 'lib')).create(recursive: true);
  await File(p.join(tempDir.path, 'lib/main.dart'))
      .writeAsString('void main() {}');

  return tempDir;
}
