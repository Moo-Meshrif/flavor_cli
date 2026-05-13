# Changelog

## 0.0.8

*   **ENV-Only Architecture**: Fully transitioned from JSON-based runtime configuration to a strictly ENV-based model using `flutter_dotenv`.
*   **Configuration Modernization**: Migration from `.flavor_cli.json` to `flavor_cli.yaml` for better readability and industry standards.
*   **Automatic Dependency Injection**: The CLI now automatically manages the `flutter_dotenv` dependency, asset registration, and `.gitignore` entries.
*   **Enhanced Migration Command**: Completely revamped `migrate` command to handle legacy JSON to YAML conversion and runtime value migration to `.env` files.
*   **Clean Source of Truth**: Dynamic runtime values are now isolated in protected `.env` files, keeping `flavor_cli.yaml` focused on static project metadata.

## 0.0.7

*   **Main File Preservation**: Automatically preserves existing `main.dart` content when migrating to the "Separate Main Files" strategy by moving it to the production flavor entry point.
*   **Enhanced Reset Command**: The `reset` command now restores original code from flavor entry points back to `main.dart`, ensuring no code is lost when reverting flavor setups.
*   **Smart Firebase Detection**: Improved `ConfigService` to distinguish between Firebase configuration and project integration, enabling more accurate setup prompts.
*   **Automated Firebase Integration**: The CLI now detects missing Firebase files in configured projects and offers to run the integration automatically during flavor additions or resets.
*   **Internal Refinements**: Refactored `SetupRunner` and `FileService` for more robust file handling and synchronization.

## 0.0.6

*   **Fixed Main File Generation**: Resolved an issue where adding a new flavor with the "Separate Main Files" strategy failed to generate the required Dart entry point.
*   **Firebase Optimization**: Optimized the Firebase setup flow to skip redundant re-initialization prompts for projects using "Shared ID" strategies.
*   **Targeted Commands**: Applied Firebase optimizations specifically to the `add` and `replace` commands to avoid interrupting common flavor management workflows.
*   **Refined Firebase Replacement**: When renaming a flavor in "Unique ID" projects, old options are now automatically deleted and entry points are sanitized to ensure a clean re-initialization process.
*   **Deletion Optimization**: Added a bypass for Firebase re-initialization prompts during flavor deletions to streamline the cleanup process.
*   **Simplified Project Structure**: Disabled the automatic generation of the `scripts/` folder by default to ensure a cleaner project root.
*   **Internal Robustness**: Enhanced `SetupRunner` and `FirebaseCommand` to maintain better context during flavor additions and renames.

## 0.0.5

*   **Enhanced documentation**: Make it more concise and clear.

## 0.0.4

*   **Code Generation Improvements**: Added "// GENERATED CODE - DO NOT MODIFY BY HAND" headers and removed redundant TODOs in the generated `AppConfig`.
*   **Enhanced Reset Command**: Improved the `reset` command to be more resilient by allowing it to run even when the configuration file is partially invalid.
*   **Documentation Cleanup**: Streamlined the main `README.md` and example documentation for improved clarity and conciseness.
*   **Internal Refinements**: Added support for bypassing validation in `ConfigService` when performing cleanup or reset operations.

## 0.0.3

*   **Migration Support**: Added `migrate` command to safely upgrade existing `.flavor_cli.json` files to the latest format, including filling in missing per-flavor values.
*   **Non-Interactive Initialization**: Enhanced `init` command to support `--from` for fully automated setups by persisting all configuration values in `.flavor_cli.json`.
*   **Package ID Strategy**: Added `package_id_strategy` to support unique IDs or shared IDs for flavors.

## 0.0.2

*   **Android & iOS Focus**: Restricted the CLI to strictly support Android and iOS environments.
*   **Enhanced Documentation**: Updated the example project with a new README.

## 0.0.1

* Initial release of `flavor_cli`.
