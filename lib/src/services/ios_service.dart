import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'config_service.dart';
import '../utils/logger.dart';

class IOSService {
  static void setupSchemes({AppLogger? logger}) {
    final log = logger ?? AppLogger();
    final root = ConfigService.root;

    final iosDir = Directory(p.join(root, 'ios'));
    if (!iosDir.existsSync()) {
      throw Exception('iOS folder not found');
    }

    _createXCConfigFiles(log);
    _updateInfoPlist(log);
    _runAutomationScript(log);

    // Sync Pods after adding flavored configurations
    syncPods(logger: log);

    _brandSchemes(log);

    log.success('🚀 iOS flavor setup completed automatically');
  }

  static void _createXCConfigFiles(AppLogger log) {
    final flavors = ConfigService.getFlavors();
    final root = ConfigService.root;
    final flutterDir = Directory(p.join(root, 'ios/Flutter'));

    if (!flutterDir.existsSync()) {
      flutterDir.createSync(recursive: true);
    }

    for (final flavor in flavors) {
      final file = File(p.join(flutterDir.path, '$flavor.xcconfig'));
      final brandedName = _getBrandedName(ConfigService.getAppName(), flavor);

      final productionFlavor = ConfigService.getProductionFlavor();
      final suffix = (flavor == productionFlavor || !ConfigService.useSuffix())
          ? ''
          : '.$flavor';

      final useSeparateMains = ConfigService.useSeparateMains();
      final targetPath =
          useSeparateMains ? 'lib/main/main_$flavor.dart' : 'lib/main.dart';

      final content = '''
#include "Generated.xcconfig"
FLUTTER_TARGET=$targetPath
FLUTTER_FLAVOR=$flavor
BUNDLE_ID_SUFFIX=$suffix
APP_NAME=$brandedName
''';
      file.writeAsStringSync(content);
      log.info('   ✓ Created $flavor.xcconfig (Customize configurations)');
    }
  }

  static void _updateInfoPlist(AppLogger log) {
    final plistPath = p.join(ConfigService.root, 'ios/Runner/Info.plist');
    final file = File(plistPath);
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();

    // Replace CFBundleDisplayName and CFBundleName with $(APP_NAME)
    final displayNameRegex =
        RegExp(r'<key>CFBundleDisplayName</key>\s*<string>.*?</string>');
    final dollar = String.fromCharCode(36);
    final brandedDisplay =
        '<key>CFBundleDisplayName</key>\n\t<string>$dollar(APP_NAME)</string>';

    if (displayNameRegex.hasMatch(content)) {
      content =
          content.replaceFirstMapped(displayNameRegex, (_) => brandedDisplay);
    } else {
      // Add it if missing
      content = content.replaceFirst('<dict>', '<dict>\n\t$brandedDisplay');
    }

    final bundleNameRegex =
        RegExp(r'<key>CFBundleName</key>\s*<string>.*?</string>');
    final brandedBundle =
        '<key>CFBundleName</key>\n\t<string>$dollar(APP_NAME)</string>';

    if (bundleNameRegex.hasMatch(content)) {
      content =
          content.replaceFirstMapped(bundleNameRegex, (_) => brandedBundle);
    }

    // Ensure CFBundleIdentifier uses $(PRODUCT_BUNDLE_IDENTIFIER)
    final bundleIdRegex =
        RegExp(r'<key>CFBundleIdentifier</key>\s*<string>.*?</string>');
    final brandedId =
        '<key>CFBundleIdentifier</key>\n\t<string>$dollar(PRODUCT_BUNDLE_IDENTIFIER)</string>';

    if (bundleIdRegex.hasMatch(content)) {
      content = content.replaceFirstMapped(bundleIdRegex, (_) => brandedId);
    }

    file.writeAsStringSync(content);
    log.info('   ✓ Info.plist updated to use \$(APP_NAME)');
  }

  static void _runAutomationScript(AppLogger log) {
    final root = ConfigService.root;
    final projectFile = Directory(p.join(root, 'ios/Runner.xcodeproj'));

    // Stop if not a real iOS project
    if (!projectFile.existsSync()) return;

    final flutterDir = Directory(p.join(root, 'ios/Flutter'));

    if (!flutterDir.existsSync()) {
      flutterDir.createSync(recursive: true);
    }

    // We write the script to a temporary file to avoid cluttering the project
    final tempDir = Directory.systemTemp.createTempSync('flavor_cli_');
    final scriptFile = File(p.join(tempDir.path, 'ios_flavor_setup.rb'));
    scriptFile.writeAsStringSync(_iosAutomationScriptContent());

    try {
      _runRubyAutomation(log: log, scriptPath: scriptFile.path);
    } finally {
      // Cleanup temp directory
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }

    log.info('✅ iOS project ready for automation (Zero-XCConfig mode)');
  }

