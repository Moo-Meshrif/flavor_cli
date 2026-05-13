// flavor_cli: added
import 'flavor_config.dart';

class ConfigValidator {
  static FlavorConfig validate(Map<String, dynamic> json) {
    final errors = <String>[];

    void addError(String field, String reason) {
      errors.add('   → "$field" $reason');
    }

    // Required root fields
    final requiredRoot = [
      'flavors',
      'app_name',
      'production_flavor',
      'app_config_path',
      'use_separate_mains',
      'use_suffix'
    ];

    for (var field in requiredRoot) {
      if (!json.containsKey(field) || json[field] == null) {
        addError(field, 'is required but missing.');
      }
    }

    // Android/iOS application_id / bundle_id
    if (json['android'] == null || json['android']['application_id'] == null) {
      addError('android.application_id', 'is required but missing.');
    }
    if (json['ios'] == null || json['ios']['bundle_id'] == null) {
      addError('ios.bundle_id', 'is required but missing.');
    }

    // Validation for flavors
    final flavorsList = json['flavors'] as List<dynamic>? ?? [];
    if (json.containsKey('flavors') && flavorsList.isEmpty) {
      addError('flavors', 'cannot be empty.');
    }

    final prodFlavor = json['production_flavor'] as String?;
    if (prodFlavor != null &&
        flavorsList.isNotEmpty &&
        !flavorsList.contains(prodFlavor)) {
      addError('production_flavor', 'must be one of the declared flavors.');
    }

    // Firebase Validation
    if (json['firebase'] != null) {
      final fb = json['firebase'] as Map<String, dynamic>;
      final strategy = fb['strategy'] as String?;
      final projects = fb['projects'] as Map<String, dynamic>? ?? {};
      final useSuffix = json['use_suffix'] as bool? ?? true;

      if (strategy == null) {
        addError('firebase.strategy',
            'is required when firebase config is present.');
      } else {
        const validStrategies = [
          'shared_id_single_project',
          'unique_id_single_project',
          'unique_id_multi_project'
        ];

        if (!validStrategies.contains(strategy)) {
          addError('firebase.strategy',
              'must be one of: ${validStrategies.join(', ')}.');
        } else {
          if (strategy == 'shared_id_single_project' && useSuffix == true) {
            addError('firebase.strategy',
                'shared_id_single_project requires use_suffix: false.');
          }
          if (strategy.startsWith('unique_id_') && useSuffix == false) {
            addError(
                'firebase.strategy', '$strategy requires use_suffix: true.');
          }

          final projectKeys = projects.keys.toSet();
          if (strategy == 'shared_id_single_project' ||
              strategy == 'unique_id_single_project') {
            if (projectKeys.length != 1 || !projectKeys.contains('all')) {
              addError('firebase.projects',
                  'for $strategy, projects must contain exactly one key: "all".');
            }
          } else if (strategy == 'unique_id_multi_project') {
            final flavorsSet = flavorsList.map((e) => e.toString()).toSet();
            if (projectKeys.length != flavorsSet.length ||
                !projectKeys.containsAll(flavorsSet) ||
                !flavorsSet.containsAll(projectKeys)) {
              addError('firebase.projects',
                  'for $strategy, projects keys must exactly match declared flavors: ${flavorsSet.join(', ')}.');
            }
          }
        }
      }
    }

    // Values are managed exclusively via .env files, so no validation needed here.

    if (errors.isNotEmpty) {
      final errorMsg = StringBuffer();
      errorMsg.writeln('❌ flavor_cli: invalid config at "flavor_cli.yaml"');
      for (var e in errors) {
        errorMsg.writeln(e);
      }
      throw FormatException(errorMsg.toString().trim());
    }

    return FlavorConfig.fromJson(json);
  }
}
