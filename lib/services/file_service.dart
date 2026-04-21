import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';
import '../utils/type_utils.dart';
import 'config_service.dart';

class FileService {
  static void createStructure() {
    if (ConfigService.load().useSeparateMains) {
      Directory(p.join(ConfigService.root, 'lib/main'))
          .createSync(recursive: true);
    }
    Directory(p.join(ConfigService.root, 'ios/Flutter'))
        .createSync(recursive: true);
  }

  static void createAppConfig({bool overwrite = true}) {
    final path = p.join(ConfigService.root, ConfigService.load().appConfigPath);
    final file = File(path);

    if (!overwrite && file.existsSync()) return;

    // Ensure directory exists
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final flavors = ConfigService.load().flavors;
    final fields = ConfigService.load().fields;

    final buffer = StringBuffer();
    buffer.writeln("// GENERATED CODE - DO NOT MODIFY BY HAND");
    buffer.writeln();
    buffer.writeln("enum Flavor { ${flavors.join(', ')} }");
    buffer.writeln();
    buffer.writeln("class AppConfig {");
    buffer.writeln("  static late Flavor flavor;");

    for (final entry in fields.entries) {
      buffer.writeln("  static late ${entry.value} ${entry.key};");
    }

    buffer.writeln();
    buffer.writeln("  static void init(Flavor f) {");
    buffer.writeln("    flavor = f;");
    buffer.writeln("    switch (f) {");

    final config = ConfigService.load();
    for (final f in flavors) {
      buffer.writeln("      case Flavor.$f:");
      final values = config.flavorValues[f] ?? {};
      for (final entry in fields.entries) {
        final rawVal = values[entry.key] ?? '';
        final val = TypeUtils.formatValueForDart(entry.value, rawVal);
        buffer.writeln("        ${entry.key} = $val;");
      }
      buffer.writeln("        break;");
    }

    buffer.writeln("    }");
    buffer.writeln("  }");
    buffer.writeln("}");

    file.writeAsStringSync(buffer.toString());
  }

  static void addFlavorToAppConfig(String flavor) {
    var path = p.join(ConfigService.root, ConfigService.load().appConfigPath);
    var file = File(path);
    if (!file.existsSync()) {
      createAppConfig();
      return;
    }

    var content = file.readAsStringSync();

    // Ensure generated hint is present
    const hint = "// GENERATED CODE - DO NOT MODIFY BY HAND";
    if (!content.startsWith(hint)) {
      content = "$hint\n\n$content";
    }

    // Remove TODO if present
    content = content.replaceAll(
        '// TODO: Fill in your flavor values here\n', '');
    content = content.replaceAll(
        '// TODO: Fill in your flavor values here', '');

    // 1. Update Enum
    final enumRegex = RegExp(r'enum Flavor\s*\{([^}]*)\}');
    final enumMatch = enumRegex.firstMatch(content);
    if (enumMatch != null) {
      final flavorsLine = enumMatch.group(1)!;
      final flavors = flavorsLine.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (!flavors.contains(flavor)) {
        flavors.add(flavor);
        content = content.replaceFirst(enumRegex, 'enum Flavor { ${flavors.join(', ')} }');
      }
    }

    // 2. Update switch in init()
    final switchRegex = RegExp(r'switch\s*\(f\)\s*\{');
    final switchMatch = switchRegex.firstMatch(content);
    if (switchMatch != null) {
      final startIndex = switchMatch.end;
      final closingBraceIndex = _findMatchingBrace(content, switchMatch.end - 1);
      if (closingBraceIndex != -1) {
        final switchBody = content.substring(startIndex, closingBraceIndex);
        if (!switchBody.contains('case Flavor.$flavor:')) {
          final config = ConfigService.load();
          final fields = config.fields;
          final values = config.flavorValues[flavor] ?? {};
          final buffer = StringBuffer();
          buffer.writeln();
          buffer.writeln("      case Flavor.$flavor:");
          for (final entry in fields.entries) {
            final rawVal = values[entry.key] ?? '';
            final val = TypeUtils.formatValueForDart(entry.value, rawVal);
            buffer.writeln("        ${entry.key} = $val;");
          }
          buffer.writeln("        break;");

          // Insert before the closing brace of the switch
          content = content.substring(0, closingBraceIndex) +
              buffer.toString() +
              content.substring(closingBraceIndex);
        }
      }
    }

    file.writeAsStringSync(content);
  }