  static String _iosAutomationScriptContent() {
    return r'''
require 'xcodeproj'
require 'fileutils'
require 'json'

# Standard Flutter files to preserve and heal
STANDARD_FILES = ['Generated.xcconfig', 'Debug.xcconfig', 'Release.xcconfig', 'AppFrameworkInfo.plist']

# Helper to get configuration name (e.g., Debug-DEV)
def get_config_name(base_name, flavor)
  alias_name = get_flavor_alias(flavor) || flavor
  "#{base_name}-#{alias_name.upcase}"
end

# Helper to get scheme name (e.g., DEV)
def get_scheme_name(flavor)
  (get_flavor_alias(flavor) || flavor).upcase
end

# Helper to get flavor alias (from .flavor_cli.json if available)
def get_flavor_alias(flavor)
  config_path = '.flavor_cli.json'
  if File.exist?(config_path)
    config = JSON.parse(File.read(config_path))
    raw_flavors = config['flavors'] || []
    flavor_config = raw_flavors.find { |f| f.is_a?(Hash) && f['name'] == flavor }
    if flavor_config && flavor_config['alias'] && !flavor_config['alias'].to_s.empty?
      return flavor_config['alias'].to_s
    end
  end
  # Special common case
  return 'stage' if flavor == 'staging'
  flavor.to_s
end

# Helper to get flavored bundle identifier
def get_flavored_bundle_id(base_id, flavor, config)
  use_suffix = config['use_suffix'] != false # Default to true
  
  production_flavor = config['production_flavor']
  if production_flavor.nil?
    flavors = config['flavors'] || []
    raw_flavors = flavors.map { |f| f.is_a?(Hash) ? f['name'] : f }.compact
    if raw_flavors.include?('prod')
      production_flavor = 'prod'
    elsif raw_flavors.include?('production')
      production_flavor = 'production'
    else
      production_flavor = raw_flavors.first
    end
  end

  if !use_suffix || flavor == production_flavor
    return base_id
  else
    # Sanitize flavor for bundle id (lowercase, dots/hyphens only)
    sanitized_flavor = flavor.downcase.gsub(/[^a-z0-9]/, '-')
    return "#{base_id}.#{sanitized_flavor}"
  end
end

# Find flavors from command line or .flavor_cli.json
config_path = '.flavor_cli.json'
config = File.exist?(config_path) ? JSON.parse(File.read(config_path)) : {}

if ARGV.include?('--delete')
  delete_flavor = ARGV[ARGV.index('--delete') + 1]
  flavors = []
elsif ARGV.include?('--reset')
  reset_mode = true
  flavors = []
else
  if config.empty?
    puts "❌ .flavor_cli.json not found. Run 'init' first."
    exit 1
  end
  raw_flavors = config['flavors'] || []
  flavors = raw_flavors.map { |f| f.is_a?(Hash) ? f['name'] : f }.compact
end

project_path = 'ios/Runner.xcodeproj'
unless Dir.exist?(project_path)
  puts "⚠️ iOS project not found at #{project_path}. Skipping Xcode automation."
  exit 0
end

project = Xcodeproj::Project.open(project_path)

# 1. Helper to find or create group - Force path to 'Flutter' and correct source tree
flutter_group = project.main_group['Flutter'] || project.main_group.new_group('Flutter')
flutter_group.set_path('Flutter')
flutter_group.source_tree = '<group>'

# 2. Deletion Logic
if delete_flavor
  puts "🗑️ Removing flavor: #{delete_flavor}..."
  
  # Remove Build Configurations
  ['Debug', 'Release', 'Profile'].each do |base_name|
    config_name = get_config_name(base_name, delete_flavor)
    
    project.build_configurations.find { |c| c.name == config_name }&.remove_from_project
    project.targets.each do |target|
      target.build_configurations.find { |c| c.name == config_name }&.remove_from_project
    end
  end
  
  # Remove Scheme
  scheme_name = get_scheme_name(delete_flavor)
  scheme_path = Xcodeproj::XCScheme.shared_data_dir(project_path).join("#{scheme_name}.xcscheme")
  File.delete(scheme_path) if File.exist?(scheme_path)

  # Remove File Reference
  file_ref = flutter_group.files.find { |f| f.path == "#{delete_flavor}.xcconfig" } || 
             flutter_group.files.find { |f| File.basename(f.path) == "#{delete_flavor}.xcconfig" }
  file_ref&.remove_from_project
  
  project.save
  puts "✅ Xcode cleanup for #{delete_flavor} completed!"
  exit 0
end

# 5. Path Healing: Ensure standard Flutter files and flavored xcconfigs are correctly referenced
def heal_flutter_group(project, flutter_group, flavors = [])
  # 1. Handle Standard Files
  STANDARD_FILES.each do |filename|
    file_path = File.expand_path("ios/Flutter/#{filename}")
    next unless File.exist?(file_path)

    file_ref = flutter_group.files.find { |f| f.path == filename } || 
               flutter_group.files.find { |f| File.basename(f.path) == filename }

    if file_ref
      unless file_ref.path == filename && file_ref.source_tree == '<group>'
        puts "🛠️  Healing standard file path: #{filename}"
        file_ref.set_path(filename)
        file_ref.source_tree = '<group>'
      end
    else
      puts "➕ Adding missing standard file reference: #{filename}"
      file_ref = flutter_group.new_reference(file_path)
      file_ref.set_path(filename)
      file_ref.source_tree = '<group>'
    end
  end

  # 2. Handle Flavored Files
  flavors.each do |flavor|
    filename = "#{flavor}.xcconfig"
    file_path = File.expand_path("ios/Flutter/#{filename}")
    next unless File.exist?(file_path)

    file_ref = flutter_group.files.find { |f| f.path == filename } || 
               flutter_group.files.find { |f| File.basename(f.path) == filename }

    if file_ref
      unless file_ref.path == filename && file_ref.source_tree == '<group>'
        puts "🛠️  Healing flavored file path: #{filename}"
        file_ref.set_path(filename)
        file_ref.source_tree = '<group>'
      end
    else
      puts "➕ Adding missing flavored file reference: #{filename}"
      file_ref = flutter_group.new_reference(file_path)
      file_ref.set_path(filename)
      file_ref.source_tree = '<group>'
    end
  end
end

if reset_mode
  puts "🧹 Resetting project to standard state..."
  
  # Find all flavors to help cleanup
  existing_flavors = Dir.glob('ios/Flutter/*.xcconfig').map { |f| File.basename(f, '.xcconfig') } - ['Generated', 'Debug', 'Release', 'Profile']
  heal_flutter_group(project, flutter_group, existing_flavors)
  
  # Remove ALL flavored Build Configurations
  project.build_configurations.dup.each do |config_obj|
    if config_obj.name =~ /^(Debug|Release|Profile)-/
      config_obj.remove_from_project
    end
  end
  project.targets.each do |target|
    target.build_configurations.dup.each do |config_obj|
      if config_obj.name =~ /^(Debug|Release|Profile)-/
        config_obj.remove_from_project
      end
    end
  end
  
  # Remove flavored xcconfig references from Flutter group
  flutter_group.files.dup.each do |file_ref|
    name = File.basename(file_ref.path)
    if name.end_with?('.xcconfig') && !STANDARD_FILES.include?(name)
      puts "🗑️ Removing flavor file reference: #{name}"
      file_ref.remove_from_project
    end
  end
  
  # Remove ALL flavor schemes
  Dir.glob(Xcodeproj::XCScheme.shared_data_dir(project_path).join("*.xcscheme")).each do |scheme_path|
    scheme_name = File.basename(scheme_path, ".xcscheme")
    next if scheme_name == 'Runner'
    File.delete(scheme_path) if File.exist?(scheme_path)
  end

  # Get base information for restoration
  ios_config = config['ios'] || {}
  restored_bundle_id = ios_config['bundle_id']

  # 2. Reset base configs and clear flavored settings
  ['Debug', 'Release', 'Profile'].each do |base_name|
    default_xcconfig = base_name == 'Profile' ? 'Release.xcconfig' : "#{base_name}.xcconfig"
    file_ref = flutter_group.files.find { |f| f.path == default_xcconfig } || 
               flutter_group.files.find { |f| File.basename(f.path) == default_xcconfig }

    type = base_name == 'Debug' ? :debug : :release

    [project, *project.targets].each do |obj|
      config_obj = obj.build_configurations.find { |c| c.name == base_name }
      
      # Restoration: Recreate if missing
      unless config_obj
        puts "✔ Restoring Base Configuration: #{obj.respond_to?(:name) ? obj.name : 'Project'} [#{base_name}]"
        config_obj = obj.add_build_configuration(base_name, type)
      end

      if config_obj
        config_obj.base_configuration_reference = file_ref
        config_obj.build_settings.delete('FLAVOR_APP_NAME')
        config_obj.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
        
        # Restore standard Flutter settings
        config_obj.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
        if obj.respond_to?(:name)
          if obj.name == 'Runner'
            config_obj.build_settings['INFOPLIST_FILE'] = 'Runner/Info.plist'
            config_obj.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
            config_obj.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
            config_obj.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'Runner/Runner-Bridging-Header.h'
            config_obj.build_settings['SWIFT_VERSION'] = '5.0'
            config_obj.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
          elsif obj.name == 'RunnerTests'
            config_obj.build_settings['INFOPLIST_FILE'] = 'RunnerTests/Info.plist'
          end
        end

        # Ensure it's recognized as an iOS project
        config_obj.build_settings['SDKROOT'] = 'iphoneos'
        config_obj.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2' # iPhone, iPad
        config_obj.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
        
        if restored_bundle_id && !restored_bundle_id.empty?
          config_obj.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = restored_bundle_id
        end
        
        config_obj.build_settings.delete('FLUTTER_TARGET')
        config_obj.build_settings.delete('FLUTTER_FLAVOR')
      end
    end
  end

  # 3. Restore Runner Scheme from backup if it exists, otherwise recreate
  runner_scheme_path = Xcodeproj::XCScheme.shared_data_dir(project_path).join("Runner.xcscheme")
  backup_scheme_path = Xcodeproj::XCScheme.shared_data_dir(project_path).join("Runner.xcscheme.backup")
  
  if backup_scheme_path.exist?
    puts "✔ Restoring Base Scheme from backup: Runner"
    FileUtils.mv(backup_scheme_path, runner_scheme_path, force: true)
  elsif !runner_scheme_path.exist?
    puts "✔ Restoring Base Scheme: Runner (Recreated)"
    scheme = Xcodeproj::XCScheme.new
    runner_target = project.targets.find { |t| t.name == 'Runner' }
    if runner_target
      scheme.add_build_target(runner_target)
      runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new(runner_target, 0)
      scheme.launch_action.buildable_product_runnable = runnable
      scheme.profile_action.buildable_product_runnable = runnable
    end
    scheme.save_as(project_path, 'Runner')
  end

  project.save
  
  # Reset Podfile configurations
  podfile_path = 'ios/Podfile'
  if File.exist?(podfile_path)
    content = File.read(podfile_path)
    patched = false
    content.gsub!(/(project\s+'Runner',\s*\{)(.*?)(\})/m) do |match|
      patched = true
      "#{$1}\n  'Debug' => :debug,\n  'Profile' => :release,\n  'Release' => :release,\n#{$3}"
    end
    if patched
      File.write(podfile_path, content)
      puts "✔ Restored Base Podfile configurations"
    end
  end

  puts "✅ Xcode project reset successfully!"
  exit 0
end

# 3. Setup Logic (Create Build Configurations and Inject Settings)
heal_flutter_group(project, flutter_group, flavors)

flavors.each do |flavor|
  ['Debug', 'Release', 'Profile'].each do |base_config_name|
    target_config_name = get_config_name(base_config_name, flavor)
    
      # Ensure project-level config exists
      unless project.build_configurations.any? { |c| c.name == target_config_name }
        base_config = project.build_configurations.find { |c| c.name == base_config_name } ||
                      project.build_configurations.find { |c| c.name.start_with?("#{base_config_name}-") }
        if base_config
          puts "✔ Creating Project Configuration: #{target_config_name}"
          new_config = project.add_build_configuration(target_config_name, base_config.type)
          new_config.build_settings = base_config.build_settings.clone
        end
      end

      # Ensure target-level config exists for all targets
      project.targets.each do |target|
        unless target.build_configurations.any? { |c| c.name == target_config_name }
          base_target_config = target.build_configurations.find { |c| c.name == base_config_name } ||
                               target.build_configurations.find { |c| c.name.start_with?("#{base_config_name}-") }
          if base_target_config
            puts "✔ Creating Target Configuration: #{target.name} [#{target_config_name}]"
            new_target_config = target.add_build_configuration(target_config_name, base_target_config.type)
            new_target_config.build_settings = base_target_config.build_settings.clone
          end
        end
      end

    # Zero-XCConfig: Use base mapping and inject variables
    base_xcconfig_name = base_config_name == 'Profile' ? 'Release.xcconfig' : "#{base_config_name}.xcconfig"
    base_xcconfig_ref = flutter_group.files.find { |f| f.path == base_xcconfig_name } || 
                        flutter_group.files.find { |f| File.basename(f.path) == base_xcconfig_name }

    flavor_alias = (get_flavor_alias(flavor) || flavor).upcase
    base_app_name = config['app_name'] || 'MyApp'
    
    # Target Path Logic
    use_separate_mains = config['use_separate_mains'] != false
    flutter_target = use_separate_mains ? "lib/main/main_#{flavor}.dart" : "lib/main.dart"
    
    ios_config = config['ios'] || {}
    base_bundle_id = ios_config['bundle_id'] || 'com.example.app'
    flavored_bundle_id = get_flavored_bundle_id(base_bundle_id, flavor, config)
    
    # Project level injection
    config_obj = project.build_configurations.find { |c| c.name == target_config_name }
    if config_obj
      # Find flavored xcconfig reference
      flavor_xcconfig_ref = flutter_group.files.find { |f| f.path == "#{flavor}.xcconfig" } || 
                            flutter_group.files.find { |f| File.basename(f.path) == "#{flavor}.xcconfig" }
      
      if flavor_xcconfig_ref
        puts "🔗 Linking Project Configuration: #{target_config_name} -> #{flavor}.xcconfig"
        config_obj.base_configuration_reference = flavor_xcconfig_ref
      else
        puts "⚠️ Warning: #{flavor}.xcconfig not found in Flutter group. Mapping to base."
        config_obj.base_configuration_reference = base_xcconfig_ref
      end

      # Cleanup legacy direct injections
      config_obj.build_settings.delete('FLAVOR_APP_NAME')
      config_obj.build_settings.delete('FLUTTER_TARGET')
      config_obj.build_settings.delete('FLUTTER_FLAVOR')

      # Core settings using xcconfig variables
      config_obj.build_settings['BASE_BUNDLE_ID'] = base_bundle_id
      config_obj.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(BASE_BUNDLE_ID)$(BUNDLE_ID_SUFFIX)'
      config_obj.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = '$(APP_NAME)'
      config_obj.build_settings['PRODUCT_NAME'] = '$(APP_NAME)'
      config_obj.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    end

    # Target level injection
    project.targets.each do |target|
      target_config = target.build_configurations.find { |c| c.name == target_config_name }
      if target_config
        if target.name == 'Runner'
          # CRITICAL: We clear the target-level base configuration reference.
          # This allows CocoaPods to link its Pods-Runner.xxx.xcconfig here.
          # Since the Project-level is linked to dev.xcconfig, variables like
          # APP_NAME will still be inherited correctly.
          target_config.base_configuration_reference = nil

          # Cleanup legacy direct injections
          target_config.build_settings.delete('FLAVOR_APP_NAME')
          target_config.build_settings.delete('FLUTTER_TARGET')
          target_config.build_settings.delete('FLUTTER_FLAVOR')

          target_config.build_settings['BASE_BUNDLE_ID'] = base_bundle_id
          target_config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(BASE_BUNDLE_ID)$(BUNDLE_ID_SUFFIX)'
          target_config.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = '$(APP_NAME)'
          target_config.build_settings['PRODUCT_NAME'] = '$(APP_NAME)'
          target_config.build_settings['INFOPLIST_FILE'] = 'Runner/Info.plist'
          target_config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
          
          target_config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
          target_config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
          target_config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'Runner/Runner-Bridging-Header.h'
          target_config.build_settings['SWIFT_VERSION'] = '5.0'
          target_config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
        else
          target_config.base_configuration_reference = nil
          if target.name == 'RunnerTests'
            target_config.build_settings['INFOPLIST_FILE'] = 'RunnerTests/Info.plist'
            target_config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
          end
        end
      end
    end
  end
end

# 4. Cleanup Orphaned Configurations and Schemes
active_config_names = flavors.flat_map { |f| ['Debug', 'Release', 'Profile'].map { |b| get_config_name(b, f) } }
active_scheme_names = flavors.map { |f| get_scheme_name(f) }

# Remove orphaned configurations from Project
project.build_configurations.dup.each do |config|
  next if ['Debug', 'Release', 'Profile'].include?(config.name)
  if config.name =~ /^(Debug|Release|Profile)-/ && !active_config_names.include?(config.name)
    puts "🗑️ Removing orphaned Project Configuration: #{config.name}"
    config.remove_from_project
  end
end

# Remove orphaned configurations from Targets
project.targets.each do |target|
  target.build_configurations.dup.each do |config|
    next if ['Debug', 'Release', 'Profile'].include?(config.name)
    if config.name =~ /^(Debug|Release|Profile)-/ && !active_config_names.include?(config.name)
      puts "🗑️ Removing orphaned Target Configuration: #{target.name} [#{config.name}]"
      config.remove_from_project
    end
  end
end

# 4.5. Remove Base Configurations if flavors exist
unless flavors.empty?
  ['Debug', 'Release', 'Profile'].each do |base_name|
    puts "🗑️ Removing base configuration: #{base_name}"
    project.build_configurations.find { |c| c.name == base_name }&.remove_from_project
    project.targets.each do |target|
      target.build_configurations.find { |c| c.name == base_name }&.remove_from_project
    end
  end
end

# Remove orphaned schemes
Dir.glob(Xcodeproj::XCScheme.shared_data_dir(project_path).join("*.xcscheme")).each do |scheme_path|
  scheme_name = File.basename(scheme_path, ".xcscheme")
  
  # Remove base Runner scheme if flavors exist
  if scheme_name == 'Runner' && !flavors.empty?
    backup_path = scheme_path.to_s + ".backup"
    unless File.exist?(backup_path)
      puts "📦 Backing up base scheme: Runner"
      FileUtils.cp(scheme_path, backup_path)
    end
    puts "🗑️ Removing base scheme: Runner"
    File.delete(scheme_path) if File.exist?(scheme_path)
    next
  end

  # Skip standard Runner scheme security skip
  next if scheme_name == 'Runner'
  
  unless active_scheme_names.include?(scheme_name)
    puts "🗑️ Removing orphaned Scheme: #{scheme_name}"
    File.delete(scheme_path) if File.exist?(scheme_path)
  end
end

# 5. Path Healing: DEPRECATED (Moved to heal_flutter_group helper and called in reset/init)


# 5. Scheme Creation
flavors.each do |flavor|
  scheme_name = get_scheme_name(flavor)
  
  puts "✔ Creating Scheme: #{scheme_name}"
  
  # Clone from Runner.xcscheme (or its backup) to inherit correct platform/executable settings
  # We always regenerate flavor schemes to ensure the naming/branding is updated
  runner_scheme_path = Xcodeproj::XCScheme.shared_data_dir(project_path).join("Runner.xcscheme")
  backup_scheme_path = Xcodeproj::XCScheme.shared_data_dir(project_path).join("Runner.xcscheme.backup")
  
  template_path = runner_scheme_path.exist? ? runner_scheme_path : (backup_scheme_path.exist? ? backup_scheme_path : nil)
  
  if template_path
    scheme = Xcodeproj::XCScheme.new(template_path)
  else
    scheme = Xcodeproj::XCScheme.new
    runner_target = project.targets.find { |t| t.name == 'Runner' }
    if runner_target
      scheme.add_build_target(runner_target)
      runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new(runner_target, 0)
      scheme.launch_action.buildable_product_runnable = runnable
      scheme.profile_action.buildable_product_runnable = runnable
    end
  end
  
  # Set configurations for all actions
  name = (get_flavor_alias(flavor) || flavor).upcase
  scheme.launch_action.build_configuration = "Debug-#{name}"
  scheme.test_action.build_configuration = "Debug-#{name}"
  scheme.profile_action.build_configuration = "Profile-#{name}"
  scheme.analyze_action.build_configuration = "Debug-#{name}"
  scheme.archive_action.build_configuration = "Release-#{name}"
  
  # Deep Branding: Ensure every BuildableReference points to our branded binary
  branded_binary = "$(APP_NAME).app"
  
  # Update all buildable references in the scheme
  scheme.build_action.entries.each do |entry|
    entry.buildable_references.each do |ref|
      if (ref.respond_to?(:blueprint_name) ? ref.blueprint_name : ref.xml_element.attributes['BlueprintName']) == 'Runner'
        ref.buildable_name = branded_binary
      end
    end
  end
  
  if scheme.launch_action.buildable_product_runnable
    scheme.launch_action.buildable_product_runnable.buildable_reference.buildable_name = branded_binary
  end
  
  if scheme.profile_action.buildable_product_runnable
    scheme.profile_action.buildable_product_runnable.buildable_reference.buildable_name = branded_binary
  end

  # Save first
  scheme.save_as(project_path, scheme_name)
end
  
# 6. Base Config Reset
['Debug', 'Release', 'Profile'].each do |base_name|
  default_xcconfig = base_name == 'Profile' ? 'Release.xcconfig' : "#{base_name}.xcconfig"
  file_ref = flutter_group.files.find { |f| f.path == default_xcconfig } || 
             flutter_group.files.find { |f| File.basename(f.path) == default_xcconfig }

  project.build_configurations.find { |c| c.name == base_name }&.base_configuration_reference = file_ref
  project.targets.each do |target|
    target.build_configurations.find { |c| c.name == base_name }&.base_configuration_reference = file_ref
  end
end

# 7. Sanitization: Remove orphaned file refs from Flutter group
expected_files = STANDARD_FILES # In Zero-XCConfig mode, only standard files should be in the group
flutter_group.files.each do |file|
  next if expected_files.include?(file.path) || expected_files.include?(File.basename(file.path))
  # Keep flavored xcconfigs if they somehow still exist (though Zero-XCConfig should have cleaned them)
  next if file.path =~ /#{flavors.join('|')}\.xcconfig/
  
  puts "🗑️ Removing orphaned file reference: #{file.path}"
  file.remove_from_project
end

project.save
puts "Configured schemes and configurations recursively."

# Update Podfiles
podfile_path = 'ios/Podfile'
if File.exist?(podfile_path)
  content = File.read(podfile_path)
  
  configs_str = "\n  'Debug' => :debug,\n  'Profile' => :release,\n  'Release' => :release,"
  flavors.each do |flavor|
    name = (get_flavor_alias(flavor) || flavor).upcase
    configs_str += "\n  'Debug-#{name}' => :debug,"
    configs_str += "\n  'Profile-#{name}' => :release,"
    configs_str += "\n  'Release-#{name}' => :release,"
  end
  configs_str += "\n"
  
  patched = false
  content.gsub!(/(project\s+'Runner',\s*\{)(.*?)(\})/m) do |match|
    patched = true
    "#{$1}#{configs_str}#{$3}"
  end
  
  if patched
    File.write(podfile_path, content)
    puts "Updated iOS Podfile with flavor configurations."
  else
    puts "iOS Podfile 'project Runner' block not found. Skipping."
  end
end

''';
  }

