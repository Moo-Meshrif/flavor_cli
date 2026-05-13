import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/flavor_config.dart';
import '../services/android_service.dart';
import '../services/config_service.dart';
import '../services/file_service.dart';
import '../services/ios_service.dart';
import '../services/pubspec_service.dart';
import '../services/runtime_config_service.dart';
import '../services/dependency_service.dart';
import '../utils/logger.dart';
import '../commands/firebase_command.dart';
import '../utils/exceptions.dart';

class SetupRunner {
  final AppLogger _log;

  SetupRunner({AppLogger? logger}) : _log = logger ?? AppLogger();

  Future<void> run(FlavorConfig config,
      {String? newFlavor, bool skipFirebase = false}) async {
    try {
      final adapter = RuntimeConfigService();

      // 1. Save Config as the source of truth
      ConfigService.save(config);
      _log.info('📦 Running setup with flavors: ${config.flavors.join(", ")}');

      // 2. File Structure
      FileService.createStructure();

      // Generate AppConfig via adapter (JSON or ENV variant)
      adapter.generateAppConfig(config);

      // Generate flavor-specific runtime files (no-op for JSON, .env files for ENV)
      adapter.generateFlavorFiles(config);

      // Ensure dependencies and assets are configured in pubspec.yaml
      _ensureDependencies(config);

      if (config.generateScripts) {
        FileService.createScripts();
      }
      FileService.updateTests();

      String? oldMainContent;
      if (config.useSeparateMains) {
        final mainFile = File(p.join(ConfigService.root, 'lib/main.dart'));
        if (mainFile.existsSync()) {
          oldMainContent = mainFile.readAsStringSync();
          _log.info(
              '📝 Preserving your existing main.dart content into the production flavor...');
        }
      }

      bool overwriteMains = true;
      final existingMains =
          _checkExistingMains(config.flavors, config.useSeparateMains);

      if (existingMains.isNotEmpty) {
        overwriteMains = false;
      }

      // Create main files using adapter-generated boilerplate
      _createMainFiles(config, adapter,
          overwrite: overwriteMains, productionContent: oldMainContent);

      // If we are not in full overwrite mode OR we preserved old content,
      // integrate the files to ensure they have AppConfig.init and proper imports.
      if (!overwriteMains || oldMainContent != null) {
        if (config.useSeparateMains) {
          for (final flavor in config.flavors) {
            final path =
                p.join(ConfigService.root, 'lib/main/main_$flavor.dart');
            adapter.integrateMainFile(path, config, flavor: flavor);
          }
        } else {
          final path = p.join(ConfigService.root, 'lib/main.dart');
          adapter.integrateMainFile(path, config);
        }
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
        // Also clean up adapter-specific orphan files
        adapter.cleanupFlavorFiles(orphans.toList(), config);
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

      FileService.updateVSCodeLaunchConfig();

      // Ensure Firebase entry points are synchronized (silently)
      if (ConfigService.hasFirebaseFiles()) {
        FileService.injectFirebase(separate: config.useSeparateMains);
      }

      // Check and re-initialize Firebase if necessary
      if (!skipFirebase) {
        await FirebaseCommand.checkAndReinit(_log, targetFlavor: newFlavor);
      }

      FileService.updateVSCodeLaunchConfig(); // Call again after Firebase just in case
    } catch (e) {
      if (e is CliException && e.isLogged) {
        rethrow;
      }
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
        'flavor_cli.yaml',
        'ios/Runner.xcodeproj',
        'ios/Flutter',
        'android/app/build.gradle',
        'android/app/build.gradle.kts',
        'android/app/src/main/AndroidManifest.xml',
        'lib',
        'test/widget_test.dart',
        'firebase.json',
      ];

      // Include .env files in backup
      final config = ConfigService.load();
      for (final flavor in config.flavors) {
        pathsToBackup.add('.env.$flavor');
      }
      pathsToBackup.add('.env.$oldFlavor'); // ensure old file is backed up

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
      final isProduction = oldFlavor == config.productionFlavor;

      ConfigService.renameFlavor(oldFlavor, newFlavor);
      if (isProduction) {
        ConfigService.save(
            ConfigService.load().copyWith(productionFlavor: newFlavor));
      }

      final updatedConfig = ConfigService.load();
      final adapter = RuntimeConfigService();

      // Rename adapter-specific files (e.g., .env.<old> -> .env.<new>)
      adapter.renameFlavorFiles(oldFlavor, newFlavor, updatedConfig);
      adapter.generateAppConfig(updatedConfig);

      FileService.renameFlavor(
          oldName: oldFlavor, newName: newFlavor, log: _log);

      AndroidService.setupFlavors(config: updatedConfig, logger: _log);
      IOSService.setupSchemes(config: updatedConfig, logger: _log);

      FileService.updateTests();

      final orphans = FileService.getOrphanedFlavors(updatedConfig.flavors);
      if (orphans.isNotEmpty) {
        FileService.cleanupFlavors(orphans.toList());
        adapter.cleanupFlavorFiles(orphans.toList(), updatedConfig);
      }

      FileService.updateVSCodeLaunchConfig();
      FileService.injectFirebase(separate: updatedConfig.useSeparateMains);

      // Clean up temp dir on success
      tempDir.deleteSync(recursive: true);
      _log.success(
          '✅ Flavor "$oldFlavor" successfully renamed to "$newFlavor".');

      await FirebaseCommand.checkAndReinit(_log, targetFlavor: newFlavor);
    } catch (e) {
      _log.error('❌ Rename failed: $e');
      _log.info(
          '🔄 Initiating automatic rollback to preserve project integrity...');

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

      _log.success(
          '✔ Rollback successful. Project restored to "$oldFlavor" state.');
      rethrow;
    }
  }

