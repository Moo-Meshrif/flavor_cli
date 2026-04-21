import 'dart:io';
import 'package:path/path.dart' as p;
import 'config_service.dart';
import '../utils/logger.dart';
import '../models/flavor_config.dart';

class AndroidService {
  static void setupFlavors({required FlavorConfig config, AppLogger? logger}) {
    final log = logger ?? AppLogger();
    final flavors = config.flavors;
    final fields = config.fields;

    // Check Groovy
    final groovyFile =
        File(p.join(ConfigService.root, 'android/app/build.gradle'));
    if (groovyFile.existsSync()) {
      _setupGroovy(groovyFile, config, flavors, fields, log);
    }

    // Check Kotlin DSL
    final ktsFile =
        File(p.join(ConfigService.root, 'android/app/build.gradle.kts'));
    if (ktsFile.existsSync()) {
      _setupKTS(ktsFile, config, flavors, fields, log);
    }

    _updateManifest(log);
    _handlePackageMigration(config, log);
  }

  static void addFlavor(String flavor, {required FlavorConfig config, AppLogger? logger}) {
    setupFlavors(config: config, logger: logger);
  }

  static void reset({required FlavorConfig config, AppLogger? logger}) {
    final log = logger ?? AppLogger();
    final groovyFile =
        File(p.join(ConfigService.root, 'android/app/build.gradle'));
    if (groovyFile.existsSync()) {
      _resetFile(groovyFile);
    }

    final ktsFile =
        File(p.join(ConfigService.root, 'android/app/build.gradle.kts'));
    if (ktsFile.existsSync()) {
      _resetFile(ktsFile);
    }

    _resetManifest(config);
    log.success('✔ Android flavor configuration removed');
  }

  static void _resetFile(File file) {
    var content = file.readAsStringSync();

    // Remove flavorDimensions (any variant)
    content = content.replaceAll(
        RegExp(r'flavorDimensions\s*(\+?=)?\s*".*?"\s*'), '');
    content = content.replaceAll(
        RegExp(r'flavorDimensions\s*(\+?=)?\s*\[.*?\]\s*'), '');

    // Comprehensive block removal - repeat until no more blocks found
    while (content
        .contains(RegExp(r'\bproductFlavors\s*\{', caseSensitive: false))) {
      content = _removeBlock(content, 'productFlavors');
    }

    file.writeAsStringSync(content);
  }

  static void _resetManifest(config) {
    
    final manifestPath =
        p.join(ConfigService.root, 'android/app/src/main/AndroidManifest.xml');
    final file = File(manifestPath);
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();
    final appName = config.appName;

    // Replace @string/app_name with real name
    content = content.replaceFirst(
        RegExp(r'android:label\s*=\s*"@string/app_name"'),
        'android:label="$appName"');

    file.writeAsStringSync(content);
  }

  static String _removeBlock(String content, String blockName) {
    final blockRegex =
        RegExp(r'\b' + blockName + r'\s*\{', caseSensitive: false);
    final match = blockRegex.firstMatch(content);

    if (match != null) {
      final startIndex = match.start;
      final endIndex = _findClosingBrace(content, match.end - 1);
      if (endIndex != -1) {
        // Find leading whitespace to clean up
        var startToRemove = startIndex;
        while (startToRemove > 0 &&
            (content[startToRemove - 1] == ' ' ||
                content[startToRemove - 1] == '\t')) {
          startToRemove--;
        }
        if (startToRemove > 0 && content[startToRemove - 1] == '\n') {
          startToRemove--;
        }

        return content.replaceRange(startToRemove, endIndex + 1, '');
      }
    }
    return content;
  }

  static void _updateManifest(AppLogger log) {
    final manifestPath =
        p.join(ConfigService.root, 'android/app/src/main/AndroidManifest.xml');
    final file = File(manifestPath);
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();

    // Replace android:label="..." with android:label="@string/app_name" if not already a resource
    final labelRegex = RegExp(r'android:label\s*=\s*"([^@][^"]*)"');
    if (labelRegex.hasMatch(content)) {
      content =
          content.replaceFirst(labelRegex, 'android:label="@string/app_name"');
      file.writeAsStringSync(content);
      log.info('   ✓ AndroidManifest.xml updated to use @string/app_name');
    }
  }