  static void removeFlavorFromAppConfig(String flavor) {
    var path = p.join(ConfigService.root, ConfigService.load().appConfigPath);
    var file = File(path);
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();

    // Ensure generated hint is present
    const hint = "// GENERATED CODE - DO NOT MODIFY BY HAND";
    if (!content.startsWith(hint)) {
      content = "$hint\n\n$content";
    }

    // Remove TODO if present
    content = content.replaceAll(
        '// TODO: Fill in your flavor values here\n', '');
    content = content.replaceAll(
        '// TODO: Fill in your flavor values here', '');

    // 1. Update Enum
    // Handles multi-line enums and various spacing
    final enumRegex = RegExp(r'enum Flavor\s*\{([\s\S]*?)\}');
    final enumMatch = enumRegex.firstMatch(content);
    if (enumMatch != null) {
      final oldBody = enumMatch.group(1)!;
      // Match flavor as a whole word, possibly followed by a comma and whitespace
      var newBody = oldBody.replaceAll(RegExp('\\b$flavor\\b\\s*,?'), '');

      // Clean up whitespace and any potential double commas leftovers
      newBody = newBody.replaceAll(RegExp(r',\s*,'), ',');
      newBody = newBody.trim();
      if (newBody.endsWith(',')) {
        newBody = newBody.substring(0, newBody.length - 1).trim();
      }

      content = content.replaceFirst(oldBody, '\n  $newBody\n');
    }

    // 2. Remove case from switch
    final casePrefix = 'case Flavor.$flavor:';
    final caseIndex = content.indexOf(casePrefix);
    if (caseIndex != -1) {
      // Find the start of the line for proper cleaning
      var startOfLine = content.lastIndexOf('\n', caseIndex);
      if (startOfLine == -1) startOfLine = 0;

      // Find the end: either the next case or the end of the switch
      var nextCaseIndex =
          content.indexOf('case Flavor.', caseIndex + casePrefix.length);
      if (nextCaseIndex != -1) {
        // Find the start of that line to remove everything up to it
        var nextLineStart = content.lastIndexOf('\n', nextCaseIndex);
        if (nextLineStart != -1) {
          content = content.replaceRange(startOfLine, nextLineStart, '');
        } else {
          content = content.replaceRange(startOfLine, nextCaseIndex, '');
        }
      } else {
        // No next case, look for the end of the switch block
        final switchMatch = RegExp(r'switch\s*\(f\)\s*\{').firstMatch(content);
        if (switchMatch != null) {
          final closingBraceIndex =
              _findMatchingBrace(content, switchMatch.end - 1);
          if (closingBraceIndex != -1) {
            // Find last newline before closing brace to preserve it
            var endOfBlock = content.lastIndexOf('\n', closingBraceIndex);
            if (endOfBlock != -1 && endOfBlock > startOfLine) {
              content = content.replaceRange(startOfLine, endOfBlock, '');
            } else {
              content = content.replaceRange(startOfLine, closingBraceIndex, '');
            }
          }
        }
      }
    }

    file.writeAsStringSync(content);
  }

  // _getDefaultValueForType removed in favor of TypeUtils

  static void createMainFiles({bool overwrite = true}) {
    final useSeparate = ConfigService.load().useSeparateMains;
    final flavors = ConfigService.load().flavors;

    if (useSeparate) {
      for (final flavor in flavors) {
        final file =
            File(p.join(ConfigService.root, 'lib/main/main_$flavor.dart'));
        if (!overwrite && file.existsSync()) continue;

        file.writeAsStringSync(_mainBoilerplate(flavor));
      }
    } else {
      final file = File(p.join(ConfigService.root, 'lib/main.dart'));
      if (!overwrite && file.existsSync()) return;

      file.writeAsStringSync(_singleMainBoilerplate(flavors));
    }
  }

  static void integrateMainFiles(
      {required List<String> flavors, required bool separate}) {
    if (separate) {
      for (final flavor in flavors) {
        _integrateFile(p.join(ConfigService.root, 'lib/main/main_$flavor.dart'),
            flavor: flavor);
      }
    } else {
      _integrateFile(p.join(ConfigService.root, 'lib/main.dart'));
    }
  }

