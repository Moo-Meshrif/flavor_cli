// flavor_cli: added
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/flavor_config.dart';
import '../runner/setup_runner.dart';
import '../services/config_service.dart';
import '../utils/logger.dart';
import '../utils/validation.dart';
import '../utils/type_utils.dart';

class InitWizard {
  final AppLogger _log;

  InitWizard({AppLogger? logger}) : _log = logger ?? AppLogger();

  Future<void> execute() async {
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

    // 7. Base Package ID
    final detectedId = _detectPackageId();
    final packageId = _log.prompt(
      '👉 What is your Production Package ID? (Your unique App ID, e.g., com.example.app)',
      defaultValue: detectedId,
    );

    // 8. ID strategy
    final idStrategy = _log.chooseOne(
      '👉 Which package ID strategy do you prefer?',
      choices: [
        'Unique IDs per flavor (recommended) — appends .flavorName to non-production flavors',
        'Shared ID — all flavors use the same package ID',
      ],
    );
    final useSuffix = idStrategy.startsWith('Unique');

    // 9. Firebase
    FirebaseConfig? firebaseConfig;
    bool enableFirebase = ConfigService.hasFirebase();
    if (enableFirebase) {
      _log.info('✨ Firebase detected in project, enabling support.');
    } else {
      enableFirebase =
          _log.confirm('👉 Enable Firebase support?', defaultValue: false);
    }

    if (enableFirebase) {
      final List<String> strategyChoices;
      if (useSuffix) {
        strategyChoices = [
          'unique_id_multi_project',
          'unique_id_single_project',
        ];
      } else {
        strategyChoices = [
          'shared_id_single_project',
        ];
      }

      final strategy = strategyChoices.length > 1
          ? _log.chooseOne('👉 Which Firebase strategy do you prefer?',
              choices: strategyChoices)
          : strategyChoices.first;

      if (strategyChoices.length == 1) {
        _log.info(
            'ℹ️ Using Firebase strategy: $strategy (matches your "Shared ID" strategy)');
      }

      final projects = <String, String>{};
      if (strategy == 'unique_id_multi_project') {
        for (final flavor in flavors) {
          final projectId =
              _log.prompt('👉 Enter Firebase Project ID for flavor "$flavor":');
          projects[flavor] = projectId;
        }
      } else {
        final projectId = _log.prompt('👉 Enter your Firebase Project ID:');
        projects['all'] = projectId;
      }

      firebaseConfig = FirebaseConfig(
        strategy: strategy,
        projects: projects,
      );
    }

    // 10. Per-flavor field values
    final flavorValues = <String, Map<String, dynamic>>{};
    _log.info('\n📝 Now let\'s set the values for your variables per flavor:');

    for (final fieldName in fields.keys) {
      final type = fields[fieldName]!;
      _log.info('Variable: $fieldName ($type)');
      for (final flavor in flavors) {
        final defaultValue = TypeUtils.getDefaultValueForType(type);
        final input = _log
            .prompt('   → Value for $fieldName ($flavor):',
                defaultValue: defaultValue)
            .trim();
        final typedVal = TypeUtils.parseToType(type, input);
        flavorValues.putIfAbsent(flavor, () => {})[fieldName] = typedVal;
      }
    }
    _log.info('');

    // Create FlavorConfig using collected data
    final config = FlavorConfig(
      flavors: flavors,
      appName: appName,
      fields: fields,
      flavorValues: flavorValues,
      appConfigPath: appConfigPath,
      useSeparateMains: useSeparateMains,
      useSuffix: useSuffix,
      android: AndroidConfig(applicationId: packageId),
      ios: IosConfig(bundleId: packageId),
      productionFlavor: productionFlavor,
      firebase: firebaseConfig,
      generateScripts: false,
    );

    // Call SetupRunner
    await SetupRunner(logger: _log).run(config);
  }

  String _detectAppName() {
    try {
      final existingName = ConfigService.load().appName;
      if (existingName != 'MyApp') return existingName;
    } catch (_) {}

    try {
      final plistPath = p.join(ConfigService.root, 'ios/Runner/Info.plist');
      final file = File(plistPath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final match = RegExp(
                r'<key>CFBundleDisplayName</key>\s*<string>([^$]*?)</string>',
                caseSensitive: false)
            .firstMatch(content);
        if (match != null) {
          final name = match.group(1)?.trim();
          if (name != null && name.isNotEmpty) return name;
        }

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

    try {
      final pubspec = File(p.join(ConfigService.root, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final content = pubspec.readAsStringSync();
        final nameMatch =
            RegExp(r'^name:\s*(.*)$', multiLine: true).firstMatch(content);
        if (nameMatch != null) {
          final name = nameMatch.group(1)!.trim();
          return name[0].toUpperCase() + name.substring(1);
        }
      }
    } catch (_) {}

    return 'MyApp';
  }

  String _detectPackageId() {
    final root = ConfigService.root;
    try {
      final ktsFile = File(p.join(root, 'android/app/build.gradle.kts'));
      if (ktsFile.existsSync()) {
        final content = ktsFile.readAsStringSync();
        final match =
            RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(content);
        if (match != null) return match.group(1)!;
      }
    } catch (_) {}

    try {
      final groovyFile = File(p.join(root, 'android/app/build.gradle'));
      if (groovyFile.existsSync()) {
        final content = groovyFile.readAsStringSync();
        final match =
            RegExp(r'''applicationId\s+["']([^"']+)["']''').firstMatch(content);
        if (match != null) return match.group(1)!;
      }
    } catch (_) {}

    try {
      final config = ConfigService.load();
      return config.android.applicationId;
    } catch (_) {}

    return 'com.example.app';
  }
}
