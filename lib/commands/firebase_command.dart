import 'dart:io';
import 'package:path/path.dart' as p;
import '../services/config_service.dart';
import '../services/file_service.dart';
import '../models/flavor_config.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// Command to set up and configure Firebase for different flavors.
class FirebaseCommand {
  final AppLogger _log;
  final bool fromHook;

  /// Creates a new [FirebaseCommand] with an optional [logger].
  FirebaseCommand({AppLogger? logger, this.fromHook = false})
      : _log = logger ?? AppLogger();

  /// Executes the Firebase configuration process.
  /// If [targetFlavor] is provided, only that flavor is configured.
  Future<void> execute({String? targetFlavor}) async {
    if (!ConfigService.isValidProject(_log)) return;
    if (!ConfigService.requiresInitialized(_log)) return;

    var config = ConfigService.load();
    if (config.firebase == null) {
      final confirmed = _log.confirm(
        '🔥 No Firebase configuration found in flavor_cli.yaml. Would you like to set it up now?',
        defaultValue: true,
      );

      if (!confirmed) {
        _log.error('❌ Firebase setup cancelled.');
        return;
      }

      final firebaseConfig = _promptForFirebaseConfig(config);
      config = config.copyWith(firebase: firebaseConfig);
      ConfigService.save(config);
      _log.success('📝 Firebase configuration saved to flavor_cli.yaml');
    }

    // 1. Check flutterfire
    final hasFlutterFire = await _checkCommand('flutterfire');
    if (!hasFlutterFire) {
      _log.error('❌ flavor_cli: flutterfire CLI not found');
      _log.info(
          '   → install it with: dart pub global activate flutterfire_cli');
      return;
    }

    final flavors = targetFlavor != null ? [targetFlavor] : config.flavors;
    final strategy = config.firebase!.strategy;
    final projects = config.firebase!.projects;
    final useSuffix = config.useSuffix;
    final prodFlavor = config.productionFlavor;
    final baseId = config.android.applicationId;
    final useSeparate = config.useSeparateMains;

    _log.info('🔥 Initializing Firebase (Strategy: $strategy)...');

    if (strategy == 'shared_id_single_project') {
      final projectId = projects['all'] ?? projects.values.first;
      await _runConfigure(
        projectId: projectId,
        packageId: baseId,
        out: 'lib/firebase_options.dart',
      );
      FileService.injectFirebase(separate: useSeparate);
    } else {
      // Per-flavor strategies
      for (final flavor in flavors) {
        final projectId = strategy == 'unique_id_multi_project'
            ? (projects[flavor] ?? projects.values.first)
            : (projects['all'] ?? projects.values.first);

        String packageId = baseId;
        if (useSuffix && flavor != prodFlavor) {
          packageId = '$baseId.$flavor';
        }

        await _runConfigure(
          projectId: projectId,
          packageId: packageId,
          out: 'lib/firebase_options_$flavor.dart',
          flavor: flavor,
        );

        if (useSeparate) {
          FileService.injectFirebase(separate: true, flavor: flavor);
        }
      }

      if (!useSeparate) {
        FileService.injectFirebase(separate: false);
      }
    }

    _log.info('📦 Adding firebase_core dependency...');
    final pubAddResult =
        await Process.run('flutter', ['pub', 'add', 'firebase_core']);
    if (pubAddResult.exitCode != 0) {
      _log.warn(
          '⚠️ Could not automatically add firebase_core to pubspec.yaml. Please add it manually.');
    }

    _log.success('✅ Firebase setup completed for all targets.');
    FileService.updateVSCodeLaunchConfig();
  }

