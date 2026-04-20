import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../services/config_service.dart';
import '../services/file_service.dart';
import '../utils/logger.dart';

class FirebaseCommand {
  final AppLogger _log;
  final bool fromHook;

  FirebaseCommand({AppLogger? logger, this.fromHook = false})
      : _log = logger ?? AppLogger();

  Future<void> execute({String? targetFlavor}) async {
    if (!ConfigService.isValidProject(_log)) return;

    if (!ConfigService.isInitialized()) {
      _log.error('❌ This project is not initialized.');
      _log.info('Run "dart run flavor_cli init" first.');
      return;
    }

    if (targetFlavor != null) {
      _log.info('🔥 Initializing Firebase for flavor: $targetFlavor...');
    } else {
      _log.info('🔥 Initializing Firebase for all flavors...');
    }

    // 1. Check if flutterfire is installed and working
    final flutterfireStatus = await _verifyFlutterFire();
    if (flutterfireStatus == _CLIStatus.missing) {
      _log.warn('⚠️ FlutterFire CLI not found. Installing now...');
      final result = await Process.run(
          'dart', ['pub', 'global', 'activate', 'flutterfire_cli']);
      if (result.exitCode == 0) {
        _log.success('✅ FlutterFire CLI installed successfully!');
      } else {
        _log.error('❌ Failed to install FlutterFire CLI: ${result.stderr}');
        return;
      }
    } else if (flutterfireStatus == _CLIStatus.broken) {
      _log.warn(
          '⚠️ FlutterFire CLI is broken (likely due to SDK updates). Repairing now...');
      final result = await Process.run(
          'dart', ['pub', 'global', 'activate', 'flutterfire_cli']);
      if (result.exitCode == 0) {
        _log.success('✅ FlutterFire CLI repaired successfully!');
      } else {
        _log.error(
            '❌ Failed to repair FlutterFire CLI. Please run "dart pub global activate flutterfire_cli" manually.');
        return;
      }
    }

    // 2. Check firebase login
    final hasFirebase = await _checkCommand('firebase');
    if (!hasFirebase) {
      _log.error('❌ Firebase CLI (firebase-tools) not found.');
      _log.info('Please install it first: npm install -g firebase-tools');
      return;
    }

    _log.info('🛡️ Verifying Firebase authentication...');
    try {
      final authCheck = await _runWithTimeout('firebase', ['login:list']);
      if (authCheck.exitCode != 0 ||
          authCheck.stdout.toString().contains('No accounts found')) {
        _log.error('❌ You are not logged into Firebase.');
        _log.info('Please run "firebase login" first and then try again.');
        return;
      }
    } catch (e) {
      _log.warn(
          '⚠️ Firebase session check timed out or failed. Proceeding with caution...');
    }

    // 3. Ensure firebase_core is in pubspec
    _log.info('📦 Checking firebase_core dependency...');
    final pubspecFile = File(p.join(ConfigService.root, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      final content = pubspecFile.readAsStringSync();
      if (!content.contains('firebase_core:')) {
        _log.info('➕ Adding firebase_core to pubspec.yaml...');
        final addResult =
            await Process.run('flutter', ['pub', 'add', 'firebase_core']);
        if (addResult.exitCode != 0) {
          _log.warn(
              '⚠️ Could not add firebase_core automatically via "flutter pub add". Please add it manually.');
        }
      }
    }

    final allFlavors = ConfigService.getFlavors();
    final flavors = targetFlavor != null ? [targetFlavor] : allFlavors;
    final productionFlavor = ConfigService.getProductionFlavor();
    final config = ConfigService.load();
    final basePackageId =
        config['android']?['application_id'] ?? 'com.example.app';
    final useSuffix = ConfigService.useSuffix();
    final useSeparate = ConfigService.useSeparateMains();

    // 4. Choose Strategy
    final strategy = _log.chooseOne(
      '👉 Which Firebase strategy are you using?',
      choices: [
        'Single Project (One project for all flavors)',
        'Multi-Project (Separate project per flavor)',
      ],
    );

    final isSingleProject = strategy.startsWith('Single');
    Map<String, String> flavorProjects = {};

    if (isSingleProject) {
      final projectId = _log.prompt('👉 Enter your Firebase Project ID:');
      for (final flavor in flavors) {
        flavorProjects[flavor] = projectId;
      }
    } else {
      for (final flavor in flavors) {
        final projectId =
            _log.prompt('👉 Enter Firebase Project ID for "$flavor":');
        flavorProjects[flavor] = projectId;
      }
    }

    // 5. Target Platforms (Android & iOS)
    final platforms = ['android', 'ios'];

    final platformsString = platforms.join(',');

    final successfulFlavors = <String>[];

    // 6. Check for existing configs to offer "Just Inject" mode
    bool skipConfigure = false;

    if (!fromHook) {
      final existingConfigs = flavors.where((f) =>
          File(p.join(ConfigService.root, 'lib/firebase_options_$f.dart'))
              .existsSync());

      if (existingConfigs.isNotEmpty) {
        _log.info(
            '\n🛡️ Detected existing Firebase configurations for: ${existingConfigs.join(", ")}');
        final prompt = targetFlavor != null
            ? '👉 Do you want to re-run "flutterfire configure" for flavor "$targetFlavor"?'
            : '👉 Do you want to re-run "flutterfire configure" for all flavors?';

        skipConfigure = !_log.confirm(prompt, defaultValue: true);

        if (skipConfigure) {
          successfulFlavors.addAll(existingConfigs);
          _log.info(
              '⏩ Skipping configuration. Proceeding to code injection...');
        }
      }
    }

    if (!skipConfigure) {
      _log.info(
          '\n🚀 Starting configuration for ${flavors.length} flavors...\n');

      for (final flavor in flavors) {
        final projectId = flavorProjects[flavor]!;

        // Calculate package ID for this flavor
        String packageId = basePackageId;
        if (useSuffix && flavor != productionFlavor) {
          packageId = '$basePackageId.$flavor';
        }

        final outPath = 'lib/firebase_options_$flavor.dart';

        _log.info(
            '📦 Configuring "$flavor" ($packageId) -> Project: $projectId');

        final args = [
          'configure',
          '--project=$projectId',
          '--out=$outPath',
          '--ios-bundle-id=$packageId',
          '--android-package-name=$packageId',
          '--platforms=$platformsString',
          '--yes',
        ];

        final result = await Process.start('flutterfire', args,
            mode: ProcessStartMode.inheritStdio);
        final exitCode = await result.exitCode;

        if (exitCode != 0) {
          _log.error('❌ Failed to configure flavor: $flavor');
          _diagnoseFirebaseError();

          if (fromHook) {
            _log.warn('⚠️ Skipping flavor "$flavor" due to error.');
            continue;
          }
          final cont = _log.confirm(
              'Do you want to continue with other flavors?',
              defaultValue: true);
          if (!cont) break;
        } else {
          _log.success('✔ Flavor "$flavor" configured successfully.');
          successfulFlavors.add(flavor);

          // Automated Code Injection
          if (useSeparate) {
            FileService.injectFirebase(separate: true, flavor: flavor);
            _log.info(
                '   📝 lib/main/main_$flavor.dart updated with Firebase initialization');
          }
        }
        _log.info('---');
      }
    }

    if (!useSeparate && successfulFlavors.isNotEmpty) {
      FileService.injectFirebase(
          separate: false, activeFlavors: successfulFlavors);
      _log.info('📝 lib/main.dart updated with Firebase initialization');
    }

    _log.success('\n✅ Firebase setup complete!');
  }

  void _diagnoseFirebaseError() {
    final logFile = File(p.join(ConfigService.root, 'firebase-debug.log'));
    if (!logFile.existsSync()) return;

    try {
      final content = logFile.readAsStringSync();
      if (content.contains('ALREADY_EXISTS') ||
          content.contains('Requested entity already exists')) {
        _log.info(
            '\n💡 Tip: An app with this bundle ID already exists in your Firebase project.');
        _log.info(
            '   Go to Firebase Console settings and delete the existing app before retrying,');
        _log.info('   or ensure you are using the correct Project ID.');
      } else if (content.contains('PERMISSION_DENIED')) {
        _log.info(
            '\n💡 Tip: You don\'t have permission to create apps in this Firebase project.');
        _log.info('   Check your roles (Owner or Firebase Admin required).');
      } else if (content.contains('PROJECT_LIMIT_EXCEEDED')) {
        _log.info(
            '\n💡 Tip: Your Firebase project has reached the maximum number of apps allowed.');
      }
    } catch (_) {}
  }

  Future<ProcessResult> _runWithTimeout(
    String command,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final process = await Process.start(command, args, runInShell: true);

    final stdout = StringBuffer();
    final stderr = StringBuffer();

    final stdoutSub =
        process.stdout.transform(utf8.decoder).listen(stdout.write);
    final stderrSub =
        process.stderr.transform(utf8.decoder).listen(stderr.write);

    try {
      final exitCode = await process.exitCode.timeout(timeout);
      return ProcessResult(
          process.pid, exitCode, stdout.toString(), stderr.toString());
    } on TimeoutException {
      process.kill();
      throw TimeoutException('Process $command timed out', timeout);
    } finally {
      await stdoutSub.cancel();
      await stderrSub.cancel();
    }
  }

  Future<bool> _checkCommand(String command) async {
    try {
      final isWindows = Platform.isWindows;
      final checkCmd = isWindows ? 'where' : 'which';
      final result = await Process.run(checkCmd, [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<_CLIStatus> _verifyFlutterFire() async {
    final hasCmd = await _checkCommand('flutterfire');
    if (!hasCmd) return _CLIStatus.missing;

    try {
      final result = await _runWithTimeout('flutterfire', ['--version']);
      if (result.exitCode == 0) return _CLIStatus.working;

      final output =
          (result.stdout.toString() + result.stderr.toString()).toLowerCase();
      if (output.contains('cannot resolve') ||
          output.contains('pubspec.lock') ||
          output.contains('doesn\'t support dart') ||
          output.contains('invalid kernel')) {
        return _CLIStatus.broken;
      }
      return _CLIStatus.working; // Assume working if other error
    } catch (e) {
      return _CLIStatus.broken;
    }
  }

  static Future<void> checkAndReinit(AppLogger log,
      {String? targetFlavor}) async {
    bool hasDependency = false;
    final pubspec = File(p.join(ConfigService.root, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      hasDependency = pubspec.readAsStringSync().contains('firebase_core:');
    }

    if (!hasDependency) return;

    bool hasConfig = false;
    final libDir = Directory(p.join(ConfigService.root, 'lib'));
    if (libDir.existsSync()) {
      hasConfig =
          libDir.listSync().any((e) => e.path.contains('firebase_options_'));
    }

    if (!hasConfig) {
      final androidJson =
          File(p.join(ConfigService.root, 'android/app/google-services.json'));
      final iosPlist = File(
          p.join(ConfigService.root, 'ios/Runner/GoogleService-Info.plist'));
      hasConfig = androidJson.existsSync() || iosPlist.existsSync();
    }

    if (hasConfig) {
      final prompt = targetFlavor != null
          ? '\n🔥 Firebase detected. Do you want to run Firebase setup for flavor "$targetFlavor"?'
          : '\n🔥 Firebase detected. Do you want to run Firebase setup for the updated flavors?';

      final shouldReinit = log.confirm(
        prompt,
        defaultValue: true,
      );
      if (shouldReinit) {
        await FirebaseCommand(logger: log, fromHook: true)
            .execute(targetFlavor: targetFlavor);
      } else {
        log.info('⏩ Skipping Firebase re-initialization.');
      }
    }
  }
}

enum _CLIStatus { missing, working, broken }
