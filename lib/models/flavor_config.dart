// flavor_cli: added
class FirebaseConfig {
  final String strategy;
  final Map<String, String> projects;

  const FirebaseConfig({
    required this.strategy,
    required this.projects,
  });

  factory FirebaseConfig.fromJson(Map<String, dynamic> json) {
    return FirebaseConfig(
      strategy: json['strategy'] as String? ?? '',
      projects: Map<String, String>.from(json['projects'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'strategy': strategy,
        'projects': projects,
      };

  FirebaseConfig copyWith({
    String? strategy,
    Map<String, String>? projects,
  }) {
    return FirebaseConfig(
      strategy: strategy ?? this.strategy,
      projects: projects ?? this.projects,
    );
  }
}

class AndroidConfig {
  final String applicationId;

  const AndroidConfig({
    required this.applicationId,
  });

  factory AndroidConfig.fromJson(Map<String, dynamic> json) {
    return AndroidConfig(
      applicationId: json['application_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'application_id': applicationId,
      };

  AndroidConfig copyWith({
    String? applicationId,
  }) {
    return AndroidConfig(
      applicationId: applicationId ?? this.applicationId,
    );
  }
}

class IosConfig {
  final String bundleId;

  const IosConfig({
    required this.bundleId,
  });

  factory IosConfig.fromJson(Map<String, dynamic> json) {
    return IosConfig(
      bundleId: json['bundle_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'bundle_id': bundleId,
      };

  IosConfig copyWith({
    String? bundleId,
  }) {
    return IosConfig(
      bundleId: bundleId ?? this.bundleId,
    );
  }
}

class FlavorConfig {
  final List<String> flavors;
  final String appName;
  final Map<String, String> fields;
  final Map<String, Map<String, dynamic>> flavorValues;
  final String appConfigPath;
  final bool useSeparateMains;
  final bool useSuffix;
  final AndroidConfig android;
  final IosConfig ios;
  final String productionFlavor;
  final FirebaseConfig? firebase;
  final bool generateScripts;

  const FlavorConfig({
    required this.flavors,
    required this.appName,
    required this.fields,
    required this.flavorValues,
    required this.appConfigPath,
    required this.useSeparateMains,
    required this.useSuffix,
    required this.android,
    required this.ios,
    required this.productionFlavor,
    this.firebase,
    this.generateScripts = false,
  });

  factory FlavorConfig.fromJson(Map<String, dynamic> json) {
    return FlavorConfig(
      flavors: (json['flavors'] as List<dynamic>?)?.cast<String>() ?? const [],
      appName: json['app_name'] as String? ?? 'MyApp',
      fields: Map<String, String>.from(json['fields'] as Map? ?? {}),
      flavorValues: (json['values'] as Map? ?? {}).map(
        (key, value) => MapEntry(
          key as String,
          Map<String, dynamic>.from(value as Map? ?? {}),
        ),
      ),
      appConfigPath: json['app_config_path'] as String? ?? 'lib/core/config/app_config.dart',
      useSeparateMains: json['use_separate_mains'] as bool? ?? true,
      useSuffix: json['use_suffix'] as bool? ?? true,
      android: AndroidConfig.fromJson(json['android'] as Map<String, dynamic>? ?? {}),
      ios: IosConfig.fromJson(json['ios'] as Map<String, dynamic>? ?? {}),
      productionFlavor: json['production_flavor'] as String? ?? '',
      firebase: json['firebase'] != null 
          ? FirebaseConfig.fromJson(json['firebase'] as Map<String, dynamic>) 
          : null,
      generateScripts: json['generate_scripts'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'flavors': flavors,
      'app_name': appName,
      'fields': fields,
      'values': flavorValues,
      'app_config_path': appConfigPath,
      'use_separate_mains': useSeparateMains,
      'use_suffix': useSuffix,
      'android': android.toJson(),
      'ios': ios.toJson(),
      'production_flavor': productionFlavor,
      'generate_scripts': generateScripts,
    };
    if (firebase != null) {
      json['firebase'] = firebase!.toJson();
    }
    return json;
  }

  FlavorConfig copyWith({
    List<String>? flavors,
    String? appName,
    Map<String, String>? fields,
    Map<String, Map<String, dynamic>>? flavorValues,
    String? appConfigPath,
    bool? useSeparateMains,
    bool? useSuffix,
    AndroidConfig? android,
    IosConfig? ios,
    String? productionFlavor,
    FirebaseConfig? firebase,
    bool? generateScripts,
  }) {
    return FlavorConfig(
      flavors: flavors ?? this.flavors,
      appName: appName ?? this.appName,
      fields: fields ?? this.fields,
      flavorValues: flavorValues ?? this.flavorValues,
      appConfigPath: appConfigPath ?? this.appConfigPath,
      useSeparateMains: useSeparateMains ?? this.useSeparateMains,
      useSuffix: useSuffix ?? this.useSuffix,
      android: android ?? this.android,
      ios: ios ?? this.ios,
      productionFlavor: productionFlavor ?? this.productionFlavor,
      firebase: firebase ?? this.firebase,
      generateScripts: generateScripts ?? this.generateScripts,
    );
  }
}
