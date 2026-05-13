import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import '../models/flavor_config.dart';
import '../models/config_validator.dart';
import '../utils/logger.dart';
import '../utils/type_utils.dart';
import '../utils/yaml_utils.dart';

/// Service for managing the flavor_cli configuration file (YAML).
class ConfigService {
  /// The root directory of the project.
  static String root = '.';
  static String get _configPath => p.join(root, 'flavor_cli.yaml');

  /// Returns true if the current directory is a valid Flutter project root.
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
  /// Returns true if the project has been initialized with flavor_cli.
  static bool isInitialized() {
    return File(_configPath).existsSync() ||
        File(p.join(root, '.flavor_cli.json')).existsSync();
  }

  /// Returns false and logs an error if not initialized. Use in commands to
  /// avoid duplicating the "Run init first" message.
  static bool requiresInitialized(AppLogger log) {
    if (!isInitialized()) {
      log.error('❌ Error: Project not initialized. Run "init" first.');
      return false;
    }
    return true;
  }

  // ========================
  // LOAD CONFIG
  // ========================
  /// Loads the flavor configuration from the YAML file.
  /// If [excludeValidation] is true, the config is loaded without full validation.
  static FlavorConfig load([bool excludeValidation = false]) {
    // Check for legacy JSON first for seamless loading before migration
    final legacyFile = File(p.join(root, '.flavor_cli.json'));
    if (legacyFile.existsSync() && !File(_configPath).existsSync()) {
      try {
        final content = legacyFile.readAsStringSync();
        final jsonMap = jsonDecode(content) as Map<String, dynamic>;
        if (excludeValidation) return FlavorConfig.fromJson(jsonMap);
        return ConfigValidator.validate(jsonMap);
      } catch (e) {
        // Fallthrough to yaml error
      }
    }

    final file = File(_configPath);
    if (!file.existsSync()) {
      throw Exception(
          '❌ flavor_cli: flavor_cli.yaml not found. Run init first.');
    }

    try {
      final content = file.readAsStringSync();
      final yamlMap = loadYaml(content);
      final jsonMap = YamlUtils.yamlToMap(yamlMap);

      if (excludeValidation) {
        return FlavorConfig.fromJson(jsonMap);
      }

      // Will throw FormatException with properly formatted error if invalid
      try {
        return ConfigValidator.validate(jsonMap);
      } on FormatException catch (e) {
        // Self-healing: If the ONLY issue is the production_flavor, and we have flavors, fix it.
        if (e.message.contains('production_flavor') &&
            !e.message.contains('application_id') &&
            !e.message.contains('bundle_id')) {
          final config = FlavorConfig.fromJson(jsonMap);
          if (config.flavors.isNotEmpty &&
              !config.flavors.contains(config.productionFlavor)) {
            final repaired =
                config.copyWith(productionFlavor: config.flavors.first);
            save(repaired);
            return repaired;
          }
        }
        rethrow;
      }
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('❌ flavor_cli: invalid config YAML format.\n$e');
    }
  }

  /// Loads configuration without strict validation. Useful for migration or partial reads.
  static FlavorConfig? loadLenient() {
    final file = File(_configPath);
    if (!file.existsSync()) {
      final legacyFile = File(p.join(root, '.flavor_cli.json'));
      if (!legacyFile.existsSync()) return null;
      try {
        final content = legacyFile.readAsStringSync();
        final jsonMap = jsonDecode(content) as Map<String, dynamic>;
        return FlavorConfig.fromJson(jsonMap);
      } catch (_) {
        return null;
      }
    }

    try {
      final content = file.readAsStringSync();
      final yamlMap = loadYaml(content);
      final jsonMap = YamlUtils.yamlToMap(yamlMap);
      return FlavorConfig.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  // ========================
  // SAVE CONFIG
  // ========================
  /// Saves the flavor configuration to the YAML file.
  static void save(FlavorConfig config) {
    final json = config.toJson();

    // Values live in .env files — don't persist them in the YAML.
    json.remove('values');

    final file = File(_configPath);
    String existingContent = '';
    if (file.existsSync()) {
      existingContent = file.readAsStringSync();
    }

    // We use YamlEditor to cleanly generate or update the YAML
    final editor = YamlEditor(existingContent);
    try {
      editor.update([], json);
    } catch (e) {
      // If update fails on root, recreate
      final freshEditor = YamlEditor('');
      freshEditor.update([], json);
      file.writeAsStringSync(freshEditor.toString());
      return;
    }

    file.writeAsStringSync(editor.toString());
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

      var updatedConfig = config.copyWith(
        flavors: updatedFlavors,
        flavorValues: updatedValues,
      );

      if (updatedConfig.productionFlavor == flavor &&
          updatedFlavors.isNotEmpty) {
        updatedConfig =
            updatedConfig.copyWith(productionFlavor: updatedFlavors.first);
      }

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

  /// Checks if Firebase is configured in the .flavor_cli.json file.
  static bool hasFirebaseConfig() {
    try {
      if (isInitialized()) {
        final config = loadLenient();
        return config?.firebase != null;
      }
    } catch (_) {}
    return false;
  }

  /// Checks if Firebase files or dependencies actually exist in the project.
  static bool hasFirebaseFiles() {
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

      // Check for flavored options in lib/
      final libDir = Directory(p.join(root, 'lib'));
      if (libDir.existsSync()) {
        final files = libDir.listSync();
        if (files
            .any((f) => p.basename(f.path).startsWith('firebase_options'))) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// General check for Firebase presence (either config or files).
  static bool hasFirebase() {
    return hasFirebaseConfig() || hasFirebaseFiles();
  }
}