  static void _setupGroovy(File file, FlavorConfig config, List<String> flavors, Map<String, String> fields, AppLogger log) {
    var content = file.readAsStringSync();

    // 1. Ensure flavorDimensions
    if (!content.contains('flavorDimensions')) {
      content = content.replaceFirst(
          RegExp(r'android\s*\{'), 'android {\n    flavorDimensions "default"');
    }

    // 2. Update applicationId if configured
    
    final appId = config.android.applicationId as String?;
    if (appId != null) {
      final appIdRegex = RegExp(r'applicationId\s*=\s*".*?"');
      if (appIdRegex.hasMatch(content)) {
        content = content.replaceFirst(appIdRegex, 'applicationId = "$appId"');
      }
      final namespaceRegex = RegExp(r'namespace\s*(=|\s)\s*".*?"');
      if (namespaceRegex.hasMatch(content)) {
        content = content.replaceFirst(namespaceRegex, 'namespace = "$appId"');
      }
    }

    // 3. Generate productFlavors block
    final buffer = StringBuffer();
    buffer.writeln('    productFlavors {');
    final baseAppName = config.appName;
    final prodFlavor = config.productionFlavor;
    final useSuffix = config.useSuffix;

    for (final flavor in flavors) {
      final name = _getFlavoredName(baseAppName, flavor, config);
      buffer.writeln('        $flavor {');
      buffer.writeln('            dimension "default"');
      buffer.writeln('            resValue "string", "app_name", "$name"');
      if (useSuffix && flavor != prodFlavor) {
        buffer.writeln('            applicationIdSuffix ".$flavor"');
      }
      buffer.writeln('        }');
    }
    buffer.writeln('    }');

    content = _replaceOrAddBlock(content, 'productFlavors', buffer.toString());
    file.writeAsStringSync(content);
    log.info('✔ Android flavors completed');
  }

  static void _setupKTS(File file, FlavorConfig config, List<String> flavors, Map<String, String> fields, AppLogger log) {
    var content = file.readAsStringSync();

    // 1. Ensure flavorDimensions
    if (!content.contains('flavorDimensions')) {
      content = content.replaceFirst(RegExp(r'android\s*\{'),
          'android {\n    flavorDimensions += "default"');
    }

    // 2. Update applicationId if configured
    
    final appId = config.android.applicationId as String?;
    if (appId != null) {
      final appIdRegex = RegExp(r'applicationId\s*=\s*".*?"');
      if (appIdRegex.hasMatch(content)) {
        content = content.replaceFirst(appIdRegex, 'applicationId = "$appId"');
      }
      final namespaceRegex = RegExp(r'namespace\s*=\s*".*?"');
      if (namespaceRegex.hasMatch(content)) {
        content = content.replaceFirst(namespaceRegex, 'namespace = "$appId"');
      }
    }

    // 3. Generate productFlavors block
    final buffer = StringBuffer();
    buffer.writeln('    productFlavors {');
    final baseAppName = config.appName;
    final prodFlavor = config.productionFlavor;
    final useSuffix = config.useSuffix;

    for (final flavor in flavors) {
      final name = _getFlavoredName(baseAppName, flavor, config);
      buffer.writeln('        create("$flavor") {');
      buffer.writeln('            dimension = "default"');
      buffer.writeln('            resValue("string", "app_name", "$name")');
      if (useSuffix && flavor != prodFlavor) {
        buffer.writeln('            applicationIdSuffix = ".$flavor"');
      }
      buffer.writeln('        }');
    }
    buffer.writeln('    }');

    content = _replaceOrAddBlock(content, 'productFlavors', buffer.toString());
    file.writeAsStringSync(content);
    log.info('✔ Android flavors (KTS) completed');
  }

  static String _replaceOrAddBlock(
      String content, String blockName, String newBlock) {
    final blockRegex =
        RegExp(r'\b' + blockName + r'\s*\{', caseSensitive: false);
    final match = blockRegex.firstMatch(content);

    String updatedContent;
    if (match != null) {
      final index = match.start;
      // Find the end of the block by counting braces
      final endIndex = _findClosingBrace(content, match.end - 1);
      if (endIndex != -1) {
        updatedContent = content.replaceRange(index, endIndex + 1, newBlock);
      } else {
        // Fallback: if braces are broken, just add it after android {
        updatedContent = content.replaceFirst(
            RegExp(r'android\s*\{', caseSensitive: false),
            'android {\n$newBlock');
      }
    } else {
      // Not found, add after android {
      updatedContent = content.replaceFirst(
          RegExp(r'android\s*\{', caseSensitive: false),
          'android {\n$newBlock');
    }

    // Now cleanup ANY OTHER occurrences of blockName { ... } EXCEPT the one we just dealt with (the first one)
    final firstMatch = blockRegex.firstMatch(updatedContent);
    if (firstMatch != null) {
      final keeperEnd = _findClosingBrace(updatedContent, firstMatch.end - 1);
      if (keeperEnd != -1) {
        String prefix = updatedContent.substring(0, keeperEnd + 1);
        String suffix = updatedContent.substring(keeperEnd + 1);

        // Remove all subsequent matches of the block
        while (true) {
          final nextMatch = blockRegex.firstMatch(suffix);
          if (nextMatch == null) break;

          final nextIndex = nextMatch.start;
          final nextEnd = _findClosingBrace(suffix, nextMatch.end - 1);
          if (nextEnd != -1) {
            // Find leading whitespace/newlines to clean up
            var startToRemove = nextIndex;
            while (startToRemove > 0 &&
                (suffix[startToRemove - 1] == ' ' ||
                    suffix[startToRemove - 1] == '\t')) {
              startToRemove--;
            }
            if (startToRemove > 0 && suffix[startToRemove - 1] == '\n') {
              startToRemove--;
            }

            suffix = suffix.replaceRange(startToRemove, nextEnd + 1, '');
          } else {
            break;
          }
        }
        updatedContent = prefix + suffix;
      }
    }

    // Final pass to trim excessive empty lines
    updatedContent = updatedContent.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return updatedContent;
  }