  Future<void> _runConfigure({
    required String projectId,
    required String packageId,
    required String out,
    String? flavor,
  }) async {
    final label = flavor != null ? 'flavor "$flavor"' : 'project';
    _log.info(
        '🚀 Configuring $label ($packageId) against project $projectId...');

    final args = [
      'configure',
      '--project=$projectId',
      '--out=$out',
      '--ios-bundle-id=$packageId',
      '--android-package-name=$packageId',
      '--platforms=android,ios',
      '--yes',
    ];

    // We use inheritStdio to keep the interactive feel and colors,
    // but we'll check the exit code and logs if it fails.
    final result = await Process.start('flutterfire', args,
        mode: ProcessStartMode.inheritStdio);
    final exitCode = await result.exitCode;

    if (exitCode != 0) {
      _log.error('❌ flutterfire configure failed for $label');

      // Try to diagnose the error from firebase-debug.log
      final debugLog = File(p.join(ConfigService.root, 'firebase-debug.log'));
      if (debugLog.existsSync()) {
        final content = debugLog.readAsStringSync();
        if (content.contains('RESOURCE_EXHAUSTED') ||
            content.contains('Too many Apps on project')) {
          _log.warn('\n⚠️  FIREBASE APP LIMIT REACHED');
          _log.info(
              '   Your Firebase project "$projectId" has reached the maximum number of apps.');
          _log.info(
              '   This usually happens after multiple flavor renames, as old apps are not automatically deleted.');
          _log.info('\n👉 Solution:');
          _log.info(
              '   1. Go to Firebase Console: https://console.firebase.google.com/project/$projectId/settings/general');
          _log.info(
              '   2. Remove unused apps (e.g., old package names from previous flavor names).');
          _log.info('   3. Re-run this command.');

          final config = ConfigService.loadLenient();
          if (config != null) {
            final baseId = config.android.applicationId;
            final prodFlavor = config.productionFlavor;
            final useSuffix = config.useSuffix;

            final currentIds = <String>{};
            for (final f in config.flavors) {
              if (useSuffix && f != prodFlavor) {
                currentIds.add('$baseId.$f');
              } else {
                currentIds.add(baseId);
              }
            }
            // Always ensure base ID is included if not already
            currentIds.add(baseId);

            _log.info('\n💡 Note: Your current configuration uses:');
            for (final id in currentIds) {
              _log.info('      - $id');
            }
          }
        } else if (content.contains('PERMISSION_DENIED')) {
          _log.warn('\n⚠️  FIREBASE PERMISSION DENIED');
          _log.info(
              '   The account logged into Firebase CLI does not have access to project "$projectId".');
          _log.info('\n👉 Solution:');
          _log.info('   1. Run: firebase login');
          _log.info(
              '   2. Ensure you have "Editor" or "Owner" permissions on project "$projectId".');
        } else if (content.contains('Failed to create Android app') ||
            content.contains('AlreadyExists')) {
          _log.warn('\n⚠️  FIREBASE APP CONFLICT');
          _log.info(
              '   Firebase failed to register the Android app "$packageId".');
          _log.info(
              '   This often means the package ID is already registered in another Firebase project.');
          _log.info('\n👉 Solution:');
          _log.info(
              '   1. Check if "$packageId" is already used in a different Firebase project.');
          _log.info(
              '   2. If it is, you must remove it there before registering it in "$projectId".');
        } else {
          // General advice for other errors
          _log.info('\nℹ️  Check firebase-debug.log for more details.');
        }
      }

      throw CliException(
        'flutterfire configure failed for $label.',
        isLogged: true,
      );
    }
  }

  /// Prompts the user for Firebase configuration. Reused by [InitWizard]
  /// to avoid duplicating the strategy/project-ID prompt logic.
  static FirebaseConfig promptForFirebaseConfig(
      AppLogger log, FlavorConfig config) {
    final useSuffix = config.useSuffix;
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

    final selectedStrategy = strategyChoices.length > 1
        ? log.chooseOne('👉 Which Firebase strategy do you prefer?',
            choices: strategyChoices)
        : strategyChoices.first;

    if (strategyChoices.length == 1) {
      log.info(
          'ℹ️ Using Firebase strategy: $selectedStrategy (matches your "Shared ID" strategy)');
    }

    final projects = <String, String>{};
    if (selectedStrategy == 'unique_id_multi_project') {
      for (final flavor in config.flavors) {
        final projectId =
            log.prompt('👉 Enter Firebase Project ID for flavor "$flavor":');
        projects[flavor] = projectId;
      }
    } else {
      final projectId = log.prompt('👉 Enter your Firebase Project ID:');
      projects['all'] = projectId;
    }

    return FirebaseConfig(
      strategy: selectedStrategy,
      projects: projects,
    );
  }

  FirebaseConfig _promptForFirebaseConfig(FlavorConfig config) =>
      promptForFirebaseConfig(_log, config);

  Future<bool> _checkCommand(String command) async {
    try {
      final checkCmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(checkCmd, [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> checkAndReinit(AppLogger log,
      {String? targetFlavor}) async {
    if (!ConfigService.isInitialized()) return;
    final config = ConfigService.load();
    if (config.firebase == null) return;

    final hasFiles = ConfigService.hasFirebaseFiles();

    // 1. If configured but NO files exist, this is a fresh setup from init or a reset.
    if (!hasFiles) {
      final prompt = targetFlavor != null
          ? '\n🔥 Firebase configured but not integrated. Run Firebase setup for flavor "$targetFlavor" now?'
          : '\n🔥 Firebase configured but not integrated. Run Firebase setup for all flavors now?';

      if (log.confirm(prompt, defaultValue: true)) {
        await FirebaseCommand(logger: log, fromHook: true)
            .execute(targetFlavor: targetFlavor);
      }
      return;
    }

    // 2. If files DO exist, we follow the existing prompt/link logic.
    final strategy = config.firebase!.strategy;
    final isSharedId = strategy.contains('shared_id');

    // OPTIMIZATION: If using Shared ID and config already exists, just link it without prompting.
    if (isSharedId) {
      final optionsFile =
          File(p.join(ConfigService.root, 'lib/firebase_options.dart'));
      if (optionsFile.existsSync()) {
        log.info(
            'ℹ️ Firebase Shared ID strategy detected. Automatically linking configuration...');
        FileService.injectFirebase(
            separate: config.useSeparateMains, flavor: targetFlavor);
        return;
      }
    }

    final prompt = targetFlavor != null
        ? '\n🔥 Firebase detected. Re-run Firebase setup for flavor "$targetFlavor"?'
        : '\n🔥 Firebase detected. Re-run Firebase setup for all flavors?';

    if (log.confirm(prompt, defaultValue: true)) {
      await FirebaseCommand(logger: log, fromHook: true)
          .execute(targetFlavor: targetFlavor);
    }
  }
}
