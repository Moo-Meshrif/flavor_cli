import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';

class ConfigService {
  static String root = '.';
  static String get _configPath => p.join(root, '.flavor_cli.json');

  // ========================
  // PROJECT VALIDATION
  // ========================
  static bool isValidProject(AppLogger log) {
    // 1. Check for pubspec.yaml
    if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
      log.error(
          '❌ Error: No pubspec.yaml found. Are you in a Flutter project root?');
      return false;
    }

    // 2. Check for Android/iOS platform structure
    final hasAndroid =
        File(p.join(root, 'android/app/build.gradle')).existsSync() ||
            File(p.join(root, 'android/app/build.gradle.kts')).existsSync();

    final hasIOS = Directory(p.join(root, 'ios/Runner.xcodeproj')).existsSync();

    if (!hasAndroid && !hasIOS) {
      log.error(
          '❌ Error: No valid Flutter Android or iOS project structure found.');
      log.error(
          'Expected to find "android/app/build.gradle" or "ios/Runner.xcodeproj".');
      return false;
    }

    return true;
  }

  // ========================
  // IS INITIALIZED
  // ========================
  static bool isInitialized() {
    return File(_configPath).existsSync();
  }

  // ========================
  // LOAD CONFIG
  // ========================
  static Map<String, dynamic> load() {
    final file = File(_configPath);

    if (!file.existsSync()) {
      return _defaultConfig();
    }

    try {
      final content = file.readAsStringSync();
      return jsonDecode(content);
    } catch (_) {
      return _defaultConfig();
    }
  }

  // ========================
  // SAVE CONFIG
  // ========================
  static void save(Map<String, dynamic> config) {
    final file = File(_configPath);

    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  // ========================
  // INIT CONFIG
  // ========================
  static void init({
    List<String>? flavors,
    Map<String, String>? fields,
    String? appConfigPath,
    bool? useSeparateMains,
    String? appName,
    String? productionFlavor,
    bool? useSuffix,
    String? packageId,
  }) {
    final file = File(_configPath);
    final config = file.existsSync() ? load() : _defaultConfig();

    if (flavors != null) config['flavors'] = flavors;
    if (fields != null) config['fields'] = fields;
    if (appConfigPath != null) config['app_config_path'] = appConfigPath;
    if (useSeparateMains != null) {
      config['use_separate_mains'] = useSeparateMains;
    }
    if (appName != null) config['app_name'] = appName;
    if (productionFlavor != null)
      config['production_flavor'] = productionFlavor;
    if (useSuffix != null) config['use_suffix'] = useSuffix;

    if (packageId != null) {
      config['android'] ??= {};
      config['android']['application_id'] = packageId;
      config['ios'] ??= {};
      config['ios']['bundle_id'] = packageId;
    }

    save(config);
  }

  // ========================
  // GET FLAVORS
  // ========================
  static List<String> getFlavors() {
    final config = load();
    return List<String>.from(config['flavors'] ?? []);
  }

  // ========================
  // GET FIELDS
  // ========================
  static Map<String, String> getFields() {
    final config = load();
    return Map<String, String>.from(config['fields'] ?? {'baseUrl': 'String'});
  }

  // ========================
  // GET APP NAME
  // ========================
  static String getAppName() {
    final config = load();
    return config['app_name'] ?? 'MyApp';
  }

  // ========================
  // GET PRODUCTION FLAVOR
  // ========================
  static String getProductionFlavor() {
    final config = load();
    if (config['production_flavor'] != null) {
      return config['production_flavor'];
    }

    // Fallback search
    final flavors = getFlavors();
    if (flavors.contains('prod')) return 'prod';
    if (flavors.contains('production')) return 'production';

    // Last resort: first flavor
    return flavors.isNotEmpty ? flavors.first : 'prod';
  }

  // ========================
  // GET CONFIG PATH
  // ========================
  static String getAppConfigPath() {
    final config = load();
    return config['app_config_path'] ?? 'lib/core/config/app_config.dart';
  }

  // ========================
  // GET MAIN STRATEGY
  // ========================
  static bool useSeparateMains() {
    final config = load();
    return config['use_separate_mains'] ?? true;
  }

  // ========================
  // GET SUFFIX STRATEGY
  // ========================
  static bool useSuffix() {
    final config = load();
    return config['use_suffix'] ?? true;
  }

  // ========================
  // ADD FLAVOR
  // ========================
  static bool addFlavor(String flavor) {
    final config = load();
    final flavors = List<String>.from(config['flavors'] ?? []);

    final normalized = _normalize(flavor);

    if (!_isValidFlavor(normalized)) {
      throw Exception('❌ Invalid flavor name: "$flavor"');
    }

    if (flavors.contains(normalized)) {
      return false; // already exists
    }

    flavors.add(normalized);
    config['flavors'] = flavors;

    save(config);
    return true;
  }

  // ========================
  // REMOVE FLAVOR (optional)
  // ========================
  static void removeFlavor(String flavor) {
    final config = load();
    final flavors = List<String>.from(config['flavors'] ?? []);

    flavors.remove(flavor);

    config['flavors'] = flavors;
    save(config);
  }

  // ========================
  // RENAME FLAVOR
  // ========================
  static void renameFlavor(String oldName, String newName) {
    final config = load();
    final flavors = List<String>.from(config['flavors'] ?? []);

    final index = flavors.indexOf(oldName);
    if (index != -1) {
      flavors[index] = newName;
      config['flavors'] = flavors;

      // Update production_flavor if it matches
      if (config['production_flavor'] == oldName) {
        config['production_flavor'] = newName;
      }

      save(config);
    }
  }

  // ========================
  // DEFAULT CONFIG
  // ========================
  static Map<String, dynamic> _defaultConfig() {
    return {
      'flavors': [],
      'app_name': 'MyApp',
      'fields': {
        'baseUrl': 'String',
      },
      'app_config_path': 'lib/core/config/app_config.dart',
      'use_separate_mains': true,
      'use_suffix': true,
      'android': {
        'application_id': 'com.example.app',
      },
      'ios': {
        'bundle_id': 'com.example.app',
      },
    };
  }

  // ========================
  // VALIDATION
  // ========================
  static bool _isValidFlavor(String flavor) {
    final regex = RegExp(r'^[a-z0-9_]+$');
    return regex.hasMatch(flavor);
  }

  static String _normalize(String flavor) {
    return flavor.toLowerCase().trim();
  }
}
