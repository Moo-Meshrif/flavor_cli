import 'dart:io';
import 'package:path/path.dart' as p;
import 'config_service.dart';
import 'android_service.dart';
import 'ios_service.dart';
import 'file_service.dart';
import '../utils/logger.dart';

class ResetService {
  static void reset({AppLogger? logger}) {
    final log = logger ?? AppLogger();
    final root = ConfigService.root;

    final appConfigPath = ConfigService.getAppConfigPath();

    log.info('🧹 Starting full project reset...');

    // 1. Platform Reset
    try {
      AndroidService.reset(logger: log);
    } catch (e) {
      log.warn('⚠️ Android reset issue: $e');
    }

    try {
      IOSService.reset(logger: log);
    } catch (e) {
      log.warn('⚠️ iOS reset issue: $e');
    }

    // 2. Main Dart Restoration
    _restoreMainDart(root, log);

    // 3. File Cleanup
    // We pass an empty list to Cleanup to remove ALL flavor-related files ever found
    final allPossibleOrphans = FileService.getOrphanedFlavors([]);
    if (allPossibleOrphans.isNotEmpty) {
      log.info('🗑️ Removing orphaned flavor files: ${allPossibleOrphans.join(", ")}');
      FileService.cleanupFlavors(allPossibleOrphans.toList());
    }

    // Delete AppConfig
    final configFile = File(p.join(root, appConfigPath));
    if (configFile.existsSync()) {
      configFile.deleteSync();
      log.info('🗑️ Deleted $appConfigPath');
    }

    // Delete Scripts
    final scriptsDir = Directory(p.join(root, 'scripts'));
    if (scriptsDir.existsSync()) {
      scriptsDir.deleteSync(recursive: true);
      log.info('🗑️ Deleted scripts/ directory');
    }

    // 4. Delete flavor config file last
    final flavorConfigFile = File(p.join(root, '.flavor_cli.json'));
    if (flavorConfigFile.existsSync()) {
      flavorConfigFile.deleteSync();
      log.info('🗑️ Deleted .flavor_cli.json');
    }

    // 4.5. Cleanup Firebase configuration files
    _cleanupFirebaseFiles(root, log);

    // 5. Cleanup IDE configs
    FileService.removeVSCodeLaunchConfig();
    log.info('🗑️ Removed VS Code launch configurations');

    // 5. Cleanup parent directories
    _cleanupEmptyParent(p.join(root, 'lib/main'), log);
    _cleanupEmptyParent(p.join(root, p.dirname(appConfigPath)), log);

    // 6. Restore Tests
    _restoreTests(root, log);

    // 7. Final cleanup
    log.info('🧹 Finalizing: flutter clean && flutter pub get...');
    try {
      Process.runSync('flutter', ['clean'], runInShell: true);
      Process.runSync('flutter', ['pub', 'get'], runInShell: true);
    } catch (e) {
      log.warn('⚠️ Flutter cleanup issue: $e');
    }

    // 8. Final iOS sync to ensure sandbox is clean
    try {
      IOSService.syncPods(logger: log);
    } catch (e) {
      log.warn('⚠️ CocoaPods sync issue: $e');
    }

    log.success('✅ Project reset complete. App is back to its original state.');
  }

  static void _cleanupEmptyParent(String path, AppLogger log) {
    final dir = Directory(path);
    if (dir.existsSync() && dir.listSync().isEmpty) {
      dir.deleteSync();
      log.info('🗑️ Removed empty directory: ${p.relative(path, from: ConfigService.root)}');
    }
  }

  static void _cleanupFirebaseFiles(String root, AppLogger log) {
    var deletedAny = false;

    // Root level Firebase files
    for (final file in ['firebase.json', '.firebaserc']) {
      final f = File(p.join(root, file));
      if (f.existsSync()) {
        f.deleteSync();
        log.info('🗑️ Deleted $file');
        deletedAny = true;
      }
    }

    // Android
    final androidSrc = Directory(p.join(root, 'android/app/src'));
    if (androidSrc.existsSync()) {
      for (final entity in androidSrc.listSync()) {
        if (entity is Directory) {
          final jsonFile = File(p.join(entity.path, 'google-services.json'));
          if (jsonFile.existsSync()) {
            jsonFile.deleteSync();
            log.info('🗑️ Deleted ${p.relative(jsonFile.path, from: root)}');
            deletedAny = true;
          }
        }
      }
    }
    final baseAndroidJson = File(p.join(root, 'android/app/google-services.json'));
    if (baseAndroidJson.existsSync()) {
      baseAndroidJson.deleteSync();
      log.info('🗑️ Deleted ${p.relative(baseAndroidJson.path, from: root)}');
      deletedAny = true;
    }

    // iOS
    final runnerDir = Directory(p.join(root, 'ios/Runner'));
    if (runnerDir.existsSync()) {
      for (final entity in runnerDir.listSync()) {
        if (entity is File && p.basename(entity.path).startsWith('GoogleService-Info') && p.basename(entity.path).endsWith('.plist')) {
          entity.deleteSync();
          log.info('🗑️ Deleted ${p.relative(entity.path, from: root)}');
          deletedAny = true;
        }
      }
    }

    // Flutter
    final libDir = Directory(p.join(root, 'lib'));
    if (libDir.existsSync()) {
      for (final entity in libDir.listSync()) {
        if (entity is File && p.basename(entity.path).startsWith('firebase_options') && p.basename(entity.path).endsWith('.dart')) {
          entity.deleteSync();
          log.info('🗑️ Deleted ${p.relative(entity.path, from: root)}');
          deletedAny = true;
        }
      }
    }

    if (deletedAny) {
      log.success('✔ Firebase configuration files removed');
      // Also remove firebase_core dependency
      log.info('🗑️ Removing firebase_core dependency from pubspec.yaml...');
      Process.runSync('flutter', ['pub', 'remove', 'firebase_core'], runInShell: true);
    }
  }

