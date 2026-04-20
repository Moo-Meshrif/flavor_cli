require 'xcodeproj'
require 'fileutils'
require 'json'

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

# Helper to get flavored app name (Production = base, others = base-flavor)
def get_flavored_app_name(base_name, flavor, config)
  production_flavor = config['production_flavor']
  
  # Fallback logic if production_flavor is missing from config
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

  if flavor == production_flavor
    return base_name
  else
    return "#{base_name}-#{flavor}"
  end
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
if ARGV.include?('--delete')
  delete_flavor = ARGV[ARGV.index('--delete') + 1]
  flavors = []
elsif ARGV.include?('--reset')
  reset_mode = true
  flavors = []
else
  config_path = '.flavor_cli.json'
  if File.exist?(config_path)
    config = JSON.parse(File.read(config_path))
    raw_flavors = config['flavors'] || []
    # Handle both [ "dev", "prod" ] and [ { "name": "dev" }, { "name": "prod" } ]
    flavors = raw_flavors.map { |f| f.is_a?(Hash) ? f['name'] : f }.compact
  else
    puts "❌ .flavor_cli.json not found. Run 'init' first."
    exit 1
  end
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

if reset_mode
  puts "🧹 Resetting project to standard state..."
  
  # Remove ALL flavored Build Configurations
  project.build_configurations.dup.each do |config|
    if config.name =~ /^(Debug|Release|Profile)-/
      config.remove_from_project
    end
  end
  project.targets.each do |target|
    target.build_configurations.dup.each do |config|
      if config.name =~ /^(Debug|Release|Profile)-/
        config.remove_from_project
      end
    end
  end
  
  # Remove ALL flavor schemes
  Dir.glob(Xcodeproj::XCScheme.shared_data_dir(project_path).join("*.xcscheme")).each do |scheme_path|
    scheme_name = File.basename(scheme_path, ".xcscheme")
    next if scheme_name == 'Runner'
    File.delete(scheme_path) if File.exist?(scheme_path)
  end

  # Reset base configs and clear flavored settings
  ['Debug', 'Release', 'Profile'].each do |base_name|
    default_xcconfig = base_name == 'Profile' ? 'Release.xcconfig' : "#{base_name}.xcconfig"
    file_ref = flutter_group.files.find { |f| f.path == default_xcconfig } || 
               flutter_group.files.find { |f| File.basename(f.path) == default_xcconfig }

    [project, *project.targets].each do |obj|
      config = obj.build_configurations.find { |c| c.name == base_name }
      if config
        config.base_configuration_reference = file_ref
        config.build_settings.delete('FLAVOR_APP_NAME')
        config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
        config.build_settings.delete('PRODUCT_BUNDLE_IDENTIFIER')
        config.build_settings.delete('FLUTTER_TARGET')
        config.build_settings.delete('FLUTTER_FLAVOR')
      end
    end
  end

  project.save
  puts "✅ Xcode project reset successfully!"
  exit 0
end

