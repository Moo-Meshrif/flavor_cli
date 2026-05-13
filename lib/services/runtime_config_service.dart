import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/flavor_config.dart';
import '../utils/env_utils.dart';
import '../utils/logger.dart';
import 'config_service.dart';
import '../utils/type_utils.dart';
import 'file_service.dart';
import 'pubspec_service.dart';

/// Service for generating the ENV (.env.<flavor>) based runtime config.
/// Values are stored in .env files and loaded at app startup via flutter_dotenv.
class RuntimeConfigService {
  void updateEnvFile(String flavor, Map<String, dynamic> values) {
    final root = ConfigService.root;
    final envFile = File(p.join(root, '.env.$flavor'));

    Map<String, String> existingValues = {};
    if (envFile.existsSync()) {
      existingValues = EnvUtils.parseEnvFile(envFile.readAsStringSync());
    }

    // Merge values
    for (final entry in values.entries) {
      existingValues[EnvUtils.toSnakeCase(entry.key)] = entry.value.toString();
    }

    // Load fields to know if some values need double quotes etc.
    final config = ConfigService.loadLenient();
    final fields = config?.fields ?? {};

    final content = EnvUtils.generateEnvContent(existingValues, fields);
    envFile.writeAsStringSync(content);
  }

  void generateFlavorFiles(FlavorConfig config) {
    final root = ConfigService.root;
    for (final flavor in config.flavors) {
      final envFile = File(p.join(root, '.env.$flavor'));
      final values = config.flavorValues[flavor];
      final hasValues = values != null && values.isNotEmpty;

      // If no in-memory values and file already exists, leave it alone.
      // This happens when ConfigService.load() is called in ENV mode
      // (values are not persisted in flavor_cli.yaml).
      if (!hasValues && envFile.existsSync()) continue;

      // Use provided values or generate defaults for new flavors.
      final effectiveValues = hasValues
          ? values
          : {
              for (final entry in config.fields.entries)
                entry.key: TypeUtils.getDefaultTypedValueForType(entry.value),
            };

      final content =
          EnvUtils.generateEnvContent(effectiveValues, config.fields);
      envFile.writeAsStringSync(content);
    }
  }

  void generateAppConfig(FlavorConfig config) {
    final path = p.join(ConfigService.root, config.appConfigPath);
    final file = File(path);

    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final content = _buildEnvAppConfigContent(config);
    file.writeAsStringSync(content);
    FileService.formatFile(path);
  }

  String _buildEnvAppConfigContent(FlavorConfig config) {
    final flavors = config.flavors;
    final fields = config.fields;
    final buffer = StringBuffer();

    buffer.writeln("// GENERATED CODE - DO NOT MODIFY BY HAND");
    buffer.writeln();
    buffer.writeln("import 'package:flutter_dotenv/flutter_dotenv.dart';");
    buffer.writeln();
    buffer.writeln("enum Flavor { ${flavors.join(', ')} }");
    buffer.writeln();
    buffer.writeln("class AppConfig {");
    buffer.writeln("  static late Flavor flavor;");
    buffer.writeln();

    // Typed getters that read from dotenv
    for (final entry in fields.entries) {
      final name = entry.key;
      final type = entry.value;
      final envKey = EnvUtils.toSnakeCase(name);
      buffer.writeln(
          "  static ${type} get $name => ${_dotenvGetter(type, envKey)};");
    }

    buffer.writeln();
    buffer.writeln("  static void init(Flavor f) {");
    buffer.writeln("    flavor = f;");
    buffer.writeln("  }");
    buffer.writeln("}");

    return buffer.toString();
  }

  String _dotenvGetter(String type, String envKey) {
    switch (type.trim()) {
      case 'bool':
        return "dotenv.env['$envKey']?.toLowerCase() == 'true'";
      case 'int':
        return "int.tryParse(dotenv.env['$envKey'] ?? '') ?? 0";
      case 'double':
        return "double.tryParse(dotenv.env['$envKey'] ?? '') ?? 0.0";
      default:
        return "dotenv.env['$envKey'] ?? ''";
    }
  }

  String generateMainBoilerplate(String flavor, FlavorConfig config) {
    final configPath = config.appConfigPath;
    final relativePath = p.relative(configPath, from: 'lib/main');
    return """
import '$relativePath';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.$flavor');
  AppConfig.init(Flavor.$flavor);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Hello Flavor: $flavor')),
      ),
    );
  }
}
""";
  }

  String generateSingleMainBoilerplate(FlavorConfig config) {
    final configPath = config.appConfigPath;
    final relativePath = p.relative(configPath, from: 'lib');
    final flavors = config.flavors;
    final cases =
        flavors.map((f) => "    case '\$f': return Flavor.\$f;").join('\n');

    return """
import '$relativePath';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const flavorString = String.fromEnvironment('FLAVOR');
  final flavor = _getFlavor(flavorString);
  await dotenv.load(fileName: '.env.\$flavorString');
  AppConfig.init(flavor);
  runApp(const MyApp());
}

Flavor _getFlavor(String flavor) {
  switch (flavor) {
$cases
    default: return Flavor.${flavors.first};
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Hello Flavor')),
      ),
    );
  }
}
""";
  }

  List<String> buildRunArgs(
    FlavorConfig config,
    String flavor, {
    List<String> extraArgs = const [],
  }) {
    final separate = config.useSeparateMains;
    final target = separate ? 'lib/main/main_$flavor.dart' : 'lib/main.dart';
    // Pass --dart-define=FLAVOR=<flavor>
    final args = [
      '--flavor',
      flavor,
      '-t',
      target,
      '--dart-define=FLAVOR=$flavor',
    ];
    args.addAll(extraArgs);
    return args;
  }

