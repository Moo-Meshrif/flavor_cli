import 'dart:io';
import 'dart:isolate';
import 'commands/delete_command.dart';
import 'commands/init_command.dart';
import 'commands/run_command.dart';
import 'commands/add_command.dart';
import 'commands/build_command.dart';
import 'commands/reset_command.dart';
import 'commands/replace_command.dart';
import 'commands/firebase_command.dart';
import 'commands/migrate_command.dart';
import 'utils/exceptions.dart';

class FlavorCLI {
  Future<void> run(List<String> arguments) async {
    if (arguments.isEmpty) {
      _printUsage();
      return;
    }

    final command = arguments[0];
    final remaining = arguments.sublist(1);

    try {
      switch (command) {
        case 'init':
          await InitCommand().execute(remaining);
          break;
        case 'add':
          await AddCommand().execute(remaining);
          break;
        case 'delete':
          DeleteCommand().execute(remaining);
          break;
        case 'replace':
          await ReplaceCommand().execute();
          break;
        case 'reset':
          ResetCommand().execute();
          break;
        case 'run':
          await RunCommand().execute(remaining);
          break;
        case 'build':
          await BuildCommand().execute(remaining);
          break;
        case 'firebase':
          await FirebaseCommand().execute();
          break;
        case 'migrate':
          await MigrateCommand().execute();
          break;
        case '--version':
        case '-v':
          await _printVersion();
          break;
        default:
          print('❌ Unknown command: $command');
          _printUsage();
      }
    } catch (e) {
      if (e is CliException) {
        // Custom exceptions are already formatted for the user
        print(e.toString());
      } else if (e is Exception) {
        // Generic exceptions get a red cross and the message
        print('❌ ${e.toString().replaceFirst('Exception: ', '')}');
      } else {
        // Programmer errors or unexpected types should still show stack trace
        rethrow;
      }
      exit(1);
    }
  }

  void _printUsage() {
    print('Usage: flavor_cli <command> [arguments]');
    print('');
    print('Commands:');
    print('  init     Initialize flavor setup in your project');
    print('  add      Add a new flavor to an existing setup');
    print('  delete   Remove an existing flavor');
    print('  replace  Rename an existing flavor');
    print(
        '  reset    Cleanup project from any flavors and revert to standard state');
    print('  run      Run the project with a specific flavor');
    print('  build    Build the project with a specific flavor');
    print('  firebase Setup Firebase for all flavors automatically');
    print('  migrate  Migrate flavor_cli.yaml to the latest format');

    print('');
    print('Examples:');
    print('  dart run flavor_cli init');
    print('  dart run flavor_cli add staging');
    print('  dart run flavor_cli replace');
    print('  dart run flavor_cli reset');
    print('  dart run flavor_cli run dev');
    print('  dart run flavor_cli build apk prod');
    print('  dart run flavor_cli firebase');
    print('  dart run flavor_cli migrate');
  }

  Future<void> _printVersion() async {
    try {
      final uri = await Isolate.resolvePackageUri(
          Uri.parse('package:flavor_cli/flavor_cli.dart'));
      if (uri != null) {
        final pubspecFile = File.fromUri(uri.resolve('../pubspec.yaml'));
        if (pubspecFile.existsSync()) {
          final content = pubspecFile.readAsStringSync();
          final match =
              RegExp(r'^version:\s*(.*)$', multiLine: true).firstMatch(content);
          if (match != null) {
            print('Flavor CLI v${match.group(1)?.trim()}');
            return;
          }
        }
      }
    } catch (_) {}
  }
}