# 3. Setup Logic (Create Build Configurations and Inject Settings)
flavors.each do |flavor|
  ['Debug', 'Release', 'Profile'].each do |base_config_name|
    target_config_name = get_config_name(base_config_name, flavor)
    
    # Ensure project-level config exists
    unless project.build_configurations.any? { |c| c.name == target_config_name }
      base_config = project.build_configurations.find { |c| c.name == base_config_name }
      if base_config
        puts "✔ Creating Project Configuration: #{target_config_name}"
        new_config = project.add_build_configuration(target_config_name, base_config.type)
        new_config.build_settings = base_config.build_settings.clone
      end
    end

    # Ensure target-level config exists for all targets
    project.targets.each do |target|
      unless target.build_configurations.any? { |c| c.name == target_config_name }
        base_target_config = target.build_configurations.find { |c| c.name == base_config_name }
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
    flavored_app_name = get_flavored_app_name(base_app_name, flavor, config)
    
    # Target Path Logic
    use_separate_mains = config['use_separate_mains'] != false
    flutter_target = use_separate_mains ? "lib/main/main_#{flavor}.dart" : "lib/main.dart"
    
    ios_config = config['ios'] || {}
    base_bundle_id = ios_config['bundle_id'] || 'com.example.app'
    flavored_bundle_id = get_flavored_bundle_id(base_bundle_id, flavor, config)
    
    # Project level injection
    config_obj = project.build_configurations.find { |c| c.name == target_config_name }
    if config_obj
      config_obj.base_configuration_reference = nil
      config_obj.build_settings.delete('APP_NAME') # Legacy cleanup
      config_obj.build_settings.delete('FLAVOR') # Not used cleanup
      config_obj.build_settings['FLAVOR_APP_NAME'] = flavored_app_name
      config_obj.build_settings['PRODUCT_NAME'] = flavored_app_name
      config_obj.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = flavored_bundle_id
      
      # Flutter Build Orchestration
      config_obj.build_settings['FLUTTER_TARGET'] = flutter_target
      config_obj.build_settings['FLUTTER_FLAVOR'] = flavor
    end

    # Target level injection
    project.targets.each do |target|
      target_config = target.build_configurations.find { |c| c.name == target_config_name }
      if target_config
        if target.name == 'Runner'
          target_config.base_configuration_reference = base_xcconfig_ref
          target_config.build_settings.delete('APP_NAME') # Legacy cleanup
          target_config.build_settings.delete('FLAVOR') # Not used cleanup
          target_config.build_settings['FLAVOR_APP_NAME'] = flavored_app_name
          target_config.build_settings['PRODUCT_NAME'] = flavored_app_name
          target_config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = flavored_bundle_id
          
          # Flutter Build Orchestration
          target_config.build_settings['FLUTTER_TARGET'] = flutter_target
          target_config.build_settings['FLUTTER_FLAVOR'] = flavor
        else
          target_config.base_configuration_reference = nil
          # Still set flavor for other targets if needed (e.g. extensions)
          target_config.build_settings['FLUTTER_FLAVOR'] = flavor
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

# Remove orphaned schemes
Dir.glob(Xcodeproj::XCScheme.shared_data_dir(project_path).join("*.xcscheme")).each do |scheme_path|
  scheme_name = File.basename(scheme_path, ".xcscheme")
  # Skip standard Runner scheme
  next if scheme_name == 'Runner'
  
  unless active_scheme_names.include?(scheme_name)
    puts "🗑️ Removing orphaned Scheme: #{scheme_name}"
    File.delete(scheme_path) if File.exist?(scheme_path)
  end
end

# 5. Path Healing: Ensure standard Flutter files are correctly referenced
standard_files = ['Generated.xcconfig', 'Debug.xcconfig', 'Release.xcconfig', 'AppFrameworkInfo.plist']
standard_files.each do |filename|
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

# 5. Scheme Creation
flavors.each do |flavor|
  scheme_name = get_scheme_name(flavor)
  
  puts "✔ Creating Scheme: #{scheme_name}"
  
  # Clone from Runner.xcscheme if possible to inherit correct executable/settings
  # We always regenerate flavor schemes to ensure the naming/branding is updated
  runner_scheme_path = Xcodeproj::XCScheme.shared_data_dir(project_path).join("Runner.xcscheme")
  if runner_scheme_path.exist?
    scheme = Xcodeproj::XCScheme.new(runner_scheme_path)
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
  base_app_name = config['app_name'] || 'MyApp'
  flavored_app_name = get_flavored_app_name(base_app_name, flavor, config)
  branded_binary = "#{flavored_app_name}.app"
  
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
expected_files = standard_files # In Zero-XCConfig mode, only standard files should be in the group
flutter_group.files.each do |file|
  next if expected_files.include?(file.path) || expected_files.include?(File.basename(file.path))
  # Keep flavored xcconfigs if they somehow still exist (though Zero-XCConfig should have cleaned them)
  next if file.path =~ /#{flavors.join('|')}\.xcconfig/
  
  puts "🗑️ Removing orphaned file reference: #{file.path}"
  file.remove_from_project
end

project.save