  static void reset({AppLogger? logger}) {
    final log = logger ?? AppLogger();
    _resetInfoPlist(log);
    _healRunnerScheme(log);
    // We need to pass --reset explicitly
    _runRubyAutomationWithReset(log);

    // Crucial: CocoaPods MUST be synced after configurations change
    syncPods(logger: log);

    log.success('✔ iOS flavor configuration removed');
  }

  static void _healRunnerScheme(AppLogger log) {
    final root = ConfigService.root;
    final schemePath = p.join(
        root, 'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme');
    final file = File(schemePath);
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();
    // Restore any corrupted .app or .xctest names in the main Runner scheme
    if (content.contains('BuildableName = ".app"') ||
        content.contains('BuildableName = ".xctest"')) {
      content = content.replaceAll(
          'BuildableName = ".app"', 'BuildableName = "Runner.app"');
      content = content.replaceAll(
          'BuildableName = ".xctest"', 'BuildableName = "RunnerTests.xctest"');
      file.writeAsStringSync(content);
      log.info('   🩹 Healed Runner.xcscheme');
    }

    // Also delete any weird unnamed .xcscheme
    final dotScheme = File(
        p.join(root, 'ios/Runner.xcodeproj/xcshareddata/xcschemes/.xcscheme'));
    if (dotScheme.existsSync()) {
      dotScheme.deleteSync();
      log.info('   🗑️ Removed corrupted .xcscheme');
    }
  }

