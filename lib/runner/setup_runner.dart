import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/flavor_config.dart';
import '../services/android_service.dart';
import '../services/config_service.dart';
import '../services/file_service.dart';
import '../services/ios_service.dart';
import '../utils/logger.dart';
import '../commands/firebase_command.dart';

class SetupRunner {
  final AppLogger _log;

  SetupRunner({AppLogger? logger}) : _log = logger ?? AppLogger();

  Future<void> run(FlavorConfig config) async {
    try {
      // 1. Save Config as the source of truth
      ConfigService.save(config);
      _log.info('📦 Running setup with flavors: ${config.flavors.join(", ")}');

      // 2. File Structure
      FileService.createStructure();
      FileService.createAppConfig(overwrite: true);
      FileService.createScripts();
      FileService.updateTests();

      bool overwriteMains = true;
      final existingMains =
          _checkExistingMains(config.flavors, config.useSeparateMains);

      if (existingMains.isNotEmpty) {
        // If we are just regenerating in the background, we shouldn't prompt if already set up.
        // But if there's confusion, prompt.
        // Actually, assuming SetupRunner is called headless, we trust existing files.
        overwriteMains = false;
      }

      if (overwriteMains || existingMains.isEmpty) {
        FileService.createMainFiles(overwrite: overwriteMains);
      } else {
        FileService.integrateMainFiles(
            flavors: config.flavors, separate: config.useSeparateMains);
      }

      // 3. Platform Setup
      _safe(() => AndroidService.setupFlavors(config: config, logger: _log),
          'Android flavors');
      _safe(() => IOSService.setupSchemes(config: config, logger: _log),
          'iOS setup');

      // 4. Cleanup
      final orphans = FileService.getOrphanedFlavors(config.flavors);
      if (orphans.isNotEmpty) {
        FileService.cleanupFlavors(orphans.toList());
        for (final orphan in orphans) {
          _safe(() => IOSService.removeFlavorSchemes(orphan, logger: _log),
              'iOS cleanup for $orphan');
        }
        _log.info('✔ Orphaned files cleaned up (${orphans.join(", ")})');
      }

      // Cleanup main files based on strategy
      if (config.useSeparateMains) {
        final rootMain = File(p.join(ConfigService.root, 'lib/main.dart'));
        if (rootMain.existsSync()) {
          rootMain.deleteSync();
        }
      } else {
        final mainDir = Directory(p.join(ConfigService.root, 'lib/main'));
        if (mainDir.existsSync()) {
          mainDir.deleteSync(recursive: true);
        }
      }

      _log.success('✅ Flavor system synchronized successfully!');

      // Check and re-initialize Firebase if necessary
      await FirebaseCommand.checkAndReinit(_log);

      FileService.updateVSCodeLaunchConfig();
    } catch (e) {
      _log.error('❌ Failed to synchronize flavors: $e');
      rethrow;
    }
  }