  static void cleanupFlavors(List<String> deletedFlavors) {
    for (final flavor in deletedFlavors) {
      // 1. Delete main file if exists
      final mainFile =
          File(p.join(ConfigService.root, 'lib/main/main_$flavor.dart'));
      if (mainFile.existsSync()) {
        mainFile.deleteSync();
      }

      // 2. Delete xcconfig if exists
      final xcconfigFile =
          File(p.join(ConfigService.root, 'ios/Flutter/$flavor.xcconfig'));
      if (xcconfigFile.existsSync()) {
        xcconfigFile.deleteSync();
      }

      // 3. Delete Firebase options if exists
      final firebaseFile =
          File(p.join(ConfigService.root, 'lib/firebase_options_$flavor.dart'));
      if (firebaseFile.existsSync()) {
        firebaseFile.deleteSync();
      }
    }

    // 3. Cleanup empty directories
    _deleteIfEmpty(p.join(ConfigService.root, 'lib/main'));
    _deleteIfEmpty(p.join(ConfigService.root, 'ios/Flutter'));
  }

  static void cleanupFirebaseConfig(String flavor) {
    final root = ConfigService.root;

    // 1. firebase.json cleanup
    final firebaseFile = File(p.join(root, 'firebase.json'));
    if (firebaseFile.existsSync()) {
      try {
        final content = firebaseFile.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;

        if (json.containsKey('flutter') &&
            json['flutter'].containsKey('platforms') &&
            json['flutter']['platforms'].containsKey('dart')) {
          final dart =
              json['flutter']['platforms']['dart'] as Map<String, dynamic>;
          final targetKey = 'lib/firebase_options_$flavor.dart';

          if (dart.containsKey(targetKey)) {
            dart.remove(targetKey);
            const encoder = JsonEncoder.withIndent('    ');
            firebaseFile.writeAsStringSync(encoder.convert(json));
          }
        }
      } catch (_) {
        // Ignore errors if JSON is malformed
      }
    }

    // 2. google-services.json cleanup
    final googleFile = File(p.join(root, 'android/app/google-services.json'));
    if (googleFile.existsSync()) {
      try {
        final content = googleFile.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;

        if (json.containsKey('client')) {
          final clients = json['client'] as List<dynamic>;

          // Calculate package ID for this flavor
          final config = ConfigService.load();
          final baseId = config.android.applicationId;
          final prodFlavor = ConfigService.load().productionFlavor;
          final useSuffix = ConfigService.load().useSuffix;

          String packageId = baseId;
          if (useSuffix && flavor != prodFlavor) {
            packageId = '$baseId.$flavor';
          }

          final initialLength = clients.length;
          clients.removeWhere((c) {
            if (c is Map && c.containsKey('client_info')) {
              final info = c['client_info'] as Map;
              if (info.containsKey('android_client_info')) {
                final android = info['android_client_info'] as Map;
                return android['package_name'] == packageId;
              }
            }
            return false;
          });

          if (clients.length != initialLength) {
            const encoder = JsonEncoder.withIndent('  ');
            googleFile.writeAsStringSync(encoder.convert(json));
          }
        }
      } catch (_) {
        // Ignore errors
      }
    }
  }

  static void _deleteIfEmpty(String path) {
    final dir = Directory(path);
    if (dir.existsSync() && dir.listSync().isEmpty) {
      dir.deleteSync();
    }
  }

  static int _findMatchingBrace(String content, int openBraceIndex) {
    int count = 1;
    for (int i = openBraceIndex + 1; i < content.length; i++) {
      if (content[i] == '{') count++;
      if (content[i] == '}') count--;
      if (count == 0) return i;
    }
    return -1;
  }

  static Set<String> getOrphanedFlavors(List<String> currentFlavors) {
    final orphans = <String>{};

    // 1. Check lib/main/
    final mainDir = Directory(p.join(ConfigService.root, 'lib/main'));
    if (mainDir.existsSync()) {
      for (final entity in mainDir.listSync()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          final match = RegExp(r'^main_(.*)\.dart$').firstMatch(name);
          if (match != null) {
            final flavor = match.group(1)!;
            if (!currentFlavors.contains(flavor)) {
              orphans.add(flavor);
            }
          }
        }
      }
    }

