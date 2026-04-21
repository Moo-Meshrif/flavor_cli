# 🍹 Flavor CLI

**Transform any Flutter project into a multi-environment powerhouse in seconds.**

`flavor_cli` is a production-grade automation tool that handles the heavy lifting of build flavor configuration. Stop manually editing `build.gradle` or Xcode schemes; focus on shipping features instead.

---

## ✨ Key Features

### 🛡️ Resilient & Type-Safe

- **Zero-Guess Configuration**: Auto-generates a type-safe `AppConfig` class with typed variables (`String`, `bool`, `int`, `double`), with per-flavor values defined at init time.
- **Project Safety**: Interactive `delete` and `replace` commands ensure your project remains buildable. `replace` uses a pre-flight snapshot for atomic, rollback-capable renames. Revert instantly with a **`reset`** command.
- **Strict Validation**: Every command validates `.flavor_cli.json` on load — missing fields, invalid Firebase strategies, and mismatched flavor values all fail fast with clear, actionable error messages.

### 📦 Flexible Architecture

- **Automatic Isolation**: Automatically configures unique internal suffixes (e.g., `.dev`, `.beta`) to allow parallel app installations on the same device.
- **Smart Patterns**: Seamlessly supports both the professional **"Separate Mains"** pattern and the classic **"Single Main"** approach.
- **IDE Integration**: Automatically generates and maintains VS Code `launch.json` configurations for each flavor, allowing you to run any environment directly from your IDE.

---

## 🚀 Getting Started

### 1. Installation

Add `flavor_cli` to your `dev_dependencies`:

```bash
flutter pub add dev:flavor_cli
```

### 2. Initialization

#### Option A — Interactive wizard

Launch the interactive wizard to bootstrap your project:

```bash
dart run flavor_cli init
```

#### Option B — Non-interactive

Commit a `.flavor_cli.json` to your repo and bootstrap with:

```bash
dart run flavor_cli init --from .flavor_cli.json
```