  void reset([bool excludeValidation = false]) {
    final log = _log;
    final root = ConfigService.root;
    final config = ConfigService.load(excludeValidation);

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
    _restoreMainDart(root, log, config);

    // 3. File Cleanup
    final allPossibleOrphans = FileService.getOrphanedFlavors([]);
    if (allPossibleOrphans.isNotEmpty) {
      log.info(
          '🗑️ Removing orphaned flavor files: ${allPossibleOrphans.join(", ")}');
      FileService.cleanupFlavors(allPossibleOrphans.toList());
    }

    _cleanupEnvFiles(root, config, log);

    final configFile = File(p.join(root, config.appConfigPath));
    if (configFile.existsSync()) {
      configFile.deleteSync();
    }

    final scriptsDir = Directory(p.join(root, 'scripts'));
    if (scriptsDir.existsSync()) {
      scriptsDir.deleteSync(recursive: true);
    }

    final flavorConfigFile = File(p.join(root, 'flavor_cli.yaml'));
    if (flavorConfigFile.existsSync()) {
      flavorConfigFile.deleteSync();
    }

    _cleanupFirebaseFiles(root, log);
    FileService.removeVSCodeLaunchConfig();

    _cleanupEmptyDir(p.join(root, 'lib/main'), log);
    _cleanupEmptyDir(p.join(root, p.dirname(config.appConfigPath)), log);

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

    log.info('🎨 Formatting code...');
    try {
      Process.runSync('dart', ['format', 'lib'], runInShell: true);
    } catch (_) {}

    log.success('✅ Project reset complete. App is back to its original state.');
  }

