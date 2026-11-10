# 📜 Changelog

All notable changes to **FLRD (Flutter Rapid Deployment)** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2026-11-10

### 🚀 Initial Public Release

We are thrilled to launch the first public release of **FLRD (Flutter Rapid Deployment)**! Conceived and built by **Robson David (@iRoobsoN)** to eliminate the 2-hour boilerplate setup tax every time a Flutter developer starts a new MVP.

### ✨ Highlights

#### 🖥️ Native Desktop Experience (Obsidian Glass)
* **Frameless Desktop Shell**: Custom window controls (Minimize, Maximize, Close) and dynamic status pill (`⚡ Engine Ready`).
* **Interactive 6-Step Wizard**:
  1. **Project Details**: Project name, organization ID, and local directory picker via `file_picker`.
  2. **Stack Presets**: Selection between SaaS, Clean-Lite, and Offline-First recipes.
  3. **Navigation Architecture**: Interactive cards with mini layout previews (Modern Tabs, Drawer, Adaptive Rail).
  4. **Smart Contrast Theme Engine**: Live seed color picker with automated WCAG AAA contrast ratio calculation.
  5. **Smart Permission Wizard**: Toggle camera, location, notifications, photo gallery, and biometrics.
  6. **Native Target Configuration**: Android `minSdkVersion`, MultiDex support, and iOS deployment target setup.

#### 📦 Curated Architectural Presets
* **Preset 1: SaaS / Indie Hacker**:
  * State Management: `flutter_riverpod` (v2.x).
  * Backend: Supabase ready + mock authentication.
  * Routing: `go_router` with unbypassable route guards (`refreshListenable` with instant redirect kicks on unauthenticated URL attempts).
* **Preset 2: Clean-Lite (Scalable Starter)**:
  * State Management: `flutter_bloc` (v8.x) with Dart 3 pattern matching and sealed classes.
  * Networking: `dio` with pre-wired timeout configurations and error interceptors.
  * Dependency Injection: `get_it` service locator.
* **Preset 3: Offline-First Utility**:
  * Local Storage: SQLite via `sqflite` with robust `DatabaseHelper` singleton and schema creation.
  * State Management: `provider` with in-memory caching and real-time offline search.
  * User Preferences: `shared_preferences` for light/dark theme persistence.

#### 🛡️ Anti-Obsolescence Native Injectors
* **Semantic XML & Plist Mutation**: Modifies `AndroidManifest.xml` and `Info.plist` using structured AST/XML parsers without regex corruption.
* **PermissionService Generator**: Automatically generates friendly in-app rationale dialogs before triggering native OS permission prompts.

#### ⚡ Companion CLI (`bin/flrd.dart`)
* Interactive terminal question wizard with neon ANSI styling.
* Direct flag mode (`flrd create my_app --preset=saas --nav=tabs`).
* Global activation support via `dart pub global activate flrd`.

#### 🤖 CI/CD & Quality
* Automated GitHub Actions pipeline (`.github/workflows/ci.yml`) validating formatting, static analysis, and unit test suite.
* Official GitHub Sponsor support (`.github/FUNDING.yml`) with PayPal and Pix integration.