  static int _findClosingBrace(String content, int openBraceIndex) {
    if (openBraceIndex < 0 ||
        openBraceIndex >= content.length ||
        content[openBraceIndex] != '{') {
      return -1;
    }
    int count = 0;
    for (int i = openBraceIndex; i < content.length; i++) {
      if (content[i] == '{') {
        count++;
      } else if (content[i] == '}') {
        count--;
        if (count == 0) {
          return i;
        }
      }
    }
    return -1;
  }

  static String _getFlavoredName(String baseName, String flavor, FlavorConfig config) {
    final productionFlavor = config.productionFlavor;
    if (flavor == productionFlavor) {
      return baseName;
    }
    return '$baseName-$flavor';
  }

  static void _handlePackageMigration(FlavorConfig config, AppLogger log) {
    
    final targetAppId = config.android.applicationId as String?;
    if (targetAppId == null) return;

    final mainDir = p.join(ConfigService.root, 'android/app/src/main');
    final kotlinDir = p.join(mainDir, 'kotlin');
    final javaDir = p.join(mainDir, 'java');

    File? mainActivityFile;
    String? currentPackage;
    String? sourceBaseDir;

    // Search for MainActivity
    for (final baseDir in [kotlinDir, javaDir]) {
      if (!Directory(baseDir).existsSync()) continue;

      final files = Directory(baseDir).listSync(recursive: true);
      for (final entity in files) {
        if (entity is File &&
            (p.basename(entity.path) == 'MainActivity.kt' ||
                p.basename(entity.path) == 'MainActivity.java')) {
          final content = entity.readAsStringSync();
          final match = RegExp(r'package\s+([\w.]+)').firstMatch(content);
          if (match != null) {
            mainActivityFile = entity;
            currentPackage = match.group(1);
            sourceBaseDir = baseDir;
            break;
          }
        }
      }
      if (mainActivityFile != null) break;
    }

    if (mainActivityFile == null ||
        currentPackage == null ||
        currentPackage == targetAppId) {
      return;
    }

    log.info('📦 Migrating Android package: $currentPackage -> $targetAppId');

    // 1. Move files
    final oldPackageDir =
        p.joinAll([sourceBaseDir!, ...currentPackage.split('.')]);
    final newPackageDir = p.joinAll([sourceBaseDir, ...targetAppId.split('.')]);

    if (!Directory(newPackageDir).existsSync()) {
      Directory(newPackageDir).createSync(recursive: true);
    }

    final oldDir = Directory(oldPackageDir);
    if (oldDir.existsSync()) {
      for (final entity in oldDir.listSync()) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          final newPath = p.join(newPackageDir, fileName);

          var content = entity.readAsStringSync();
          // 2. Update package declaration
          content = content.replaceFirst(
            RegExp(r'package\s+' + RegExp.escape(currentPackage)),
            'package $targetAppId',
          );

          File(newPath).writeAsStringSync(content);
          entity.deleteSync();
          log.info('   ✓ Moved and updated $fileName');
        }
      }
    }

    // 3. Cleanup old empty directories
    _cleanupEmptyDirs(sourceBaseDir, currentPackage);
  }

  static void _cleanupEmptyDirs(String baseDir, String package) {
    final parts = package.split('.');
    for (int i = parts.length; i > 0; i--) {
      final currentPath = p.joinAll([baseDir, ...parts.sublist(0, i)]);
      final dir = Directory(currentPath);
      if (dir.existsSync() && dir.listSync().isEmpty) {
        dir.deleteSync();
      } else {
        // If not empty, we can't delete parents either
        break;
      }
    }
  }
}
