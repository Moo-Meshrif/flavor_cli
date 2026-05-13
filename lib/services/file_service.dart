import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';
import 'config_service.dart';

/// Service for managing file system operations, including folder structure
/// and configuration injection for different platforms.
class FileService {
  /// Creates the necessary directory structure for flavors.
  static void createStructure() {
    if (ConfigService.load().useSeparateMains) {
      Directory(p.join(ConfigService.root, 'lib/main'))
          .createSync(recursive: true);
    }
    Directory(p.join(ConfigService.root, 'ios/Flutter'))
        .createSync(recursive: true);
  }

  /// Removes files and directories associated with deleted flavors.
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
      content = content.replaceAll('.env.$oldName', '.env.$newName');
      content = content.replaceAll(
          ': $oldName', ': $newName'); // For "Hello Flavor: c1"
      content = content.replaceAll(
          'firebase_options_$oldName.dart', 'firebase_options_$newName.dart');

      File(newMainPath).writeAsStringSync(content);
      oldMainFile.deleteSync();
    }

    // 2. AppConfig update is now handled by SetupRunner via RuntimeConfigService.generateAppConfig

    // 3. Update single main if exists
    final rootMain = File(p.join(root, 'lib/main.dart'));
    if (rootMain.existsSync()) {
      var content = rootMain.readAsStringSync();
      if (content.contains('Flavor.$oldName') ||
          content.contains("'$oldName'") ||
          content.contains('.env.$oldName') ||
          content.contains('firebase_options_$oldName.dart')) {
        log.info('📝 Updating lib/main.dart references...');
        content = content.replaceAll('Flavor.$oldName', 'Flavor.$newName');
        content = content.replaceAll("'$oldName'", "'$newName'");
        content = content.replaceAll('.env.$oldName', '.env.$newName');
        content = content.replaceAll(': $oldName', ': $newName');
        content = content.replaceAll(
            'firebase_options_$oldName.dart', 'firebase_options_$newName.dart');
        content = content.replaceAll(' as $oldName;', ' as $newName;');
        content = content.replaceAll('$oldName.DefaultFirebaseOptions',
            '$newName.DefaultFirebaseOptions');
        rootMain.writeAsStringSync(content);
      }
    }

    // 4. Firebase options handling
    final config = ConfigService.load();
    final strategy = config.firebase?.strategy ?? '';
    final isUniqueId = strategy.contains('unique_id');

    final oldFirebasePath = p.join(root, 'lib/firebase_options_$oldName.dart');
    final newFirebasePath = p.join(root, 'lib/firebase_options_$newName.dart');
    final oldFirebaseFile = File(oldFirebasePath);

    if (oldFirebaseFile.existsSync()) {
      if (isUniqueId) {
        log.info(
            '🗑️ Deleting old Firebase options (Unique ID strategy): ${p.basename(oldFirebasePath)}');
        oldFirebaseFile.deleteSync();

        // Also ensure the main files are cleaned if they were using these options
        _cleanupFirebaseFromEntryPoints(oldName, newName, log);
      } else {
        log.info(
            '📝 Renaming Firebase options: ${p.basename(oldFirebasePath)} -> ${p.basename(newFirebasePath)}');
        oldFirebaseFile.renameSync(newFirebasePath);
      }
    }
  }

  static void _cleanupFirebaseFromEntryPoints(
      String oldName, String newName, AppLogger log) {
    final root = ConfigService.root;

    // Separate main
    final newMainPath = p.join(root, 'lib/main/main_$newName.dart');
    final newMainFile = File(newMainPath);
    if (newMainFile.existsSync()) {
      log.info(
          '🧹 Cleaning Firebase from new main: ${p.basename(newMainPath)}');
      newMainFile.writeAsStringSync(
          removeFirebaseFromContent(newMainFile.readAsStringSync()));
    }

    // Single main
    final rootMain = File(p.join(root, 'lib/main.dart'));
    if (rootMain.existsSync()) {
      log.info('🧹 Cleaning Firebase from lib/main.dart');
      rootMain.writeAsStringSync(
          removeFirebaseFromContent(rootMain.readAsStringSync()));
    }
  }

  static String removeFirebaseFromContent(String content) {
    var cleaned = content;

    // 1. Remove Firebase init (multi-line)
    final firebaseInitRegex = RegExp(
        r'^\s*await Firebase\.initializeApp\([\s\S]*?\);[\t ]*\n?',
        multiLine: true);
    cleaned = cleaned.replaceAll(firebaseInitRegex, '');

    // 2. Remove Firebase imports and options imports (handles single/double quotes, aliases, and indentation)
    cleaned = cleaned.replaceAll(
        RegExp(
            r'''^\s*import\s+['"]package:firebase_core/firebase_core\.dart['"];[\t ]*\n?''',
            multiLine: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(
            r'''^\s*import\s+['"].*?firebase_options.*?\.dart['"](?:\s+as\s+\w+)?;[\t ]*\n?''',
            multiLine: true),
        '');

    // 3. Fix main() signature if it was made async for Firebase but no longer needs to be
    if (!cleaned.contains('await ')) {
      cleaned = cleaned.replaceFirst(
          RegExp(r'void main\s*\(\s*\) async\s*\{'), 'void main() {');
    }

    // 4. Cleanup multiple newlines
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return cleaned.trim() + '\n';
  }

  /// Injects Firebase initialization code into the entry point files.
  /// If [separate] is true, it injects into 'lib/main/main_<flavor>.dart'.
  /// Otherwise, it injects into 'lib/main.dart'.
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

      final initRegex =
          RegExp(r'^(\s*)AppConfig\.init\s*\(.*\);', multiLine: true);
      final match = initRegex.firstMatch(content);

      if (match != null) {
        final indent = match.group(1) ?? '  ';
        final ensureInitialized =
            content.contains('WidgetsFlutterBinding.ensureInitialized()')
                ? ""
                : "${indent}WidgetsFlutterBinding.ensureInitialized();\n";
        final initBlock =
            "\n$ensureInitialized${indent}await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);";

        final mainRegex = RegExp(r'void main\s*\(\s*\)\s*(async\s*)?{');
        content = content.replaceFirst(mainRegex, 'void main() async {');
        content = content.replaceFirst(
            match.group(0)!, '${match.group(0)!}$initBlock');
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
          final initRegex =
              RegExp(r'^(\s*)AppConfig\.init\s*\(.*\);', multiLine: true);
          final match = initRegex.firstMatch(content);
          if (match != null) {
            final indent = match.group(1) ?? '  ';
            final ensureInitialized =
                content.contains('WidgetsFlutterBinding.ensureInitialized()')
                    ? ""
                    : "${indent}WidgetsFlutterBinding.ensureInitialized();\n";
            final initBlock =
                "\n$ensureInitialized${indent}await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);";

            final mainRegex = RegExp(r'void main\s*\(\s*\)\s*(async\s*)?{');
            content = content.replaceFirst(mainRegex, 'void main() async {');
            content = content.replaceFirst(
                match.group(0)!, '${match.group(0)!}$initBlock');
          }
        }
      } else {
        // Multi-Options Injection (Unique ID strategies)
        final configuredFlavors = flavors.where((f) {
          return File(p.join(root, 'lib/firebase_options_$f.dart'))
              .existsSync();
        }).toList();

        if (configuredFlavors.isEmpty) return;

        // Clean existing to regenerate
        content = content.replaceAll(
            RegExp(
                r'''import ['"]package:firebase_core/firebase_core\.dart['"];\n?'''),
            '');
        content = content.replaceAll(
            RegExp(r'''import ['"]firebase_options_.*\.dart['"] as \w+;\n?'''),
            '');

        final importBuffer = StringBuffer();
        importBuffer
            .writeln("import 'package:firebase_core/firebase_core.dart';");
        for (final f in configuredFlavors) {
          importBuffer.writeln("import 'firebase_options_$f.dart' as $f;");
        }
        content = importBuffer.toString() + content.trimLeft();

        final initRegex =
            RegExp(r'await Firebase\.initializeApp\s*\([\s\S]*?\);');
        String indent = '  ';
        final configInitRegex =
            RegExp(r'^(\s*)AppConfig\.init\s*\(.*\);', multiLine: true);
        final configMatch = configInitRegex.firstMatch(content);
        if (configMatch != null) indent = configMatch.group(1) ?? '  ';

        final buffer = StringBuffer();
        buffer.writeln("await Firebase.initializeApp(");
        buffer.writeln("$indent  options: switch (flavor) {");
        for (final f in configuredFlavors) {
          buffer.writeln(
              "$indent    Flavor.$f => $f.DefaultFirebaseOptions.currentPlatform,");
        }
        if (configuredFlavors.length < flavors.length) {
          buffer.writeln(
              "$indent    _ => ${configuredFlavors.first}.DefaultFirebaseOptions.currentPlatform,");
        }
        buffer.writeln("$indent  },");
        buffer.write("$indent)");

        if (content.contains('Firebase.initializeApp')) {
          content =
              content.replaceFirst(initRegex, buffer.toString().trim() + ';');
        } else if (configMatch != null) {
          final indent = configMatch.group(1) ?? '  ';
          final ensureInitialized =
              content.contains('WidgetsFlutterBinding.ensureInitialized()')
                  ? ""
                  : "${indent}WidgetsFlutterBinding.ensureInitialized();\n";
          final initBlock =
              "\n$ensureInitialized${indent}${buffer.toString().trim()};";
          final mainRegex = RegExp(r'void main\s*\(\s*\)\s*(async\s*)?{');
          content = content.replaceFirst(mainRegex, 'void main() async {');
          content = content.replaceFirst(
              configMatch.group(0)!, '${configMatch.group(0)!}$initBlock');
        }
      }
      file.writeAsStringSync(content);
    }
  }

  static void updateVSCodeLaunchConfig() {
    final root = ConfigService.root;
    final flavorConfig = ConfigService.load();
    final flavors = flavorConfig.flavors;
    final separate = flavorConfig.useSeparateMains;
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

      // ENV mode: only pass --dart-define=FLAVOR=<flavor> for identification.
      // Field values are loaded from .env.<flavor> at runtime.
      (flavorConfig['args'] as List<String>)
          .addAll(['--dart-define', 'FLAVOR=$flavor']);

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

  static void formatFile(String path) {
    try {
      Process.runSync('dart', ['format', path]);
    } catch (_) {}
  }

  static void formatDirectory(String path) {
    try {
      Process.runSync('dart', ['format', path]);
    } catch (_) {}
  }
}