  static void _resetInfoPlist(AppLogger log) {
    final plistPath = p.join(ConfigService.root, 'ios/Runner/Info.plist');
    final file = File(plistPath);
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();
    final appName = ConfigService.getAppName();

    // Restore CFBundleDisplayName and CFBundleName
    content = content.replaceAll(
        RegExp(r'<key>CFBundleDisplayName</key>\s*<string>.*?</string>'),
        '<key>CFBundleDisplayName</key>\n\t<string>$appName</string>');
    content = content.replaceAll(
        RegExp(r'<key>CFBundleName</key>\s*<string>.*?</string>'),
        '<key>CFBundleName</key>\n\t<string>$appName</string>');

    // Restore CFBundleIdentifier to use variable
    final dollar = String.fromCharCode(36);
    content = content.replaceAll(
        RegExp(r'<key>CFBundleIdentifier</key>\s*<string>.*?</string>'),
        '<key>CFBundleIdentifier</key>\n\t<string>$dollar(PRODUCT_BUNDLE_IDENTIFIER)</string>');

    file.writeAsStringSync(content);
  }

  static void _brandSchemes(AppLogger log) {
    final root = ConfigService.root;
    final flavors = ConfigService.getFlavors();
    if (flavors.isEmpty) return;

    final baseAppName = ConfigService.getAppName();

    final schemeDir =
        Directory(p.join(root, 'ios/Runner.xcodeproj/xcshareddata/xcschemes'));
    if (!schemeDir.existsSync()) return;

    for (final flavor in flavors) {
      final alias = _getAliasSync(flavor);
      final schemeName =
          alias.toUpperCase(); // Schemes are always uppercase alias/name

      if (schemeName == 'RUNNER')
        continue; // Safety: Never touch the main Runner scheme

      final name = _getBrandedName(baseAppName, flavor);
      if (name.isEmpty) continue;

      final brandedBinary = '$name.app';

      final schemeFile = File(p.join(schemeDir.path, '$schemeName.xcscheme'));
      if (schemeFile.existsSync()) {
        var content = schemeFile.readAsStringSync();
        // Look for any BuildableName that is either empty, Runner.app, or just .app
        // and replace it with the correct branded binary name.
        final regex = RegExp(r'BuildableName = "([^"]*\.app)"');
        if (regex.hasMatch(content)) {
          content =
              content.replaceAll(regex, 'BuildableName = "$brandedBinary"');
          schemeFile.writeAsStringSync(content);
          log.info('   ⚓ Final Sweep: $schemeName branded as $brandedBinary');
        }
      }
    }
  }

