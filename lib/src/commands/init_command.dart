import 'dart:io';
import 'package:path/path.dart' as p;
import '../services/file_service.dart';
import '../services/android_service.dart';
import '../services/ios_service.dart';
import '../services/config_service.dart';
import '../utils/logger.dart';
import '../utils/validation.dart';
import 'firebase_command.dart';

class InitCommand {
  final AppLogger _log;

  InitCommand({AppLogger? logger}) : _log = logger ?? AppLogger();

  Future<void> execute() async {
    if (!ConfigService.isValidProject(_log)) return;

    _log.info('🚀 Welcome to Flavor CLI! Let\'s set up your environment.');

    // 1. Choose flavors
    var flavorSelection = _log.chooseOne(
      '👉 Which flavor setup do you need ?',
      choices: [
        'dev, prod',
        'dev, stage, prod',
        'Enter manually',
      ],
    );

    List<String> flavors;
    while (true) {
      if (flavorSelection == 'Enter manually') {
        final input = _log.prompt(
          '👉 List your flavors (comma separated)',
          defaultValue: 'dev, stage, prod',
        );
        flavors = input
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();
      } else {
        flavors = flavorSelection
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .toList();
      }

      bool allFlavorsValid = true;
      for (final flavor in flavors) {
        if (!ValidationUtils.isValidIdentifier(flavor)) {
          _log.error(
              '❌ Invalid flavor name: "$flavor". Must be a valid Dart identifier (start with letter, no spaces, no special characters).');
          allFlavorsValid = false;
        }
      }

      if (flavors.length < 2) {
        _log.error(
            '❌ Error: You need at least 2 flavors to use this tool (e.g., dev and prod).');
        allFlavorsValid = false;
      }

      if (allFlavorsValid) break;

      if (flavorSelection != 'Enter manually') {
        flavorSelection = 'Enter manually';
      }
      _log.info('Please try again.');
    }

    // 2. Choose fields
    final fields = <String, String>{};
    while (true) {
      final fieldInput = _log.prompt(
        '👉 What variables should your AppConfig have ?',
        defaultValue: 'String baseUrl, bool debug',
      );

      final parts = fieldInput.split(',').map((e) => e.trim()).toList();
      bool allValid = true;

      for (var part in parts) {
        if (part.isEmpty) continue;
        final entry = part.split(' ');
        if (entry.length != 2) {
          _log.error('❌ Invalid format: "$part". Use "Type Name"');
          allValid = false;
          break;
        }
        final type = entry[0];
        final name = entry[1];

        // Basic type validation
        const validTypes = ['String', 'int', 'bool', 'double'];
        if (!validTypes.contains(type)) {
          _log.error('❌ Invalid type: "$type". Use: String, int, bool, double');
          allValid = false;
          break;
        }

        if (!ValidationUtils.isValidIdentifier(name)) {
          _log.error(
              '❌ Invalid variable name: "$name". Must be a valid Dart identifier.');
          allValid = false;
          break;
        }

        fields[name] = type;
      }

      if (allValid && fields.isNotEmpty) break;
      _log.info('Please try again.');
    }

    // 3. Choose AppConfig path
    var appConfigPath = _log.prompt(
      '👉 Where should AppConfig be created ?',
      defaultValue: 'lib/core/config/app_config.dart',
    );

    // Path sanitization
    appConfigPath = appConfigPath.trim();
    if (appConfigPath.startsWith('Example: ')) {
      appConfigPath = appConfigPath.replaceFirst('Example: ', '');
    }
    if (!appConfigPath.endsWith('.dart')) {
      appConfigPath = p.join(appConfigPath, 'app_config.dart');
    }

    // 4. Choose Main strategy
    final strategy = _log.chooseOne(
      '👉 Which main strategy do you prefer ?',
      choices: [
        'Separate main files per flavor (e.g., main_dev.dart)',
        'Single main file for all flavors',
      ],
    );
    final useSeparateMains = strategy.startsWith('Separate');

    // 5. App Name
    final detectedName = _detectAppName();
    final appName = _log.prompt(
      '👉 What is your App Name?',
      defaultValue: detectedName,
    );

    // 6. Identify Production Flavor
    String productionFlavor;
    if (flavors.contains('prod')) {
      productionFlavor = 'prod';
    } else if (flavors.contains('production')) {
      productionFlavor = 'production';
    } else {
      productionFlavor = _log.chooseOne(
        '👉 Which one is the production flavor?',
        choices: flavors,
      );
    }

    // 7. Production Package ID
    final detectedId = _detectPackageId();
    final packageId = _log.prompt(
      '👉 What is your Production Package ID? (Your unique App ID, e.g., com.example.app)',
      defaultValue: detectedId,
    );

    // 8. Package ID Strategy (Forced to separate IDs for better isolation)
    final useSuffix = true;

    try {
      // ========================
      // 2. CONFIG INIT
      // ========================
      ConfigService.init(
        flavors: flavors,
        fields: fields,
        appConfigPath: appConfigPath,
        useSeparateMains: useSeparateMains,
        appName: appName,
        productionFlavor: productionFlavor,
        useSuffix: useSuffix,
        packageId: packageId,
      );

      _log.info('📦 Initializing with flavors: ${flavors.join(", ")}');

      // ========================
      // 3. FILE STRUCTURE
      // ========================
      FileService.createStructure();

      FileService.createAppConfig(overwrite: true);
      FileService.createScripts();
      FileService.updateTests();

      bool overwriteMains = true;
      final existingMains = _checkExistingMains(flavors, useSeparateMains);
      if (existingMains.isNotEmpty) {
        final choice = _log.chooseOne(
          '👉 Main file(s) already exist. How would you like to proceed?',
          choices: [
            'Integrate setup into existing files',
            'Replace with flavor boilerplate',
          ],
        );

        if (choice == 'Integrate setup into existing files') {
          FileService.integrateMainFiles(
              flavors: flavors, separate: useSeparateMains);
          overwriteMains = false; // Already integrated
        } else {
          overwriteMains = true; // Replace
        }
      }

      if (overwriteMains || existingMains.isEmpty) {
        FileService.createMainFiles(overwrite: overwriteMains);
      }

      // ========================
      // 4. PLATFORM SETUP
      // ========================
      _safe(() => AndroidService.setupFlavors(logger: _log), 'Android flavors');
      _safe(() => IOSService.setupSchemes(logger: _log), 'iOS setup');

      // ========================
      // 6. CLEANUP
      // ========================
      final orphans = FileService.getOrphanedFlavors(flavors);
      if (orphans.isNotEmpty) {
        FileService.cleanupFlavors(orphans.toList());
        for (final orphan in orphans) {
          _safe(() => IOSService.removeFlavorSchemes(orphan, logger: _log),
              'iOS cleanup for $orphan');
        }
        _log.info('✔ Orphaned files cleaned up (${orphans.join(", ")})');
      }

      // Cleanup root main.dart if using separate mains
      if (useSeparateMains) {
        final rootMain = File(p.join(ConfigService.root, 'lib/main.dart'));
        if (rootMain.existsSync()) {
          rootMain.deleteSync();
          _log.info(
              '✔ Root lib/main.dart removed (using separate flavor mains)');
        }
      } else {
        // Cleanup lib/main directory if it exists
        final mainDir = Directory(p.join(ConfigService.root, 'lib/main'));
        if (mainDir.existsSync()) {
          mainDir.deleteSync(recursive: true);
          _log.info(
              '✔ lib/main directory removed (not needed for single main)');
        }
      }

      _log.success('✅ Flavor system initialized successfully!');

      // Check and re-initialize Firebase if necessary
      await FirebaseCommand.checkAndReinit(_log);

      FileService.updateVSCodeLaunchConfig();
    } catch (e) {
      _log.error('❌ Failed to initialize: $e');
    }
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
      if (File('lib/main.dart').existsSync()) {
        existing.add('lib/main.dart');
      }
    }
    return existing;
  }

  String _detectAppName() {
    // 1. Try Config
    try {
      final existingName = ConfigService.getAppName();
      if (existingName != 'MyApp') return existingName;
    } catch (_) {}

    // 2. Try Info.plist (if not already flavored)
    try {
      final plistPath = p.join(ConfigService.root, 'ios/Runner/Info.plist');
      final file = File(plistPath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        // More robust regex for CFBundleDisplayName
        final match = RegExp(
                r'<key>CFBundleDisplayName</key>\s*<string>([^$]*?)</string>',
                caseSensitive: false)
            .firstMatch(content);
        if (match != null) {
          final name = match.group(1)?.trim();
          if (name != null && name.isNotEmpty) return name;
        }

        // Fallback to CFBundleName
        final nameMatch = RegExp(
                r'<key>CFBundleName</key>\s*<string>([^$]*?)</string>',
                caseSensitive: false)
            .firstMatch(content);
        if (nameMatch != null) {
          final name = nameMatch.group(1)?.trim();
          if (name != null && name.isNotEmpty) return name;
        }
      }
    } catch (_) {}

    // 3. Try pubspec.yaml
    try {
      final pubspec = File(p.join(ConfigService.root, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final content = pubspec.readAsStringSync();
        final nameMatch =
            RegExp(r'^name:\s*(.*)$', multiLine: true).firstMatch(content);
        if (nameMatch != null) {
          final name = nameMatch.group(1)!.trim();
          // Capitalize first letter as it is usually a lowercase package name
          return name[0].toUpperCase() + name.substring(1);
        }
      }
    } catch (_) {}

    return 'MyApp';
  }

  String _detectPackageId() {
    final root = ConfigService.root;
    // 1. Try Android build.gradle.kts
    try {
      final ktsFile = File(p.join(root, 'android/app/build.gradle.kts'));
      if (ktsFile.existsSync()) {
        final content = ktsFile.readAsStringSync();
        final match =
            RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(content);
        if (match != null) return match.group(1)!;
      }
    } catch (_) {}

    // 2. Try Android build.gradle (Groovy)
    try {
      final groovyFile = File(p.join(root, 'android/app/build.gradle'));
      if (groovyFile.existsSync()) {
        final content = groovyFile.readAsStringSync();
        final match =
            RegExp(r'''applicationId\s+["']([^"']+)["']''').firstMatch(content);
        if (match != null) return match.group(1)!;
      }
    } catch (_) {}

    // 3. Try Config
    try {
      final config = ConfigService.load();
      final appId = config['android']?['application_id'];
      if (appId != null) return appId;
    } catch (_) {}

    return 'com.example.app';
  }
}
