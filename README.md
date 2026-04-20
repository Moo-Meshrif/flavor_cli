# 🍹 Flavor CLI

**Transform any Flutter project into a multi-environment powerhouse in seconds.**


`flavor_cli` is a production-grade automation tool that handles the heavy lifting of build flavor configuration. Stop manually editing `build.gradle` or Xcode schemes; focus on shipping features instead.

---

## ✨ Key Features

### 🛡️ Resilient & Type-Safe

*   **Zero-Guess Configuration**: Auto-generates a type-safe `AppConfig` class with typed variables (`String`, `bool`, `int`, `double`).
*   **Project Safety**: Interactive `delete` and `replace` commands ensure your project remains buildable. Revert instantly with a **`reset`** command.

### 📦 Flexible Architecture
*   **Automatic Isolation**: Automatically configures unique internal suffixes (e.g., `.dev`, `.beta`) to allow parallel app installations on the same device.
*   **Smart Patterns**: Seamlessly supports both the professional **"Separate Mains"** pattern and the classic **"Single Main"** approach.
*   **IDE Integration**: Automatically generates and maintains VS Code `launch.json` configurations for each flavor, allowing you to run any environment directly from your IDE.


---

## 🚀 Getting Started

### 1. Installation

Add `flavor_cli` to your `dev_dependencies`:

```bash
flutter pub add dev:flavor_cli
```

### 2. Initialization

Launch the interactive wizard to bootstrap your project:

```bash
dart run flavor_cli init
```

### 3. Usage Overview

```text
Usage: flavor_cli <command> [arguments]

Commands:
  init     Initialize flavor setup in your project
  add      Add a new flavor to an existing setup
  delete   Remove an existing flavor
  replace  Rename an existing flavor
  reset    Cleanup project from any flavors and revert to standard state
  run      Run the project with a specific flavor
  build    Build the project with a specific flavor
  firebase Setup Firebase for all flavors automatically

Examples:
  dart run flavor_cli init
  dart run flavor_cli add staging
  dart run flavor_cli replace
  dart run flavor_cli reset
  dart run flavor_cli run dev
  dart run flavor_cli build apk prod
  dart run flavor_cli firebase
```

> [!TIP]
> **See it in action**: Check out the [example](example/) project for a pre-configured implementation.

---

## 🛠️ Command Deep Dive

### `1. init`
**The wizard will guide you through:**
1.  **Flavor Selection**: Choose standard sets (dev, prod) or enter manually.
2.  **Schema Definition**: Define your `AppConfig` variables (e.g., `String baseUrl`).
3.  **Config Location**: Specify where your generated configuration file should live.
4.  **Main Strategy**: Choose between **Separate Mains** (one file per flavor) or **Single Main**.
5.  **App Branding**: Set the display name for your application (auto-detected).
6.  **Production Identity**: Identify which flavor is your "Golden" production build.
7.  **Package ID**: Set your base application identifier (auto-detected from Gradle).

> [!NOTE]
> **Zero-Config Isolation**: `flavor_cli` now automatically applies unique package identifiers for each flavor to ensure they can be installed side-by-side on devices.

---

### `2. add`
Add a new environment to an existing setup without re-initializing.
*   **The wizard will guide you through:** Prompting for the flavor name if not provided as an argument.
*   **Outcome**: Generates new `.xcconfig`, updates Android flavors, and adds the flavor to your `AppConfig` enum.

---

### `3. delete`
Safely remove a flavor and its associated artifacts.
*   **The wizard will guide you through:** Selecting the flavor to remove.
*   **Safety First**: If deleting a flavor would leave only one remaining, the tool warns you of system damage and offers a full **Project Reset**.
*   **Identity Migration**: If you delete your production flavor, you'll be prompted to nominate a new one.

---

### `4. replace`
Rename an existing flavor across the entire project.
*   **The wizard will guide you through:** 
    1. Selecting the old flavor.
    2. Entering the new name.
*   **Outcome**: Renames files, updates class definitions, and migrates Xcode schemes/schematics automatically.

---

### `5. reset`
*   **Action**: Reverts your project to its original, non-flavored state.
*   **Cleanup**: Removes all flavor mains, XCConfigs, generated scripts, and reverts `build.gradle` and Xcode project settings.

---

### `6. run`
Standardized wrapper for the `flutter run` command.
*   **The wizard will guide you through:** 
    1. Selecting the flavor (if not provided).
    2. Selecting the build mode (**debug**, **release**, or **profile**).
*   **Outcome**: Launches the app on your selected device with the correct flavor and entry point.

---

### `7. build`
High-level wrapper for the `flutter build` command.
*   **The wizard will guide you through:** 
    1. Selecting the build target (**apk**, **ipa**, **appbundle**, etc.) if not provided.
    2. Selecting the flavor to build.
*   **Outcome**: Generates a production-ready binary for the specified platform.

---

### `8. firebase`
**The "One-Pass" Firebase orchestrator.**
*   **The wizard will guide you through:** 
    1. Selecting your Firebase project strategy.
    2. Entering your Firebase Project IDs.
*   **Outcome**: 
    1. Automatically resets and authenticates via `firebase login`.
    2. Runs `flutterfire configure` for every flavor with correct mappings.
    3. **Automated Initialization**: Injects Firebase setup code and imports into your `main` files automatically.

---

## 💡 Pro Tips

### Separate Mains Pattern
By default, `flavor_cli` creates separate main files (e.g., `lib/main/main_dev.dart`). This is the **safest** way to handle flavors as it ensures environment-specific code is only compiled for that specific flavor.

---

## 📚 Guides

*   **[Firebase Integration](doc/FIREBASE.md)** - A step-by-step guide to using Firebase CLI with flavors.
*   **[Manual Setup Guide](doc/MANUAL_SETUP.md)** - A beginner-friendly reference for manual flavor configuration on Android and iOS.

## 🤝 Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.