  static String _getBrandedName(String baseName, String flavor) {
    final productionFlavor = ConfigService.getProductionFlavor();
    if (flavor == productionFlavor) {
      return baseName;
    }
    return '$baseName-$flavor';
  }

  static String _getAliasSync(String flavor) {
    final configPath = p.join(ConfigService.root, '.flavor_cli.json');
    final file = File(configPath);
    if (file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final config = jsonDecode(content) as Map<String, dynamic>;
        final flavorsList = config['flavors'] as List<dynamic>?;
        if (flavorsList != null) {
          for (final f in flavorsList) {
            if (f is Map && f['name'] == flavor) {
              final alias = f['alias'];
              if (alias != null && alias.toString().isNotEmpty) {
                return alias.toString();
              }
            }
          }
        }
      } catch (_) {}
    }

    if (flavor == 'staging') return 'stage';
    return flavor;
  }

  static void removeFlavorSchemes(String flavor, {AppLogger? logger}) {
    final log = logger ?? AppLogger();
    _runRubyAutomationWithDelete(log, flavor);
    syncPods(logger: log);
    log.success('✔ iOS flavor cleanup completed');
  }

  static void _runRubyAutomationWithReset(AppLogger log) {
    final tempDir = Directory.systemTemp.createTempSync('flavor_cli_reset_');
    final scriptFile = File(p.join(tempDir.path, 'ios_flavor_setup.rb'));
    scriptFile.writeAsStringSync(_iosAutomationScriptContent());

    try {
      _runRubyAutomation(
          log: log, scriptPath: scriptFile.path, args: ['--reset']);
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  static void _runRubyAutomationWithDelete(AppLogger log, String flavor) {
    final tempDir = Directory.systemTemp.createTempSync('flavor_cli_delete_');
    final scriptFile = File(p.join(tempDir.path, 'ios_flavor_setup.rb'));
    scriptFile.writeAsStringSync(_iosAutomationScriptContent());

    try {
      _runRubyAutomation(
          log: log, scriptPath: scriptFile.path, args: ['--delete', flavor]);
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  static void _runRubyAutomation(
      {required AppLogger log,
      required String scriptPath,
      List<String> args = const []}) {
    // Check if xcodeproj is installed
    final checkResult = Process.runSync(
      'ruby',
      ['-e', 'require "xcodeproj"'],
      runInShell: true,
    );

    if (checkResult.exitCode != 0) {
      throw Exception(
        'The "xcodeproj" gem is missing. Please install it to automate iOS setup:\n'
        '  gem install xcodeproj --user-install\n'
        'Then run "init" again.',
      );
    }

    final result = Process.runSync(
      'ruby',
      [scriptPath, ...args],
      runInShell: true,
      workingDirectory: ConfigService.root,
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr);
    }

    if (result.stdout.toString().trim().isNotEmpty) {
      log.info(result.stdout.toString().trim());
    }
  }

  /// Sync CocoaPods configurations with the current Xcode project state.
  /// Runs `pod install` in the ios directory if a Podfile is present.
  static void syncPods({AppLogger? logger}) {
    _syncCocoaPods(logger ?? AppLogger());
  }

  static void _syncCocoaPods(AppLogger log, {bool isRetry = false}) {
    final root = ConfigService.root;
    final iosDir = Directory(p.join(root, 'ios'));
    final podfile = File(p.join(iosDir.path, 'Podfile'));

    if (!podfile.existsSync()) return;

    log.info('📦 Running pod install to update CocoaPods configurations...');

    try {
      // Check if pod is installed
      final checkResult = Process.runSync('which', ['pod'], runInShell: true);
      if (checkResult.exitCode != 0) {
        log.warn(
            '⚠️ CocoaPods "pod" command not found. Please run "pod install" manually in the ios folder.');
        return;
      }

      final result = Process.runSync(
        'pod',
        ['install'],
        workingDirectory: iosDir.path,
        runInShell: true,
        environment: {
          ...Platform.environment,
          'LANG': 'en_US.UTF-8',
          'LC_ALL': 'en_US.UTF-8',
        },
      );

      if (result.exitCode != 0) {
        final stderr = result.stderr.toString();
        final stdout = result.stdout.toString();
        final combinedOutput = '$stderr\n$stdout'.trim();

        log.error('❌ pod install failed:');
        if (combinedOutput.isNotEmpty) {
          log.info(combinedOutput);
        }

        if (combinedOutput.contains('Ignoring ffi') ||
            combinedOutput.contains('extensions are not built')) {
          log.info('💡 Tip: Your Ruby FFI gem seems broken.');

          if (!isRetry) {
            final fixConfirmed = log.confirm(
                '👉 Would you like to try fixing this automatically by reinstalling CocoaPods via Homebrew?',
                defaultValue: true);

            if (fixConfirmed) {
              log.info('🛠️ Reinstalling CocoaPods... (This may take a few minutes, this is a one-time operation)');
              final brewResult = Process.runSync('brew', ['reinstall', 'cocoapods'], runInShell: true);
              
              if (brewResult.exitCode == 0) {
                log.success('✅ CocoaPods reinstalled successfully.');
                log.info('🔄 Retrying pod install...');
                _syncCocoaPods(log, isRetry: true);
                return;
              } else {
                log.error('❌ brew reinstall failed: ${brewResult.stderr}');
                log.info('   Please try running: gem pristine ffi');
              }
            } else {
              log.info('   Recommended fix: gem pristine ffi');
            }
          }
        } else if (combinedOutput.contains('flutter precache --ios')) {
          log.info('💡 Tip: Flutter iOS artifacts are missing.');

          if (!isRetry) {
            final fixConfirmed = log.confirm(
                '👉 Would you like to run "flutter precache --ios" to download them and retry?',
                defaultValue: true);

            if (fixConfirmed) {
              log.info('🛠️ Downloading Flutter iOS artifacts... (This may take a few minutes, this is a one-time operation)');
              final precacheResult =
                  Process.runSync('flutter', ['precache', '--ios'], runInShell: true);

              if (precacheResult.exitCode == 0) {
                log.success('✅ Flutter artifacts downloaded successfully.');
                log.info('🔄 Retrying pod install...');
                _syncCocoaPods(log, isRetry: true);
                return;
              } else {
                log.error('❌ flutter precache failed: ${precacheResult.stderr}');
              }
            }
          }
        } else if (combinedOutput.contains('Unicode Normalization') || 
                   combinedOutput.contains('ASCII-8BIT')) {
          log.info('💡 Tip: This is a Locale encoding issue.');
          log.info('   Try adding "export LANG=en_US.UTF-8" to your ~/.zshrc or ~/.zshenv');
        } else if (combinedOutput.contains('curl') || combinedOutput.contains('SSL')) {
          log.info('💡 Tip: This looks like a network or certificate issue.');
        } else if (combinedOutput.contains('out of date')) {
          log.info('💡 Tip: Try running: pod repo update');
        }
      } else {
        log.info('   ✓ CocoaPods updated');
      }
    } catch (e) {
      log.warn('⚠️ Could not run pod install: $e');
    }
  }
}
