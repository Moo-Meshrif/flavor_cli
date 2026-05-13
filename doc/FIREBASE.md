# 🔥 Firebase CLI with flavors


There are two ways to integrate Firebase with `flavor_cli`:

1.  **⚡ Automated (Recommended)**: Use the built-in `firebase` command to handle everything in seconds.
2.  **🛠️ Manual**: Follow the step-by-step guide below for manual control over each configuration.

---

## ⚡ Option 1: Automated Setup (Zero-Friction)

`flavor_cli` now automates the **entire** Firebase setup in a single command. 

```bash
dart run flavor_cli firebase
```

The tool will:
1. **Manage Dependencies**: Automatically adds `firebase_core` to your `pubspec.yaml`.
2. **Authentication**: Resets and ensures you are logged in via `firebase login`.
3. **Configure Flavors**: Runs `flutterfire configure` for every environment.
4. **Auto-Code Injection**: Automatically injects initialization code and imports into your `main` files!

---

## 🛠️ Option 2: Manual Step-by-Step Guide

## 🏎️ 1. Prerequisites

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
```

## 🧠 2. Architecture Overview

| Approach | Recommended | Notes |
|--------|------------|------|
| Same Bundle ID | ❌ No | Causes conflicts |
| Unique Bundle IDs | ✅ Yes | Production-safe |


## ✅ 3. Best Practice: Unique IDs

| Flavor | Android ID | iOS Bundle ID |
|-------|-----------|--------------|
| dev | com.example.dev | com.example.dev |
| prod | com.example | com.example |


## ⚙️ 4. Configure Firebase for each flavor

### DEV
```bash
flutterfire configure \
  --project=<YOUR_PROJECT_ID> \
  --out=lib/firebase_options_dev.dart \
  --ios-bundle-id=<YOUR_PACKAGE_NAME>.dev \
  --android-app-id=<YOUR_PACKAGE_NAME>.dev
```

### PROD
```bash
flutterfire configure \
  --project=<YOUR_PROJECT_ID> \
  --out=lib/firebase_options_prod.dart \
  --ios-bundle-id=<YOUR_PACKAGE_NAME> \
  --android-app-id=<YOUR_PACKAGE_NAME>
```

## 📁 5. Main Strategy & Initialization

Depending on your `flavor_cli` configuration, choose the pattern below:

### **Pattern A: Separated Mains (lib/main/main_dev.dart)**
*Recommended for clean architecture.*

```dart
// lib/main/main_dev.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../firebase_options_dev.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.dev');
  AppConfig.init(Flavor.dev);
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}
```

### **Pattern B: Single Main (lib/main.dart)**
*Use this if you use the same entry point for all flavors.*

```dart
// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:<your_project_name>/core/config/app_config.dart';
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Custom logic to get current flavor
  const flavorString = String.fromEnvironment('FLAVOR');
  final flavor = _getFlavor(flavorString);
  
  // Load environment variables
  await dotenv.load(fileName: '.env.$flavorString');
  AppConfig.init(flavor);

  // Initialize Firebase based on flavor
  await Firebase.initializeApp(
    options: flavor == Flavor.dev 
      ? dev.DefaultFirebaseOptions.currentPlatform 
      : prod.DefaultFirebaseOptions.currentPlatform,
  );

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