  void _cleanupEnvFiles(String root, FlavorConfig config, AppLogger log) {
    log.info('🗑️ Removing .env files...');
    for (final flavor in config.flavors) {
      final envFile = File(p.join(root, '.env.$flavor'));
      if (envFile.existsSync()) {
        envFile.deleteSync();
        log.info('   ✔ Deleted .env.$flavor');
      }
    }

    // Also clean up any stray .env.* files
    final projectDir = Directory(root);
    if (projectDir.existsSync()) {
      for (final entity in projectDir.listSync()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.startsWith('.env.') && name != '.env.example') {
            entity.deleteSync();
          }
        }
      }
    }

    // Remove flutter_dotenv from pubspec if it was auto-added
    if (PubspecService.hasDependency('flutter_dotenv')) {
      PubspecService.removeDependency('flutter_dotenv');
      log.info('   ✔ Removed flutter_dotenv from pubspec.yaml');
    }

    // Remove .env asset entries from pubspec
    final envAssets = PubspecService.getAssetsWithPrefix('.env.');
    if (envAssets.isNotEmpty) {
      PubspecService.removeAssets(envAssets);
      log.info('   ✔ Removed .env asset entries from pubspec.yaml');
    }
  }

  void _createMainFiles(
    FlavorConfig config,
    RuntimeConfigService adapter, {
    bool overwrite = true,
    String? productionContent,
  }) {
    final root = ConfigService.root;
    final useSeparate = config.useSeparateMains;
    final flavors = config.flavors;
    final prodFlavor = config.productionFlavor;

    if (useSeparate) {
      for (final flavor in flavors) {
        final file = File(p.join(root, 'lib/main/main_$flavor.dart'));
        if (!overwrite && file.existsSync()) continue;

        if (flavor == prodFlavor && productionContent != null) {
          file.writeAsStringSync(productionContent);
        } else {
          file.writeAsStringSync(
              adapter.generateMainBoilerplate(flavor, config));
        }
      }
    } else {
      final file = File(p.join(root, 'lib/main.dart'));
      if (!overwrite && file.existsSync()) return;
      file.writeAsStringSync(adapter.generateSingleMainBoilerplate(config));
    }
  }

  void _ensureDependencies(FlavorConfig config) {
    DependencyService.ensureEnvDependencies(config, _log);
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
        if (File('lib/main/main_$f.dart').existsSync()) {
          existing.add('lib/main/main_$f.dart');
        }
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

  void _cleanupEmptyDir(String path, AppLogger log) {
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

  void _restoreMainDart(String root, AppLogger log, FlavorConfig config) {
    final mainPath = p.join(root, 'lib/main.dart');
    final mainFile = File(mainPath);

    // Try to restore from production main if separate mains were used
    if (config.useSeparateMains) {
      final prodMainPath =
          p.join(root, 'lib/main/main_${config.productionFlavor}.dart');
      final prodMainFile = File(prodMainPath);
      if (prodMainFile.existsSync()) {
        mainFile
            .writeAsStringSync(_cleanContent(prodMainFile.readAsStringSync()));
        return;
      }
    }

    if (mainFile.existsSync()) {
      mainFile.writeAsStringSync(_cleanContent(mainFile.readAsStringSync()));
    } else {
      mainFile.writeAsStringSync(_boilerplateContent());
    }
  }

  String _cleanContent(String content) {
    var cleaned = FileService.removeFirebaseFromContent(content);

    // Remove AppConfig imports
    cleaned = cleaned.replaceAll(
        RegExp(r'''^\s*import\s+['"].*?app_config\.dart['"];\s*\n?''',
            multiLine: true),
        '');

    // Remove flutter_dotenv import
    cleaned = cleaned.replaceAll(
        RegExp(
            r'''^\s*import\s+['"]package:flutter_dotenv/flutter_dotenv\.dart['"];\s*\n?''',
            multiLine: true),
        '');

    // Remove AppConfig.init and flavor variable setup
    cleaned = cleaned.replaceAll(
        RegExp(r'^\s*AppConfig\.init\(.*?\);\s*\n?', multiLine: true), '');
    cleaned = cleaned.replaceAll(
        RegExp(
            r"^\s*const flavorString = String\.fromEnvironment\('FLAVOR'\);\s*\n?",
            multiLine: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'^\s*final flavor = _getFlavor\(flavorString\);\s*\n?',
            multiLine: true),
        '');

    // Remove dotenv.load calls
    cleaned = cleaned.replaceAll(
        RegExp(r'^\s*await dotenv\.load\(.*?\);\s*\n?', multiLine: true), '');

    // Remove _getFlavor helper function
    final getFlavorRegex = RegExp(
        r'^Flavor _getFlavor\(String flavor\) \{[\s\S]*?\}\s*\}[\t ]*\n?',
        multiLine: true);
    cleaned = cleaned.replaceAll(getFlavorRegex, '');

    // Fix main() signature if it was made async but no longer needs to be
    if (!cleaned.contains('await ') && !cleaned.contains('async')) {
      cleaned = cleaned.replaceFirst(
          RegExp(r'(Future<void>|void) main\s*\(\s*\) async\s*\{'),
          'void main() {');
    }

    // Cleanup multiple newlines
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
