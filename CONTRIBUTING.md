# Contributing to FLRD

First off, thank you for considering contributing to **FLRD (Flutter Rapid Deployment)**! Tools like this thrive because of the collective wisdom of the Flutter community.

---

## 🌟 Code of Conduct

We aim to foster an open, welcoming, and productive environment. Please treat all contributors with kindness and respect.

---

## 🚀 How Can You Contribute?

### 1. Adding or Improving Presets / Templates
Have a favorite architectural stack? (e.g., Signals + GetIt, Supabase + Riverpod, Firebase + Bloc).
* All presets live in `assets/templates/presets/<preset_name>/`.
* Each preset must follow the **Anti-Obsolescence Guidelines** (see [ARCHITECTURE.md](ARCHITECTURE.md)):
  * Use idiomatic Dart 3+ syntax (records, pattern matching, sealed classes).
  * Do not hardcode fixed dependency versions; declare package identifiers in the preset manifest.
  * Ensure `flutter analyze` passes with zero warnings.

### 2. Improving Semantic Injectors
Help us improve native file modifications for Android and iOS:
* Android `AndroidManifest.xml` updates (`lib/features/generator/injectors/android_manifest_injector.dart`).
* iOS `Info.plist` updates (`lib/features/generator/injectors/ios_plist_injector.dart`).
* Gradle / `.gradle.kts` configuration helpers.

### 3. Enhancing the Desktop UI
* Creating smooth animations with `flutter_animate`.
* Improving the **Smart Contrast Theme Engine** previewer.
* Adding keyboard shortcuts and accessibility (a11y) improvements.

---

## 🛠️ Local Development Setup

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/iRoobsoN/flrd.git
   cd flrd
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the desktop app:
   ```bash
   # On Windows
   flutter run -d windows

   # On macOS
   flutter run -d macos

   # On Linux
   flutter run -d linux
   ```

4. Run tests and static analysis:
   ```bash
   dart analyze
   flutter test
   ```

---

## 📋 Pull Request Guidelines

1. Create a branch for your feature: `git checkout -b feature/my-new-feature`
2. Follow effective Dart style conventions.
3. If you add a new generator capability or template, add a corresponding test in `test/`.
4. Open a PR with a clear description and screenshot/GIF if UI changes are included.

Thank you for helping supercharge Flutter developers worldwide! 💙
