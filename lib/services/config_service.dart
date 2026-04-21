// flavor_cli: modified
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/flavor_config.dart';
import '../models/config_validator.dart';
import '../utils/logger.dart';
import '../utils/type_utils.dart';

class ConfigService {
  static String root = '.';
  static String get _configPath => p.join(root, '.flavor_cli.json');

  // ========================
  // PROJECT VALIDATION
  // ========================
  static bool isValidProject(AppLogger log) {
    if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
      log.error(
          '❌ Error: No pubspec.yaml found. Are you in a Flutter project root?');
      return false;
    }

    final hasAndroid =
        File(p.join(root, 'android/app/build.gradle')).existsSync() ||
            File(p.join(root, 'android/app/build.gradle.kts')).existsSync();
    final hasIOS = Directory(p.join(root, 'ios/Runner.xcodeproj')).existsSync();

    if (!hasAndroid && !hasIOS) {
      log.error(
          '❌ Error: No valid Flutter Android or iOS project structure found.');
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
  static FlavorConfig load() {
    final file = File(_configPath);
    if (!file.existsSync()) {
      throw Exception(
          '❌ flavor_cli: .flavor_cli.json not found. Run init first.');
    }

    try {
      final content = file.readAsStringSync();
      final jsonMap = jsonDecode(content) as Map<String, dynamic>;

      // Will throw FormatException with properly formatted error if invalid
      return ConfigValidator.validate(jsonMap);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('❌ flavor_cli: invalid config JSON format.\n$e');
    }
  }

  /// Loads configuration without strict validation. Useful for migration or partial reads.
  static FlavorConfig? loadLenient() {
    final file = File(_configPath);
    if (!file.existsSync()) return null;

    try {
      final content = file.readAsStringSync();
      final jsonMap = jsonDecode(content) as Map<String, dynamic>;
      return FlavorConfig.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  // ========================
  // SAVE CONFIG
  // ========================
  static void save(FlavorConfig config) {
    final file = File(_configPath);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  // ========================
  // ADD FLAVOR
  // ========================
  static bool addFlavor(String flavor) {
    final config = load();
    final normalized = _normalize(flavor);

    if (!_isValidFlavor(normalized)) {
      throw Exception('❌ Invalid flavor name: "$flavor"');
    }
    if (config.flavors.contains(normalized)) {
      return false; // already exists
    }

    final updatedFlavors = List<String>.from(config.flavors)..add(normalized);

    // Initialize empty values for new flavor to satisfy validator
    final updatedValues =
        Map<String, Map<String, dynamic>>.from(config.flavorValues);
    updatedValues[normalized] = {
      for (final field in config.fields.keys)
        field: TypeUtils.getDefaultTypedValueForType(
            config.fields[field] ?? "String")
    };

    final updatedConfig = config.copyWith(
      flavors: updatedFlavors,
      flavorValues: updatedValues,
    );

    save(updatedConfig);
    return true;
  }

  // ========================
  // REMOVE FLAVOR
  // ========================
  static void removeFlavor(String flavor) {
    if (!isInitialized()) return;
    try {
      final config = load();
      final updatedFlavors = List<String>.from(config.flavors)..remove(flavor);
      final updatedValues =
          Map<String, Map<String, dynamic>>.from(config.flavorValues)
            ..remove(flavor);

      final updatedConfig = config.copyWith(
        flavors: updatedFlavors,
        flavorValues: updatedValues,
      );
      save(updatedConfig);
    } catch (_) {}
  }

  // ========================
  // RENAME FLAVOR
  // ========================
  static void renameFlavor(String oldName, String newName) {
    final config = load();
    final index = config.flavors.indexOf(oldName);

    if (index != -1) {
      final updatedFlavors = List<String>.from(config.flavors);
      updatedFlavors[index] = newName;

      final updatedValues =
          Map<String, Map<String, dynamic>>.from(config.flavorValues);
      final oldValues = updatedValues.remove(oldName);
      if (oldValues != null) {
        updatedValues[newName] = oldValues;
      }

      var updatedConfig = config.copyWith(
        flavors: updatedFlavors,
        flavorValues: updatedValues,
      );

      if (updatedConfig.productionFlavor == oldName) {
        updatedConfig = updatedConfig.copyWith(productionFlavor: newName);
      }

      // Also update Firebase projects map if strategy is unique_id_multi_project
      if (updatedConfig.firebase?.strategy == 'unique_id_multi_project' &&
          updatedConfig.firebase!.projects.containsKey(oldName)) {
        final newProjects =
            Map<String, String>.from(updatedConfig.firebase!.projects);
        final projId = newProjects.remove(oldName)!;
        newProjects[newName] = projId;
        updatedConfig = updatedConfig.copyWith(
            firebase: updatedConfig.firebase!.copyWith(projects: newProjects));
      }

      save(updatedConfig);
    }
  }

  // ========================
  // VALIDATION HELPERS
  // ========================
  static bool _isValidFlavor(String flavor) {
    final regex = RegExp(r'^[a-z0-9_]+$');
    return regex.hasMatch(flavor);
  }

  static String _normalize(String flavor) => flavor.toLowerCase().trim();

  // ========================
  // FIREBASE DETECTION
  // ========================
  static bool hasFirebase() {
    try {
      if (isInitialized()) {
        final config = load();
        if (config.firebase != null) return true;
      }
    } catch (_) {}

    try {
      final pubspec = File(p.join(root, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final content = pubspec.readAsStringSync();
        if (content.contains('firebase_core:')) return true;
      }

      if (File(p.join(root, 'android/app/google-services.json')).existsSync()) {
        return true;
      }
      if (File(p.join(root, 'ios/Runner/GoogleService-Info.plist'))
          .existsSync()) {
        return true;
      }
    } catch (_) {}

    return false;
  }
}