  static void _restoreTests(String root, AppLogger log) {
    final testPath = p.join(root, 'test/widget_test.dart');
    final file = File(testPath);
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return;

    final nameRegex = RegExp(r'^name:\s*(.*)$', multiLine: true);
    final match = nameRegex.firstMatch(pubspec.readAsStringSync());
    if (match == null) return;
    final pkgName = match.group(1)!.trim();

    final flavorRegex = RegExp(
        "import 'package:$pkgName/main/main_.*?\\.dart';|import \"package:$pkgName/main/main_.*?\\.dart\";");

    if (flavorRegex.hasMatch(content)) {
      log.info('   🧹 Reverting test/widget_test.dart imports...');
      content = content.replaceAll(flavorRegex, "import 'package:$pkgName/main.dart';");
      file.writeAsStringSync(content);
    }
  }

  static void _restoreMainDart(String root, AppLogger log) {
    final mainPath = p.join(root, 'lib/main.dart');
    final mainFile = File(mainPath);

    if (mainFile.existsSync()) {
      log.info('🧹 De-integrating flavor logic from lib/main.dart...');
      final cleanedContent = _cleanContent(mainFile.readAsStringSync());
      mainFile.writeAsStringSync(cleanedContent);
    } else {
      // Look for a flavor main to recover user logic
      final flavors = ConfigService.getFlavors();
      File? flavorMain;

      // Try production flavor first
      final prod = ConfigService.getProductionFlavor();
      final prodFile = File(p.join(root, 'lib/main/main_$prod.dart'));
      if (prodFile.existsSync()) {
        flavorMain = prodFile;
      } else {
        // Try any main
        for (final f in flavors) {
          final fFile = File(p.join(root, 'lib/main/main_$f.dart'));
          if (fFile.existsSync()) {
            flavorMain = fFile;
            break;
          }
        }
      }

      if (flavorMain != null) {
        log.info('📝 Recovering logic from ${p.basename(flavorMain.path)}...');
        final cleanedContent = _cleanContent(flavorMain.readAsStringSync());
        mainFile.writeAsStringSync(cleanedContent);
      } else {
        log.info('📝 Restoring standard boilerplate lib/main.dart...');
        mainFile.writeAsStringSync(_boilerplateContent());
      }
    }
  }

  static String _cleanContent(String content) {
    final appConfigPath = ConfigService.getAppConfigPath();
    final configName = p.basename(appConfigPath);

    var cleaned = content;

    // Remove import
    cleaned = cleaned.replaceAll(RegExp(r"import '.*?" + configName + r"';\n?"), '');

    // Remove AppConfig.init call
    cleaned = cleaned.replaceAll(RegExp(r"\s*AppConfig\.init\(.*?\);"), '');

    // Remove flavor detection logic in main
    cleaned = cleaned.replaceAll(RegExp(r"\s*const flavorString = String\.fromEnvironment\('FLAVOR'\);"), '');
    cleaned = cleaned.replaceAll(RegExp(r"\s*final flavor = _getFlavor\(flavorString\);"), '');

    // Remove Firebase imports
    cleaned = cleaned.replaceAll(RegExp(r"import 'package:firebase_core/firebase_core\.dart';\n?"), '');
    cleaned = cleaned.replaceAll(RegExp(r"import 'firebase_options_.*?\.dart' as .*?;\n?"), '');
    cleaned = cleaned.replaceAll(RegExp(r"import '\.\./firebase_options_.*?\.dart';\n?"), '');

    // Remove Firebase.initializeApp blocks
    final firebaseInitRegex = RegExp(r'\s*WidgetsFlutterBinding\.ensureInitialized\(\);\s*await Firebase\.initializeApp\(.*?\);', dotAll: true);
    cleaned = cleaned.replaceAll(firebaseInitRegex, '');

    // 4. Remove _getFlavor helper function
    final helperSig = 'Flavor _getFlavor(String flavor)';
    final helperIndex = cleaned.indexOf(helperSig);
    if (helperIndex != -1) {
      final openBraceIndex = cleaned.indexOf('{', helperIndex);
      if (openBraceIndex != -1) {
        final closingBraceIndex = _findMatchingBrace(cleaned, openBraceIndex);
        if (closingBraceIndex != -1) {
          // Find preceding newlines to clean up
          var startToRemove = helperIndex;
          while (startToRemove > 0 && 
                 (cleaned[startToRemove - 1] == '\n' || cleaned[startToRemove - 1] == '\r' || cleaned[startToRemove - 1] == ' ')) {
            startToRemove--;
          }
          cleaned = cleaned.replaceRange(startToRemove, closingBraceIndex + 1, '');
        }
      }
    }

    // Final pass for excessive newlines
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return cleaned.trim() + '\n';
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

  static String _boilerplateContent() {
    return '''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '\$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
''';
  }
}
