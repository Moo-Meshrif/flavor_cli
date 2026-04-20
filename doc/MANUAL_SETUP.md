# 🛠️ Manual Flavor Setup Guide

This guide provides a step-by-step walkthrough for manually configuring flavors in a Flutter project. While tools like `flavor_cli` automate this process, understanding the manual steps is essential for deep customization and troubleshooting.

---

## 🧠 1. Core Concepts

Flavors (known as "Build Variants" on Android and "Schemes/Configurations" on iOS) allow you to create different versions of your app from a single codebase.

**Common use cases:**
- **Development (dev)**: Connects to a dev API , shows debug logs.
- **Staging (stage)**: Connects to a staging API, similar to production with limited logs.
- **Production (prod)**: Connects to the live API, no debug logs, uses the real App Store/Play Store ID.

---

## ⚖️ 2. AppConfig — Environment Class

A robust way to manage environment-specific variables is using a singleton configuration class.

### `lib/app_config.dart`

```dart
enum Flavor { dev, stage, prod }

class AppConfig {
  static late Flavor flavor;
  static late String url;

  static void init(Flavor f) {
    flavor = f;
    // TODO: Fill in your flavor values here
    switch (f) {
      case Flavor.dev:
        url = 'https://dev.api.com';
        break;
      case Flavor.stage:
        url = 'https://stage.api.com';
        break;
      case Flavor.prod:
        url = 'https://api.com';
        break;
    }
  }

  static bool get isDev => flavor == Flavor.dev;
  static bool get isStage => flavor == Flavor.stage;
  static bool get isProd => flavor == Flavor.prod;
}
```

---

## 🏁 3. Flutter Entry Points

There are two common patterns for implementing flavors in Dart.

### Pattern A: Multiple Entry Points (Recommended)
Create separate entry points for each flavor. This is cleaner for large apps and allows flavor-specific initialization (e.g., different Firebase options) at the top level.

#### `lib/main_dev.dart`
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.init(Flavor.dev);
  runApp(const MyApp());
}
```

#### `lib/main_prod.dart`
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.init(Flavor.prod);
  runApp(const MyApp());
}
```

### Pattern B: Single Entry Point
Use a single `main.dart` and detect the environment using compile-time constants.

#### `lib/main.dart`
```dart
void main() {
  const flavorString = String.fromEnvironment('FLAVOR');
  final flavor = _getFlavor(flavorString);
  AppConfig.init(flavor);
  
  runApp(const MyApp());
}

Flavor _getFlavor(String flavorString) {
  switch (flavorString) {
    case 'dev': return Flavor.dev;
    case 'stage': return Flavor.stage;
    case 'prod':
    default: return Flavor.prod;
  }
}
```

---

## 🤖 4. Android Setup

### `android/app/build.gradle` (Groovy)

```gradle
android {
    ...
    flavorDimensions "default"

    productFlavors {
        dev {
            dimension "default"
            applicationIdSuffix ".dev"
            versionNameSuffix "-dev"
            resValue "string", "app_name", "MyApp Dev"
        }
        stage {
            dimension "default"
            applicationIdSuffix ".stage"
            versionNameSuffix "-stage"
            resValue "string", "app_name", "MyApp Stage"
        }
        prod {
            dimension "default"
            resValue "string", "app_name", "MyApp"
        }
    }
}
```

### `android/app/build.gradle.kts` (Kotlin DSL)

```kotlin
android {
    ...
    flavorDimensions += "default"

    productFlavors {
        create("dev") {
            dimension = "default"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "MyApp Dev")
        }
        create("stage") {
            dimension = "default"
            applicationIdSuffix = ".stage"
            versionNameSuffix = "-stage"
            resValue("string", "app_name", "MyApp Stage")
        }
        create("prod") {
            dimension = "default"
            resValue("string", "app_name", "MyApp")
        }
    }
}
```

---

## 🍎 5. iOS Setup

### Step 1: Create Configurations in Xcode
In Xcode, go to `Navigator → Runner project → Info tab → Configurations`. Duplicate `Debug` and `Release` for each flavor (e.g., `Debug-dev`, `Release-dev`).

### Step 2: Create `.xcconfig` Files
Create files in `ios/Flutter/` for each flavor:

**`dev.xcconfig`**:
```xcconfig
#include "Generated.xcconfig"
FLUTTER_TARGET=lib/main_dev.dart
FLUTTER_FLAVOR=dev
BUNDLE_ID_SUFFIX=.dev
APP_NAME=MyApp Dev
```

### Step 3: Assign XCConfigs
In Xcode `Project → Info → Configurations`, assign the corresponding `.xcconfig` file to each configuration.

### Step 4: Create Schemes
Go to `Product → Scheme → Manage Schemes`. Create schemes like `Runner-dev`, `Runner-prod` and assign the correct Build Configuration to the Run/Archive actions.

### Step 5: Bundle IDs & Display Names
- **Bundle ID**: Set `PRODUCT_BUNDLE_IDENTIFIER` to `com.myapp$(BUNDLE_ID_SUFFIX)`.
- **Display Name**: Set `INFOPLIST_KEY_CFBundleDisplayName` to `$(APP_NAME)`.

---

## 💻 6. IDE Launch Configurations

### VS Code (`.vscode/launch.json`)

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Dev",
      "request": "launch",
      "type": "dart",
      "program": "lib/main_dev.dart",
      "args": ["--flavor", "dev"]
    },
    {
      "name": "Prod",
      "request": "launch",
      "type": "dart",
      "program": "lib/main_prod.dart",
      "args": ["--flavor", "prod"]
    }
  ]
}
```

### Android Studio
Go to `Run → Edit Configurations → + → Flutter`. Set the Name, Dart entrypoint, and add `--flavor <name>` to Additional args.

---

## 🚀 7. Run & Build Commands

### Run (debug)
```bash
flutter run --flavor dev -t lib/main_dev.dart
```

### Build
```bash
# APK
flutter build apk --flavor prod -t lib/main_prod.dart

# iOS IPA
flutter build ipa --flavor prod -t lib/main_prod.dart
```

---

> [!IMPORTANT]
> **Why use `flavor_cli`?**
> Manually syncing bundle IDs, display names, and build configurations across Android and iOS is error-prone. `flavor_cli` handles 100% of the steps above automatically with `dart run flavor_cli init`.
