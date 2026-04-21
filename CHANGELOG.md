# Changelog

## 0.0.3

*   **Migration Support**: Added `migrate` command to safely upgrade existing `.flavor_cli.json` files to the latest format, including filling in missing per-flavor values.
*   **Non-Interactive Initialization**: Enhanced `init` command to support `--from` for fully automated setups by persisting all configuration values in `.flavor_cli.json`.
*   **Package ID Strategy**: Added `package_id_strategy` to support unique IDs or shared IDs for flavors.

## 0.0.2

*   **Android & iOS Focus**: Restricted the CLI to strictly support Android and iOS environments.
*   **Enhanced Documentation**: Updated the example project with a new README.

## 0.0.1

* Initial release of `flavor_cli`.