All required fields are validated before any files are touched. See [Config Reference](#-config-reference) for the full schema.

### 3. Usage Overview

```
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
  migrate  Migrate .flavor_cli.json to the latest format

Examples:
  dart run flavor_cli init
  dart run flavor_cli init --from .flavor_cli.json
  dart run flavor_cli add staging
  dart run flavor_cli replace
  dart run flavor_cli reset
  dart run flavor_cli run dev
  dart run flavor_cli build apk prod
  dart run flavor_cli firebase
  dart run flavor_cli migrate
```

> [!TIP]
> **See it in action**: Check out the [example](example/) project for a pre-configured implementation.

---

## 🛠️ Command Deep Dive

### `1. init`

**Option A — Interactive wizard**

The wizard guides you through 9 steps:

1. **Flavor Selection**: Choose standard sets (`dev, prod` or `dev, stage, prod`) or enter manually.
2. **Schema Definition**: Define your `AppConfig` variables (e.g., `String baseUrl, bool debug`).
3. **Config Location**: Specify where your generated `AppConfig` file should live.
4. **Main Strategy**: Choose between **Separate Mains** (one file per flavor) or **Single Main**.
5. **App Branding**: Set the display name for your application (auto-detected from `Info.plist` / `pubspec.yaml`).
6. **Package ID**: Set your base application identifier (auto-detected from `build.gradle`).
7. **Package ID Strategy**: Choose whether your flavors use **Unique IDs** or a **Shared ID**.
8. **Firebase Project ID**: Set your Firebase project ID if you enable Firebase.
9. **Per-Flavor Values**: Set the runtime value for each `AppConfig` variable across every flavor (e.g., `baseUrl` for `dev`, `stage`, `prod`).

On completion, `.flavor_cli.json` is written to your project root (silently overwrites if it exists).

**Option B — `--from <path>`**

```bash
dart run flavor_cli init --from .flavor_cli.json
```

Reads and strictly validates the config file, then runs the full setup non-interactively. Any missing required field fails immediately with a clear error:

```
❌ flavor_cli: invalid config at ".flavor_cli.json"
   → "production_flavor" must be one of the declared flavors: [dev, stage, prod]
```

> [!NOTE]
> **Package ID Strategy**: `flavor_cli` supports **Unique IDs** (appending `.flavorName` to non-production flavors, e.g. `com.example.app.dev`) or a **Shared ID** (same identifier across all environments). Unique IDs are recommended — they allow multiple flavors to be installed side-by-side on the same device. The production flavor always uses the base ID as-is, regardless of strategy.

---

### `2. add`

Add a new environment to an existing setup without re-initializing.

- Prompts for the flavor name if not provided as an argument.
- Initializes empty per-flavor values for all defined `AppConfig` fields (fill them in `.flavor_cli.json` after).
- Regenerates `.xcconfig` files, updates Android flavors, and adds the flavor to your `AppConfig`.

```bash
dart run flavor_cli add staging
```

---

### `3. delete`

Safely remove a flavor and its associated artifacts.

- Prompts for the flavor to remove if not provided.
- **Safety First**: If deleting would leave fewer than 2 flavors, warns and offers a full **Project Reset** instead.
- **Identity Migration**: If you delete your production flavor, you are prompted to nominate a replacement.

---

### `4. replace`

Rename an existing flavor across the entire project.

- Guides you through selecting the old flavor and entering the new name.
- **Atomic rename**: A pre-flight snapshot of all affected files (xcconfig, schemes, gradle, dart mains, `.flavor_cli.json`) is taken before any changes. If any step fails, all files are restored verbatim from the snapshot — no partial renames.

---

### `5. reset`

Reverts your project to its original, non-flavored state.

- Removes all flavor mains, xcconfig files, generated scripts, and VS Code launch configs.
- Reverts `build.gradle` / `build.gradle.kts` and Xcode project settings.
- Deletes `.flavor_cli.json`.

---

### `6. run`

Standardized wrapper for `flutter run`.

- Prompts for flavor and build mode (`debug` / `release` / `profile`) if not provided.
- Resolves the correct entry point based on your main strategy (`lib/main/main_<flavor>.dart` or `lib/main.dart`).
- Passes `--flavor`, `--target`, `--dart-define=FLAVOR=<flavor>`, and all per-flavor `AppConfig` field values as `--dart-define` entries automatically.
- Fails with a clear error if the resolved entry point file does not exist.

```bash
dart run flavor_cli run dev
```

---

### `7. build`

High-level wrapper for `flutter build`.

- Prompts for build target (`apk` / `ipa` / `appbundle` etc.) and flavor if not provided.
- Same entry point resolution and `--dart-define` injection as `run`.

```bash
dart run flavor_cli build apk prod
```

---

### `8. firebase`

**The "One-Pass" Firebase orchestrator.**

Reads the `firebase` block from `.flavor_cli.json` and configures Firebase non-interactively across all flavors. Requires `flutterfire` CLI to be available on PATH.

Supports 3 strategies:

| Strategy | `use_suffix` | When to use |
|---|---|---|
| `shared_id_single_project` | `false` | All flavors share one Firebase project and one package ID |
| `unique_id_single_project` | `true` | All flavors in one Firebase project but with unique package IDs |
| `unique_id_multi_project` | `true` | Each flavor has its own Firebase project |

- Runs `flutterfire configure` the minimum number of times needed for your strategy.
- Injects `Firebase.initializeApp` and the correct options import into your main files automatically.
- **Idempotent**: Skips injection if `Firebase.initializeApp` is already present in a file.
- **Suffix rules**: Production flavor always uses the base bundle ID. Non-production flavors append `.<flavorName>` when `use_suffix` is `true`.

```bash
dart run flavor_cli firebase
```

---

### `9. migrate`

**Migrate your configuration to the latest version.**

If you are upgrading from an older version of `flavor_cli`, your `.flavor_cli.json` might be missing the required `values` section. The `migrate` command detects these omissions and guides you through filling them in.

- Reads your existing `.flavor_cli.json` (even if it's currently invalid).
- Prompts for missing per-flavor values for any defined `fields`.
- Updates the configuration file while preserving your existing settings.
- **Note**: This only updates the JSON file. Run `init` after migration to apply any changes to your source code.

```bash
dart run flavor_cli migrate
```

---

## 📐 Config Reference

`.flavor_cli.json` is the source of truth for all commands after `init`.

```json
{
  "flavors": ["dev", "stage", "prod"],
  "app_name": "MyApp",
  "fields": {
    "baseUrl": "String",
    "debug": "bool"
  },
  "values": {
    "dev":   { "baseUrl": "https://dev.api.com",  "debug": "true" },
    "stage": { "baseUrl": "https://stage.api.com","debug": "true" },
    "prod":  { "baseUrl": "https://api.com",      "debug": "false" }
  },
  "app_config_path": "lib/core/config/app_config.dart",
  "use_separate_mains": true,
  "use_suffix": true,
  "android": {
    "application_id": "com.example.app"
  },
  "ios": {
    "bundle_id": "com.example.app"
  },
  "production_flavor": "prod",
  "firebase": {
    "strategy": "unique_id_multi_project",
    "projects": {
      "dev":   "my-app-dev",
      "stage": "my-app-stage",
      "prod":  "my-app-prod"
    }
  }
}
```

### Required fields

`flavors`, `app_name`, `production_flavor`, `android.application_id`, `ios.bundle_id`, `app_config_path`, `use_separate_mains`, `use_suffix`

### Optional fields

| Field | Default | Notes |
|---|---|---|
| `fields` | `{}` | AppConfig variable definitions |
| `values` | `{}` | Per-flavor values for each field in `fields` |
| `firebase` | _(absent)_ | Skips firebase setup if not present |

---

## 📚 Guides

- **[Firebase Integration](doc/FIREBASE.md)** — Step-by-step guide to using the Firebase CLI with flavors.
- **[Manual Setup Guide](doc/MANUAL_SETUP.md)** — Beginner-friendly reference for manual flavor configuration on Android and iOS.

---

## 🤝 Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.