    // 2. Check ios/Flutter/
    final iosDir = Directory(p.join(ConfigService.root, 'ios/Flutter'));
    if (iosDir.existsSync()) {
      for (final entity in iosDir.listSync()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          final match = RegExp(r'^(.*)\.xcconfig$').firstMatch(name);
          if (match != null) {
            final flavor = match.group(1)!;
            // Ignore standard files
            if (flavor == 'Generated' ||
                flavor == 'Release' ||
                flavor == 'Debug') {
              continue;
            }

            if (!currentFlavors.contains(flavor)) {
              orphans.add(flavor);
            }
          }
        }
      }
    }

    return orphans;
  }

  static void _integrateFile(String path, {String? flavor}) {
    final file = File(path);
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();
    final configPath = ConfigService.load().appConfigPath;

    // Calculate relative path from the main file to any config path,
    // respecting the working directory.
    final relativeToRoot = p.relative(path, from: ConfigService.root);
    final relativeConfigPath =
        p.relative(configPath, from: p.dirname(relativeToRoot));

    // 1. Add Import
    if (!content.contains(p.basename(configPath))) {
      content = "import '$relativeConfigPath';\n$content";
    }

    // 2. Add AppConfig.init inside main()
    if (!content.contains('AppConfig.init')) {
      final mainRegex = RegExp(r'void main\s*\(\s*\)\s*(async\s*)?{');
      final match = mainRegex.firstMatch(content);
      if (match != null) {
        final asyncMod = match.group(1) ?? '';
        if (flavor != null) {
          content = content.replaceFirst(
            mainRegex,
            'void main() ${asyncMod}{\n  AppConfig.init(Flavor.$flavor);',
          );
        } else {
          content = content.replaceFirst(
            mainRegex,
            "void main() ${asyncMod}{\n  const flavorString = String.fromEnvironment('FLAVOR');\n  final flavor = _getFlavor(flavorString);\n  AppConfig.init(flavor);",
          );
        }
      }
    }

    // 3. Add Switch Case helper if needed (for single main)
    if (flavor == null) {
      final flavors = ConfigService.load().flavors;
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
      final sig = 'Flavor _getFlavor';
      final startIndex = content.indexOf(sig);
      if (startIndex != -1) {
        final openBraceIndex = content.indexOf('{', startIndex);
        if (openBraceIndex != -1) {
          final closingBraceIndex = _findMatchingBrace(content, openBraceIndex);
          if (closingBraceIndex != -1) {
            content = content.substring(0, startIndex).trimRight() +
                "\n\n" +
                helper.trim() +
                content.substring(closingBraceIndex + 1);
          }
        }
      } else {
        content = content.trimRight() + "\n\n" + helper.trim() + "\n";
      }
    }

    file.writeAsStringSync(content);
  }

  static void updateTests() {
    final testPath = p.join(ConfigService.root, 'test/widget_test.dart');
    final file = File(testPath);
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();
    final pubspec = File(p.join(ConfigService.root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return;

    final nameRegex = RegExp(r'^name:\s*(.*)$', multiLine: true);
    final match = nameRegex.firstMatch(pubspec.readAsStringSync());
    if (match == null) return;

    final pkgName = match.group(1)!.trim();
    final prodFlavor = ConfigService.load().productionFlavor;
    final useSeparate = ConfigService.load().useSeparateMains;

    final targetImport = useSeparate
        ? "import 'package:$pkgName/main/main_$prodFlavor.dart';"
        : "import 'package:$pkgName/main.dart';";

    // Regex to match any variant of the main import
    final importRegex = RegExp(
      "import ['\"]package:$pkgName/(main/main_.*|main)\\.dart['\"];",
      multiLine: true,
    );

    if (importRegex.hasMatch(content)) {
      content = content.replaceAll(importRegex, targetImport);
    }

    file.writeAsStringSync(content);
  }

  static String _mainBoilerplate(String flavor) {
    final configPath = ConfigService.load().appConfigPath;
    final relativePath = p.relative(configPath, from: 'lib/main');

    return """
import '$relativePath';
import 'package:flutter/material.dart';

void main() {
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

  static String _singleMainBoilerplate(List<String> flavors) {
    final configPath = ConfigService.load().appConfigPath;
    final relativePath = p.relative(configPath, from: 'lib');
    final cases =
        flavors.map((f) => "    case '$f': return Flavor.$f;").join('\n');

    return """
import '$relativePath';
import 'package:flutter/material.dart';

void main() {
  const flavorString = String.fromEnvironment('FLAVOR');
  final flavor = _getFlavor(flavorString);
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

  static void createScripts() {
    Directory(p.join(ConfigService.root, 'scripts'))
        .createSync(recursive: true);
    final file = File(p.join(ConfigService.root, 'scripts/run.sh'));
    final useSeparate = ConfigService.load().useSeparateMains;

    String command;
    if (useSeparate) {
      command = 'flutter run --flavor \$FLAVOR -t lib/main/main_\$FLAVOR.dart';
    } else {
      command =
          'flutter run --flavor \$FLAVOR -t lib/main.dart --dart-define=FLAVOR=\$FLAVOR';
    }

    file.writeAsStringSync('''
#!/bin/bash
FLAVOR=\$1
if [ -z "\$FLAVOR" ]; then
    echo "Usage: ./run.sh [flavor]"
    exit 1
fi
$command
''');
  }

  static void renameFlavor({
    required String oldName,
    required String newName,
    required AppLogger log,
  }) {
    final root = ConfigService.root;

    // 1. Rename Main File
    final oldMainPath = p.join(root, 'lib/main/main_$oldName.dart');
    final newMainPath = p.join(root, 'lib/main/main_$newName.dart');
    final oldMainFile = File(oldMainPath);

    if (oldMainFile.existsSync()) {
      log.info(
          '📝 Renaming main file: ${p.basename(oldMainPath)} -> ${p.basename(newMainPath)}');
      var content = oldMainFile.readAsStringSync();
      // Update internal references
      content = content.replaceAll('Flavor.$oldName', 'Flavor.$newName');
      content = content.replaceAll("'$oldName'", "'$newName'");
      content = content.replaceAll('firebase_options_$oldName.dart', 'firebase_options_$newName.dart');

      File(newMainPath).writeAsStringSync(content);
      oldMainFile.deleteSync();
    }

    // 2. Update AppConfig
    final appConfigPath = p.join(root, ConfigService.load().appConfigPath);
    final appConfigFile = File(appConfigPath);

    if (appConfigFile.existsSync()) {
      log.info('📝 Updating AppConfig enum and switch cases...');
      var content = appConfigFile.readAsStringSync();

      // Ensure generated hint is present
      const hint = "// GENERATED CODE - DO NOT MODIFY BY HAND";
      if (!content.startsWith(hint)) {
        content = "$hint\n\n$content";
      }

      // Remove TODO if present
      content = content.replaceAll(
          '// TODO: Fill in your flavor values here\n', '');
      content = content.replaceAll(
          '// TODO: Fill in your flavor values here', '');

      // Update Enum
      final enumRegex = RegExp(r'enum Flavor\s*\{([^}]*)\}');
      final enumMatch = enumRegex.firstMatch(content);
      if (enumMatch != null) {
        final flavorsLine = enumMatch.group(1)!;
        final flavors = flavorsLine.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        final index = flavors.indexOf(oldName);
        if (index != -1) {
          flavors[index] = newName;
          content = content.replaceFirst(enumRegex, 'enum Flavor { ${flavors.join(', ')} }');
        }
      }

      // Update references (Flavor.name)
      content = content.replaceAll('Flavor.$oldName', 'Flavor.$newName');

      appConfigFile.writeAsStringSync(content);
    }

    // 3. Update single main if exists
    final rootMain = File(p.join(root, 'lib/main.dart'));
    if (rootMain.existsSync()) {
      var content = rootMain.readAsStringSync();
      if (content.contains('Flavor.$oldName') ||
          content.contains("'$oldName'") ||
          content.contains('firebase_options_$oldName.dart')) {
        log.info('📝 Updating lib/main.dart references...');
        content = content.replaceAll('Flavor.$oldName', 'Flavor.$newName');
        content = content.replaceAll("'$oldName'", "'$newName'");
        content = content.replaceAll('firebase_options_$oldName.dart', 'firebase_options_$newName.dart');
        content = content.replaceAll(' as $oldName;', ' as $newName;');
        content = content.replaceAll('$oldName.DefaultFirebaseOptions', '$newName.DefaultFirebaseOptions');
        rootMain.writeAsStringSync(content);
      }
    }

    // 4. Rename Firebase options if exists
    final oldFirebasePath = p.join(root, 'lib/firebase_options_$oldName.dart');
    final newFirebasePath = p.join(root, 'lib/firebase_options_$newName.dart');
    final oldFirebaseFile = File(oldFirebasePath);

    if (oldFirebaseFile.existsSync()) {
      log.info(
          '📝 Renaming Firebase options: ${p.basename(oldFirebasePath)} -> ${p.basename(newFirebasePath)}');
      oldFirebaseFile.renameSync(newFirebasePath);
    }
  }

  static void injectFirebase({required bool separate, String? flavor}) {
    final root = ConfigService.root;
    final config = ConfigService.load();
    final strategy = config.firebase?.strategy;
    final flavors = config.flavors;

    if (separate) {
      if (flavor == null) {
        for (final f in flavors) {
          injectFirebase(separate: true, flavor: f);
        }
        return;
      }
      
      final mainPath = p.join(root, 'lib/main/main_$flavor.dart');
      final file = File(mainPath);
      if (!file.existsSync()) return;

      final optionsFile = strategy == 'shared_id_single_project' 
          ? 'firebase_options.dart' 
          : 'firebase_options_$flavor.dart';
      
      final configFile = File(p.join(root, 'lib/$optionsFile'));
      if (!configFile.existsSync()) return;

      var content = file.readAsStringSync();
      
      // 1. Manage Imports
      if (!content.contains('firebase_core.dart')) {
        content = "import 'package:firebase_core/firebase_core.dart';\n"
                  "import '../$optionsFile';\n$content";
      } else if (!content.contains(optionsFile)) {
        content = "import '../$optionsFile';\n$content";
      }

      // 2. Inject Initialization
      if (content.contains('Firebase.initializeApp')) {
        return; // Skip if already initialized
      }

      final initRegex = RegExp(r'^(\s*)AppConfig\.init\s*\(.*\);', multiLine: true);
      final match = initRegex.firstMatch(content);
      
      if (match != null) {
        final indent = match.group(1) ?? '  ';
        final initBlock = "\n${indent}WidgetsFlutterBinding.ensureInitialized();\n"
            "${indent}await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);\n";

        final mainRegex = RegExp(r'void main\s*\(\s*\)\s*(async\s*)?{');
        content = content.replaceFirst(mainRegex, 'void main() async {');
        content = content.replaceFirst(match.group(0)!, '${match.group(0)!}$initBlock');
        file.writeAsStringSync(content);
      }
    } else {
      // Single Main Strategy
      final mainPath = p.join(root, 'lib/main.dart');
      final file = File(mainPath);
      if (!file.existsSync()) return;

      var content = file.readAsStringSync();

      if (strategy == 'shared_id_single_project') {
         final configFile = File(p.join(root, 'lib/firebase_options.dart'));
         if (!configFile.existsSync()) return;

         if (!content.contains('firebase_core.dart')) {
           content = "import 'package:firebase_core/firebase_core.dart';\n"
                     "import 'firebase_options.dart';\n$content";
         }
         
         if (!content.contains('Firebase.initializeApp')) {
           final initRegex = RegExp(r'^(\s*)AppConfig\.init\s*\(.*\);', multiLine: true);
           final match = initRegex.firstMatch(content);
           if (match != null) {
             final indent = match.group(1) ?? '  ';
             final initBlock = "\n${indent}WidgetsFlutterBinding.ensureInitialized();\n"
                 "${indent}await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);\n";
             
             final mainRegex = RegExp(r'void main\s*\(\s*\)\s*(async\s*)?{');
             content = content.replaceFirst(mainRegex, 'void main() async {');
             content = content.replaceFirst(match.group(0)!, '${match.group(0)!}$initBlock');
           }
         }
      } else {
        // Multi-Options Injection (Unique ID strategies)
        final configuredFlavors = flavors.where((f) {
          return File(p.join(root, 'lib/firebase_options_$f.dart')).existsSync();
        }).toList();

        if (configuredFlavors.isEmpty) return;

        // Clean existing to regenerate
        content = content.replaceAll(RegExp(r'''import ['"]package:firebase_core/firebase_core\.dart['"];\n?'''), '');
        content = content.replaceAll(RegExp(r'''import ['"]firebase_options_.*\.dart['"] as \w+;\n?'''), '');
        
        final importBuffer = StringBuffer();
        importBuffer.writeln("import 'package:firebase_core/firebase_core.dart';");
        for (final f in configuredFlavors) {
          importBuffer.writeln("import 'firebase_options_$f.dart' as $f;");
        }
        content = importBuffer.toString() + content.trimLeft();

        final initRegex = RegExp(r'await Firebase\.initializeApp\s*\([\s\S]*?\);');
        String indent = '  ';
        final configInitRegex = RegExp(r'^(\s*)AppConfig\.init\s*\(.*\);', multiLine: true);
        final configMatch = configInitRegex.firstMatch(content);
        if (configMatch != null) indent = configMatch.group(1) ?? '  ';

        final buffer = StringBuffer();
        buffer.writeln("await Firebase.initializeApp(");
        buffer.writeln("$indent  options: switch (flavor) {");
        for (final f in configuredFlavors) {
          buffer.writeln("$indent    Flavor.$f => $f.DefaultFirebaseOptions.currentPlatform,");
        }
        if (configuredFlavors.length < flavors.length) {
          buffer.writeln("$indent    _ => ${configuredFlavors.first}.DefaultFirebaseOptions.currentPlatform,");
        }
        buffer.writeln("$indent  },");
        buffer.write("$indent)");

        if (content.contains('Firebase.initializeApp')) {
          content = content.replaceFirst(initRegex, buffer.toString().trim() + ';');
        } else if (configMatch != null) {
          final initBlock = "\n${indent}WidgetsFlutterBinding.ensureInitialized();\n"
              "${indent}${buffer.toString().trim()};";
          final mainRegex = RegExp(r'void main\s*\(\s*\)\s*(async\s*)?{');
          content = content.replaceFirst(mainRegex, 'void main() async {');
          content = content.replaceFirst(configMatch.group(0)!, '${configMatch.group(0)!}$initBlock');
        }
      }
      file.writeAsStringSync(content);
    }
  }

  static void updateVSCodeLaunchConfig() {
    final root = ConfigService.root;
    final flavors = ConfigService.load().flavors;
    final separate = ConfigService.load().useSeparateMains;
    final vscodeDir = Directory(p.join(root, '.vscode'));
    if (!vscodeDir.existsSync()) vscodeDir.createSync();

    final launchFile = File(p.join(vscodeDir.path, 'launch.json'));
    Map<String, dynamic> config;

    if (launchFile.existsSync()) {
      try {
        config = jsonDecode(launchFile.readAsStringSync());
      } catch (_) {
        config = {'version': '0.2.0', 'configurations': []};
      }
    } else {
      config = {'version': '0.2.0', 'configurations': []};
    }

    final List<dynamic> currentConfigs = config['configurations'] ?? [];

    // Remove existing flavor configs
    currentConfigs.removeWhere((c) =>
        c is Map &&
        c['name'] is String &&
        (c['name'] as String).startsWith('Flutter: '));

    for (final flavor in flavors) {
      final String program =
          separate ? 'lib/main/main_$flavor.dart' : 'lib/main.dart';

      final Map<String, dynamic> flavorConfig = {
        'name': 'Flutter: $flavor',
        'request': 'launch',
        'type': 'dart',
        'program': program,
        'args': ['--flavor', flavor],
      };

      if (!separate) {
        flavorConfig['args'].addAll(['--dart-define', 'FLAVOR=$flavor']);
      }

      currentConfigs.add(flavorConfig);
    }

    config['configurations'] = currentConfigs;
    const encoder = JsonEncoder.withIndent('  ');
    launchFile.writeAsStringSync(encoder.convert(config));
  }

  static void removeVSCodeLaunchConfig() {
    final root = ConfigService.root;
    final launchFile = File(p.join(root, '.vscode/launch.json'));
    if (launchFile.existsSync()) launchFile.deleteSync();
  }
}
