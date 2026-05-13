import 'dart:io';

import 'package:path/path.dart' as p;

import 'config_service.dart';

class PubspecService {
  static String get _pubspecPath => p.join(ConfigService.root, 'pubspec.yaml');

  static bool hasDependency(String name) {
    final file = File(_pubspecPath);

    if (!file.existsSync()) return false;

    final lines = file.readAsLinesSync();

    bool inDependencies = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (!line.startsWith(' ') && trimmed == 'dependencies:') {
        inDependencies = true;
        continue;
      }

      if (inDependencies && trimmed.isNotEmpty && !line.startsWith(' ')) {
        break;
      }

      if (inDependencies && trimmed.startsWith('$name:')) {
        return true;
      }
    }

    return false;
  }

  static void addDependency(
    String name,
    String version,
  ) {
    final file = File(_pubspecPath);

    if (!file.existsSync()) return;

    if (hasDependency(name)) return;

    final lines = file.readAsLinesSync();

    final result = <String>[];

    bool inserted = false;
    bool dependenciesFound = false;

    for (final line in lines) {
      result.add(line);

      if (!line.startsWith(' ') && line.trim() == 'dependencies:') {
        dependenciesFound = true;

        result.add('  $name: $version');

        inserted = true;
      }
    }

    if (!dependenciesFound && !inserted) {
      result.add('');
      result.add('dependencies:');
      result.add('  $name: $version');
    }

    file.writeAsStringSync(
      '${result.join('\n')}\n',
    );
  }

  static void removeDependency(
    String name,
  ) {
    final file = File(_pubspecPath);

    if (!file.existsSync()) return;

    final lines = file.readAsLinesSync();

    final result = lines.where((line) {
      final trimmed = line.trimLeft();

      return !trimmed.startsWith(
        '$name:',
      );
    }).toList();

    file.writeAsStringSync(
      '${result.join('\n')}\n',
    );
  }

  static void addAssets(
    List<String> assetPaths,
  ) {
    final file = File(_pubspecPath);

    if (!file.existsSync()) return;

    final lines = file.readAsLinesSync();

    final existingAssets = _getAllAssets(lines);

    final toAdd = assetPaths
        .where(
          (e) => !existingAssets.contains(e),
        )
        .toList();

    if (toAdd.isEmpty) return;

    final result = <String>[];

    bool flutterFound = false;
    bool assetsFound = false;
    bool inserted = false;

    for (final line in lines) {
      final trimmed = line.trim();

      result.add(line);

      if (!line.startsWith(' ') && trimmed == 'flutter:') {
        flutterFound = true;
        continue;
      }

      if (flutterFound && line.startsWith('  ') && trimmed == 'assets:') {
        assetsFound = true;

        if (!inserted) {
          for (final asset in toAdd) {
            result.add(
              '    - $asset',
            );
          }

          inserted = true;
        }
      }
    }

    if (flutterFound && !assetsFound) {
      final flutterIndex = result.indexWhere(
        (e) => !e.startsWith(' ') && e.trim() == 'flutter:',
      );

      if (flutterIndex != -1) {
        result.insert(
          flutterIndex + 1,
          '  assets:',
        );

        for (int i = 0; i < toAdd.length; i++) {
          result.insert(
            flutterIndex + 2 + i,
            '    - ${toAdd[i]}',
          );
        }
      }
    }

    if (!flutterFound) {
      result.add('');
      result.add('flutter:');
      result.add('  assets:');

      for (final asset in toAdd) {
        result.add(
          '    - $asset',
        );
      }
    }

    file.writeAsStringSync(
      '${result.join('\n')}\n',
    );
  }

  static void removeAssets(
    List<String> assetPaths,
  ) {
    final file = File(_pubspecPath);

    if (!file.existsSync()) return;

    final lines = file.readAsLinesSync();

    final toRemove = assetPaths.toSet();

    final result = <String>[];

    bool inFlutter = false;
    bool inAssets = false;

    int? assetsIndex;
    int? flutterIndex;

    for (final line in lines) {
      final trimmed = line.trim();

      // root flutter section
      if (!line.startsWith(' ') && trimmed == 'flutter:') {
        inFlutter = true;
        flutterIndex = result.length;

        result.add(line);

        continue;
      }

      // assets section
      if (inFlutter && line.startsWith('  ') && trimmed == 'assets:') {
        inAssets = true;
        assetsIndex = result.length;

        result.add(line);

        continue;
      }

      // exit assets block
      if (inAssets &&
          trimmed.isNotEmpty &&
          line.startsWith('  ') &&
          !line.startsWith('    ') &&
          trimmed != 'assets:') {
        inAssets = false;
      }

      // remove assets
      if (inAssets && trimmed.startsWith('- ')) {
        final asset = trimmed.substring(2).trim();

        if (toRemove.contains(asset)) {
          continue;
        }
      }

      result.add(line);
    }

    // remove empty assets section
    if (assetsIndex != null) {
      bool hasAssets = false;

      for (int i = assetsIndex + 1; i < result.length; i++) {
        final line = result[i];

        if (line.startsWith(
          '    - ',
        )) {
          hasAssets = true;
          break;
        }

        if (line.startsWith('  ') &&
            !line.startsWith('    ') &&
            line.trim().isNotEmpty) {
          break;
        }

        if (!line.startsWith(' ') && line.trim().isNotEmpty) {
          break;
        }
      }

      if (!hasAssets) {
        result.removeAt(
          assetsIndex,
        );
      }
    }

    // remove empty flutter section
    if (flutterIndex != null) {
      bool hasFlutterContent = false;

      for (int i = flutterIndex + 1; i < result.length; i++) {
        final line = result[i];

        if (line.startsWith('  ') && line.trim().isNotEmpty) {
          hasFlutterContent = true;
          break;
        }

        if (!line.startsWith(' ') && line.trim().isNotEmpty) {
          break;
        }
      }

      if (!hasFlutterContent) {
        result.removeAt(
          flutterIndex,
        );
      }
    }

    file.writeAsStringSync(
      '${result.join('\n')}\n',
    );
  }

  static List<String> getAssetsWithPrefix(
    String prefix,
  ) {
    final file = File(_pubspecPath);

    if (!file.existsSync()) {
      return [];
    }

    final lines = file.readAsLinesSync();

    return _getAllAssets(lines)
        .where(
          (e) => e.startsWith(prefix),
        )
        .toList();
  }

  static Set<String> _getAllAssets(
    List<String> lines,
  ) {
    final assets = <String>{};

    bool inFlutter = false;
    bool inAssets = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (!line.startsWith(' ') && trimmed == 'flutter:') {
        inFlutter = true;
        continue;
      }

      if (inFlutter && line.startsWith('  ') && trimmed == 'assets:') {
        inAssets = true;
        continue;
      }

      if (inAssets) {
        if (line.startsWith('  ') &&
            !line.startsWith('    ') &&
            trimmed.isNotEmpty &&
            trimmed != 'assets:') {
          break;
        }

        if (trimmed.startsWith('- ')) {
          assets.add(
            trimmed.substring(2).trim(),
          );
        }
      }
    }

    return assets;
  }
}