  void integrateMainFile(String path, FlavorConfig config, {String? flavor}) {
    final file = File(path);
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();
    final configPath = config.appConfigPath;

    final relativeToRoot = p.relative(path, from: ConfigService.root);
    final relativeConfigPath =
        p.relative(configPath, from: p.dirname(relativeToRoot));

    // 1. Add AppConfig import
    if (!content.contains(p.basename(configPath))) {
      content = "import '$relativeConfigPath';\n$content";
    }

    // 2. Add flutter_dotenv import
    if (!content.contains('flutter_dotenv')) {
      content =
          "import 'package:flutter_dotenv/flutter_dotenv.dart';\n$content";
    }

    // 3. Ensure dotenv.load and AppConfig.init are present
    if (!content.contains('dotenv.load')) {
      final mainRegex =
          RegExp(r'(Future<void>|void) main\s*\(\s*\)\s*(async\s*)?{');
      final match = mainRegex.firstMatch(content);
      if (match != null) {
        final String loadCall;
        if (flavor != null) {
          loadCall = "await dotenv.load(fileName: '.env.$flavor');";
        } else {
          loadCall =
              "const flavorString = String.fromEnvironment('FLAVOR');\n  await dotenv.load(fileName: '.env.\$flavorString');";
        }

        final String initCall;
        if (content.contains('AppConfig.init')) {
          initCall = ""; // Already present
        } else {
          initCall = flavor != null
              ? "\n  AppConfig.init(Flavor.$flavor);"
              : "\n  final flavor = _getFlavor(flavorString);\n  AppConfig.init(flavor);";
        }

        // Remove existing ensureInitialized to avoid duplicates and ensure it's at the top
        content = content.replaceAll(
            RegExp(r'^\s*WidgetsFlutterBinding\.ensureInitialized\(\);\s*\n?',
                multiLine: true),
            '');

        content = content.replaceFirst(
          mainRegex,
          "Future<void> main() async {\n  WidgetsFlutterBinding.ensureInitialized();\n  $loadCall$initCall",
        );
      }
    } else if (!content.contains('AppConfig.init')) {
      // dotEnv exists but AppConfig.init doesn't? (unlikely but possible)
      final initCall = flavor != null
          ? "AppConfig.init(Flavor.$flavor);"
          : "final flavor = _getFlavor(flavorString);\n  AppConfig.init(flavor);";
      content =
          content.replaceFirst('dotenv.load(', '$initCall\n  dotenv.load(');
    }

    // 4. Ensure _getFlavor helper exists for single main strategy
    if (flavor == null && !content.contains('Flavor _getFlavor')) {
      final flavors = config.flavors;
      final cases =
          flavors.map((f) => "    case '$f': return Flavor.$f;").join('\n');
      final helper = """
Flavor _getFlavor(String flavor) {
  switch (flavor) {
$cases
    default: return Flavor.${flavors.first};
  }
}
""";
      content = "$content\n$helper";
    }

    file.writeAsStringSync(content);
    FileService.formatFile(path);
  }

  void cleanupFlavorFiles(List<String> deletedFlavors, FlavorConfig config) {
    final root = ConfigService.root;
    for (final flavor in deletedFlavors) {
      final envFile = File(p.join(root, '.env.$flavor'));
      if (envFile.existsSync()) {
        envFile.deleteSync();
      }
    }
  }

  void renameFlavorFiles(String oldName, String newName, FlavorConfig config) {
    final root = ConfigService.root;
    final oldEnvFile = File(p.join(root, '.env.$oldName'));
    final newEnvFile = File(p.join(root, '.env.$newName'));
    if (oldEnvFile.existsSync()) {
      oldEnvFile.renameSync(newEnvFile.path);
    }

    // Update pubspec.yaml assets
    PubspecService.removeAssets(['.env.$oldName']);
    PubspecService.addAssets(['.env.$newName']);
  }

  List<String> validate(FlavorConfig config) {
    final errors = <String>[];
    final root = ConfigService.root;

    // Check .env.<flavor> files exist
    for (final flavor in config.flavors) {
      final envFile = File(p.join(root, '.env.$flavor'));
      if (!envFile.existsSync()) {
        errors.add('   → Missing .env.$flavor file. Run setup to regenerate.');
      }
    }

    // Check flutter_dotenv dependency
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      final content = pubspecFile.readAsStringSync();
      if (!content.contains('flutter_dotenv')) {
        errors.add(
            '   → flutter_dotenv dependency missing in pubspec.yaml. Add: flutter_dotenv: ^5.1.0');
      }
    }

    return errors;
  }

  /// Validates that both the .env file and entry-point file exist for [flavor].
  /// Logs errors via [log] and returns false if either is missing.
  bool validateFlavorReadyToRun(
      FlavorConfig config, String flavor, AppLogger log) {
    final envFile = File('.env.$flavor');
    if (!envFile.existsSync()) {
      log.error(
          '❌ Error: Missing .env.$flavor file. Run "init" or "setup" to regenerate it.');
      return false;
    }

    final targetPath = config.useSeparateMains
        ? 'lib/main/main_$flavor.dart'
        : 'lib/main.dart';
    if (!File(targetPath).existsSync()) {
      log.error('❌ Error: Entry point not found: $targetPath');
      return false;
    }

    return true;
  }
}