  Future<void> replaceFlavor({
    required String oldFlavor,
    required String newFlavor,
  }) async {
    final root = ConfigService.root;
    final tempDir = Directory.systemTemp.createTempSync('flavor_cli_backup_');
    _log.info('📸 Creating pre-flight snapshot...');

    try {
      // 1. SNAPSHOT
      final pathsToBackup = [
        '.flavor_cli.json',
        'ios/Runner.xcodeproj',
        'ios/Flutter',
        'android/app/build.gradle',
        'android/app/build.gradle.kts',
        'android/app/src/main/AndroidManifest.xml',
        'lib',
        'test/widget_test.dart',
        'firebase.json',
      ];

      for (final relativePath in pathsToBackup) {
        final src = FileSystemEntity.isDirectorySync(p.join(root, relativePath))
            ? Directory(p.join(root, relativePath))
            : File(p.join(root, relativePath));

        if (!src.existsSync()) continue;

        final destPath = p.join(tempDir.path, relativePath);
        if (src is Directory) {
          _copyDirectory(src, Directory(destPath));
        } else if (src is File) {
          File(destPath).createSync(recursive: true);
          src.copySync(destPath);
        }
      }

      // 2. ATTEMPT RENAME SEQUENCE
      final config = ConfigService.load();
      final isProduction = oldFlavor == config.productionFlavor;

      ConfigService.renameFlavor(oldFlavor, newFlavor);
      if (isProduction) {
        ConfigService.save(
            ConfigService.load().copyWith(productionFlavor: newFlavor));
      }

      final updatedConfig = ConfigService.load();

      FileService.renameFlavor(
          oldName: oldFlavor, newName: newFlavor, log: _log);

      AndroidService.setupFlavors(config: updatedConfig, logger: _log);
      IOSService.setupSchemes(config: updatedConfig, logger: _log);

      FileService.updateTests();

      final orphans = FileService.getOrphanedFlavors(updatedConfig.flavors);
      if (orphans.isNotEmpty) {
        FileService.cleanupFlavors(orphans.toList());
      }

      FileService.updateVSCodeLaunchConfig();
      FileService.injectFirebase(separate: updatedConfig.useSeparateMains);

      // Clean up temp dir on success
      tempDir.deleteSync(recursive: true);
      _log.success(
          '✅ Flavor "$oldFlavor" successfully renamed to "$newFlavor".');

      await FirebaseCommand.checkAndReinit(_log, targetFlavor: newFlavor);
    } catch (e) {
      _log.error(
          '❌ Execution failed during rename. Rolling back files to snapshot...');

      // 3. ROLLBACK FROM SNAPSHOT
      for (final entity in tempDir.listSync(recursive: true)) {
        if (entity is File) {
          final relativePath = p.relative(entity.path, from: tempDir.path);
          final targetFile = File(p.join(root, relativePath));
          targetFile.createSync(recursive: true);
          entity.copySync(targetFile.path);
        }
      }

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}

      _log.info('✔ Rollback complete. Safely reverted to original state.');
      rethrow;
    }
  }

  void reset() {
    final log = _log;
    final root = ConfigService.root;
    final config = ConfigService.load();

    log.info('🧹 Starting full project reset...');

    // 1. Platform Reset
    try {
      AndroidService.reset(config: config, logger: log);
    } catch (e) {
      log.warn('⚠️ Android reset issue: $e');
    }

    try {
      IOSService.reset(config: config, logger: log);
    } catch (e) {
      log.warn('⚠️ iOS reset issue: $e');
    }

    // 2. Main Dart Restoration
    _restoreMainDart(root, log);

    // 3. File Cleanup
    final allPossibleOrphans = FileService.getOrphanedFlavors([]);
    if (allPossibleOrphans.isNotEmpty) {
      log.info(
          '🗑️ Removing orphaned flavor files: ${allPossibleOrphans.join(", ")}');
      FileService.cleanupFlavors(allPossibleOrphans.toList());
    }

    final configFile = File(p.join(root, config.appConfigPath));
    if (configFile.existsSync()) {
      configFile.deleteSync();
    }

    final scriptsDir = Directory(p.join(root, 'scripts'));
    if (scriptsDir.existsSync()) {
      scriptsDir.deleteSync(recursive: true);
    }

    final flavorConfigFile = File(p.join(root, '.flavor_cli.json'));
    if (flavorConfigFile.existsSync()) {
      flavorConfigFile.deleteSync();
    }

    _cleanupFirebaseFiles(root, log);
    FileService.removeVSCodeLaunchConfig();

    _cleanupEmptyParent(p.join(root, 'lib/main'), log);
    _cleanupEmptyParent(p.join(root, p.dirname(config.appConfigPath)), log);

    _restoreTests(root, log);

    log.info('🧹 Finalizing: flutter clean && flutter pub get...');
    try {
      Process.runSync('flutter', ['clean'], runInShell: true);
      Process.runSync('flutter', ['pub', 'get'], runInShell: true);
    } catch (e) {
      log.warn('⚠️ Flutter cleanup issue: $e');
    }

    try {
      IOSService.syncPods(logger: log);
    } catch (e) {
      log.warn('⚠️ CocoaPods sync issue: $e');
    }

    log.success('✅ Project reset complete. App is back to its original state.');
  }

  void _safe(Function action, String label) {
    try {
      action();
    } catch (e) {
      _log.warn('⚠️ $label encountered an issue: $e');
    }
  }

  List<String> _checkExistingMains(List<String> flavors, bool separate) {
    final existing = <String>[];
    if (separate) {
      for (final f in flavors) {
        if (File('lib/main/main_$f.dart').existsSync())
          existing.add('lib/main/main_$f.dart');
      }
    } else {
      if (File('lib/main.dart').existsSync()) existing.add('lib/main.dart');
    }
    return existing;
  }

  void _copyDirectory(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    source.listSync(recursive: false).forEach((var entity) {
      if (entity is Directory) {
        var newDirectory = Directory(
            p.join(destination.absolute.path, p.basename(entity.path)));
        newDirectory.createSync();
        _copyDirectory(entity.absolute, newDirectory);
      } else if (entity is File) {
        entity.copySync(p.join(destination.path, p.basename(entity.path)));
      }
    });
  }

  void _cleanupEmptyParent(String path, AppLogger log) {
    final dir = Directory(path);
    if (dir.existsSync() && dir.listSync().isEmpty) {
      dir.deleteSync();
    }
  }

  void _cleanupFirebaseFiles(String root, AppLogger log) {
    var deletedAny = false;
    for (final file in ['firebase.json', '.firebaserc']) {
      final f = File(p.join(root, file));
      if (f.existsSync()) {
        f.deleteSync();
        deletedAny = true;
      }
    }

    final androidSrc = Directory(p.join(root, 'android/app/src'));
    if (androidSrc.existsSync()) {
      for (final entity in androidSrc.listSync()) {
        if (entity is Directory) {
          final jsonFile = File(p.join(entity.path, 'google-services.json'));
          if (jsonFile.existsSync()) jsonFile.deleteSync();
        }
      }
    }
    final baseAndroidJson =
        File(p.join(root, 'android/app/google-services.json'));
    if (baseAndroidJson.existsSync()) {
      baseAndroidJson.deleteSync();
    }

    final runnerDir = Directory(p.join(root, 'ios/Runner'));
    if (runnerDir.existsSync()) {
      for (final entity in runnerDir.listSync()) {
        if (entity is File &&
            p.basename(entity.path).startsWith('GoogleService-Info')) {
          entity.deleteSync();
        }
      }
    }

    final libDir = Directory(p.join(root, 'lib'));
    if (libDir.existsSync()) {
      for (final entity in libDir.listSync()) {
        if (entity is File &&
            p.basename(entity.path).startsWith('firebase_options')) {
          entity.deleteSync();
        }
      }
    }

    if (deletedAny) {
      Process.runSync('flutter', ['pub', 'remove', 'firebase_core'],
          runInShell: true);
    }
  }

  void _restoreTests(String root, AppLogger log) {
    final testPath = p.join(root, 'test/widget_test.dart');
    final file = File(testPath);
    if (!file.existsSync()) return;
    var content = file.readAsStringSync();
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return;
    final match = RegExp(r'^name:\s*(.*)$', multiLine: true)
        .firstMatch(pubspec.readAsStringSync());
    if (match == null) return;
    final pkgName = match.group(1)!.trim();
    final flavorRegex = RegExp(
        "import 'package:$pkgName/main/main_.*?\\.dart';|import \"package:$pkgName/main/main_.*?\\.dart\";");
    if (flavorRegex.hasMatch(content)) {
      content = content.replaceAll(
          flavorRegex, "import 'package:$pkgName/main.dart';");
      file.writeAsStringSync(content);
    }
  }

  void _restoreMainDart(String root, AppLogger log) {
    final mainPath = p.join(root, 'lib/main.dart');
    final mainFile = File(mainPath);

    if (mainFile.existsSync()) {
      mainFile.writeAsStringSync(_cleanContent(mainFile.readAsStringSync()));
    } else {
      mainFile.writeAsStringSync(_boilerplateContent());
    }
  }

  String _cleanContent(String content) {
    var cleaned = content;

    // 1. Remove Firebase init (multi-line)
    final firebaseInitRegex = RegExp(
        r'^\s*WidgetsFlutterBinding\.ensureInitialized\(\);[\s\S]*?await Firebase\.initializeApp\(.*?\);[\t ]*\n?',
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

    // 3. Remove AppConfig imports
    cleaned = cleaned.replaceAll(
        RegExp(r'''^\s*import\s+['"].*?app_config\.dart['"];[\t ]*\n?''',
            multiLine: true),
        '');

    // 4. Remove AppConfig.init and flavor variable setup
    cleaned = cleaned.replaceAll(
        RegExp(r'^\s*AppConfig\.init\(.*?\);[\t ]*\n?', multiLine: true), '');
    cleaned = cleaned.replaceAll(
        RegExp(
            r"^\s*const flavorString = String\.fromEnvironment\('FLAVOR'\);[\t ]*\n?",
            multiLine: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'^\s*final flavor = _getFlavor\(flavorString\);[\t ]*\n?',
            multiLine: true),
        '');

    // 5. Remove _getFlavor helper function (matches the whole block including the switch)
    final getFlavorRegex = RegExp(
        r'^Flavor _getFlavor\(String flavor\) \{[\s\S]*?\}\s*\}[\t ]*\n?',
        multiLine: true);
    cleaned = cleaned.replaceAll(getFlavorRegex, '');

    // 6. Fix main() signature if it was made async for Firebase but no longer needs to be
    if (!cleaned.contains('await ')) {
      cleaned = cleaned.replaceFirst(
          RegExp(r'void main\s*\(\s*\) async\s*\{'), 'void main() {');
    }

    // 7. Cleanup multiple newlines
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return cleaned.trim() + '\n';
  }

  String _boilerplateContent() {
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
      home: const Scaffold(body: Center(child: Text("App"))),
    );
  }
}
''';
  }
}
