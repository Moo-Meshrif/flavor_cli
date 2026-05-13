// flavor_cli: added
import 'dart:io';
import 'package:path/path.dart' as p;
import 'config_service.dart';

/// Safe .gitignore modification service.
class GitignoreService {
  static String get _gitignorePath => p.join(ConfigService.root, '.gitignore');

  /// Appends [entries] to .gitignore, skipping any that already exist.
  static void addEntries(List<String> entries) {
    final file = File(_gitignorePath);
    String existing = '';
    if (file.existsSync()) {
      existing = file.readAsStringSync();
    }

    final existingLines = existing.split('\n').map((l) => l.trim()).toSet();
    final toAdd =
        entries.where((e) => !existingLines.contains(e.trim())).toList();
    if (toAdd.isEmpty) return;

    final buffer = StringBuffer();
    if (existing.isNotEmpty && !existing.endsWith('\n')) {
      buffer.writeln();
    }
    buffer.writeln('# flavor_cli ENV files');
    for (final entry in toAdd) {
      buffer.writeln(entry);
    }

    file.writeAsStringSync(existing + buffer.toString());
  }
}
