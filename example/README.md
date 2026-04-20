# 🍹 Flavor CLI — Example

This example demonstrates how to use `flavor_cli` to generate and manage Flutter flavors in a real project.

It serves as a **reference implementation** showing how to structure and run a multi-environment Flutter app using automated flavor setup.

---

## 📂 Access the Full Example Project

👉 https://github.com/Moo-Meshrif/flavor_cli/tree/main/example

This is a fully working Flutter app configured with multiple flavors (`dev`, `stage`, `prod`).

---

## 🚀 Run the Example Locally

Clone the repository and navigate to the example project:

```bash
git clone https://github.com/Moo-Meshrif/flavor_cli.git
cd flavor_cli/example
flutter pub get
```

---

## ⚙️ Initialize & Generate Flavors

Run the CLI commands:

```bash
dart run flavor_cli init
```

### What this does

- ✅ Configures Android `productFlavors`
- ✅ Generates iOS schemes automatically
- ✅ Applies consistent naming conventions
- ✅ Prepares the project for multi-environment builds

---

## ▶️ Run Each Flavor

Each environment has its own entry point. Use the `flavor_cli` run wrapper for a simplified experience:

### 🔵 Development

```bash
dart run flavor_cli run dev
```

### 🟡 Staging

```bash
dart run flavor_cli run stage
```

### 🔴 Production

```bash
dart run flavor_cli run prod
```

---

## 📦 Project Structure

```bash
example/
├── lib/
│   ├── main/
│   │   ├── main_dev.dart
│   │   ├── main_stage.dart
│   │   └── main_prod.dart
│   └── app_config.dart
├── android/
├── ios/
└── pubspec.yaml
```

---

## 🧠 How It Works

`flavor_cli` automates the complex and repetitive parts of flavor setup:

- Eliminates manual Gradle configuration
- Avoids manual iOS scheme setup
- Uses a clean **Zero-XCConfig approach**
- Standardizes environment configuration

---

## ⚠️ Important

pub.dev does **not run example apps**.

This page is for documentation only.  
To test the example, clone the repository and run it locally using the steps above.
