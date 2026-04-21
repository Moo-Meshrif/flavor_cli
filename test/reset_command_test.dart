import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:flavor_cli/runner/setup_runner.dart';
import 'package:flavor_cli/services/config_service.dart';
import 'package:flavor_cli/models/flavor_config.dart';
import 'test_utils.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await createTestSandbox();
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
    ConfigService.root = '.';
  });

  test('SetupRunner.reset should remove flavor artifacts and restore main.dart', () async {
    final config = FlavorConfig(
      flavors: ['dev', 'prod'],
      appName: 'TestApp',
      fields: {},
      flavorValues: {'dev': {}, 'prod': {}},
      appConfigPath: 'lib/app_config.dart',
      useSeparateMains: true,
      useSuffix: true,
      android: const AndroidConfig(applicationId: 'com.ex'),
      ios: const IosConfig(bundleId: 'com.ex'),
      productionFlavor: 'prod',
    );
    ConfigService.save(config);
    await SetupRunner().run(config);

    final flavorConfig = File(p.join(sandbox.path, '.flavor_cli.json'));
    final mainDev = File(p.join(sandbox.path, 'lib/main/main_dev.dart'));

    expect(flavorConfig.existsSync(), isTrue);
    expect(mainDev.existsSync(), isTrue);

    SetupRunner().reset();

    expect(flavorConfig.existsSync(), isFalse);
    expect(mainDev.existsSync(), isFalse);
    expect(File(p.join(sandbox.path, 'lib/main.dart')).existsSync(), isTrue);
  });
}
