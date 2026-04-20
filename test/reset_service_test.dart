import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flavor_cli/src/services/reset_service.dart';
import 'package:flavor_cli/src/services/config_service.dart';
import 'package:flavor_cli/src/services/file_service.dart';
import 'test_utils.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await createTestSandbox();
  });

  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  test('ResetService should remove flavor artifacts and restore main.dart', () async {
    // 1. Setup a flavored state
    ConfigService.init(
      flavors: ['dev', 'prod'],
      appName: 'TestApp',
      appConfigPath: 'lib/core/config/app_config.dart',
      useSeparateMains: true,
    );
    FileService.createStructure();
    FileService.createAppConfig();
    FileService.createMainFiles();

    final flavorConfig = File(p.join(sandbox.path, '.flavor_cli.json'));
    final appConfig = File(p.join(sandbox.path, 'lib/core/config/app_config.dart'));
    final mainDev = File(p.join(sandbox.path, 'lib/main/main_dev.dart'));
    final mainProd = File(p.join(sandbox.path, 'lib/main/main_prod.dart'));

    expect(flavorConfig.existsSync(), isTrue);
    expect(appConfig.existsSync(), isTrue);
    expect(mainDev.existsSync(), isTrue);
    expect(mainProd.existsSync(), isTrue);

    // 2. Run Reset
    ResetService.reset(logger: FakeAppLogger(prompts: [], choices: []));

    // 3. Verify cleanup
    expect(flavorConfig.existsSync(), isFalse);
    expect(appConfig.existsSync(), isFalse);
    expect(mainDev.existsSync(), isFalse);
    expect(mainProd.existsSync(), isFalse);
    expect(Directory(p.join(sandbox.path, 'lib/main')).existsSync(), isFalse);

    // 4. Verify main.dart restoration
    final mainFile = File(p.join(sandbox.path, 'lib/main.dart'));
    expect(mainFile.existsSync(), isTrue);
    expect(mainFile.readAsStringSync(), contains('void main() {'));
  });
}
