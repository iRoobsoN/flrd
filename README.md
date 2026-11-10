<div align="center">

# ⚡ FLRD (Flutter Rapid Deployment)

**The sleek desktop launcher to scaffold production-ready Flutter MVPs in seconds.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=for-the-badge)](CONTRIBUTING.md)
[![Donate PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=robson.dv14@gmail.com&currency_code=USD)
[![Donate Pix](https://img.shields.io/badge/Apoie_com-PIX-32BCAD?style=for-the-badge&logo=pix&logoColor=white)](#-support-the-project--apoie-o-projeto)

<p align="center">
  <em>"A Flutter app designed to scaffold Flutter apps."</em>
  <br />
  Conceived by <strong>Robson David</strong> (<strong>FL</strong>utter <strong>R</strong>obson <strong>D</strong>avid / <strong>F</strong>lutter <strong>R</strong>apid <strong>D</strong>eployment)
</p>

[Features](#-key-features) • [Why FLRD?](#-why-flrd-over-alternatives) • [Supported Stacks](#-curated-stack-presets) • [Architecture](#-architecture--anti-obsolescence) • [Getting Started](#-getting-started) • [Contributing](#-contributing) • [Donate](#-support-the-project--apoie-o-projeto)

</div>

---

## 💡 The Problem

Every time you have an idea for a new mobile app, SaaS, or hackathon MVP, running `flutter create` gives you... a single `main.dart` with a counter app.

To turn that into a real application, you spend the next **2 to 3 hours** doing repetitive, non-creative plumbing:
- ⏳ Configuring router and route guards (`go_router`)
- ⏳ Setting up auth state and session listeners (Supabase / Firebase)
- ⏳ Wiring state management boilerplate (Riverpod / Bloc)
- ⏳ Configuring dark/light mode persistence
- ⏳ Creating folder structures, `.env` handlers, and responsive layouts

**FLRD kills the boilerplate tax.** You configure your project visually in a stunning desktop UI, hit **Generate**, and your IDE opens with a fully functional, production-structured app ready for feature code.

---

## ✨ Key Features

- 🖥️ **100% Native Desktop Experience**: Built natively in Flutter for Windows, macOS, and Linux with smooth animations and desktop-grade UX.
- ⚙️ **Frictionless Native Config (Android & iOS)**:
  - Smart `build.gradle` / `.gradle.kts` setup: automated `minSdkVersion`, `targetSdkVersion`, `multidex`, and namespace configuration without editing fragile native files.
  - Painless iOS `Info.plist` & `Podfile` configuration with safe deployment targets.
- 🧭 **Navigation Architect**: Choose your layout philosophy with pre-wired `go_router`:
  - **Modern Tabs** (Bottom Navigation Bar / Floating Island)
  - **Drawer / Dropdown** navigation
  - **Adaptive Shell** (Bottom tabs on mobile, Navigation Rail on Desktop/Tablet)
- 🎨 **Smart Contrast Theme Engine**:
  - Live preview of Light & Dark modes.
  - Automated WCAG contrast calculation — never suffer from invisible text on dark surfaces again.
  - Persistent theme switching (System, Dark, Light) saved to local preferences.
- 🛡️ **Smart Permission Wizard**:
  - Checkbox selection for Camera, Location (GPS), Photo Gallery, Notifications, and Biometrics.
  - Automatically writes correct permissions to `AndroidManifest.xml` and compliant descriptions to iOS `Info.plist` (App Store rejection-proof!).
  - Generates a pre-built `PermissionService` with user-friendly pre-permission dialogs.
- 🔐 **Pre-Wired Authentication**: Choose Supabase, Firebase, or Mock Auth — splash screen, onboarding, login, register, and protected routes are already wired up.
- 🚀 **One-Click IDE Integration**: Instant "Open in VS Code" / "Open in Android Studio" action upon generation.
- 📂 **Clean & Pragmatic Architecture**: Folder structure optimized for speed and clarity without the over-engineering of enterprise templates.

---

## 📊 Why FLRD over alternatives?

| Feature | `flutter create` | Very Good CLI | Mason CLI | **FLRD Desktop** |
| :--- | :---: | :---: | :---: | :---: |
| **Interface** | CLI only | CLI only | CLI only | 🎨 **Visual Desktop App** |
| **Setup Time** | 2-3 hours | 30-45 min | 20-30 min | ⚡ **< 30 seconds** |
| **Pre-Wired Auth Flows** | ❌ None | ❌ Manual | ⚠️ Via bricks | ✅ **Ready to run** |
| **Live Theme Preview** | ❌ None | ❌ None | ❌ None | ✅ **Real-time visualizer** |
| **Curated MVP Stacks** | ❌ None | ⚠️ Enterprise only | ⚠️ Dispersed | ✅ **SaaS, Utility & Clean** |
| **Target Audience** | Beginners | Large Enterprises | Brick Authors | 🚀 **Indie Devs, Creators & MVPs** |

---

## 📦 Curated Stack Presets

FLRD comes packed with opinionated recipes designed for velocity:

### 1. 🚀 SaaS & Indie Hacker
* **State Management:** Riverpod (or Signals)
* **Backend / Auth:** Supabase Auth + Database
* **Routing:** GoRouter with auth redirect guards
* **UI Components:** Modern, minimalist design system (Shadcn-inspired)

### 2. ⚡ Clean-Lite (Scalable Starter)
* **State Management:** BLoC / Cubit
* **Networking:** Dio + Pretty Dio Logger
* **Service Locator:** GetIt
* **Architecture:** Pragmatic Feature-First structure

### 3. 📱 Offline-First Utility
* **Local Database:** Drift (SQLite) or Isar
* **State Management:** Provider / Riverpod
* **UI:** Pure Material 3 with dynamic color support

---

## 🖥️ Application Preview (Concept)

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  ⚡ FLRD - Flutter Rapid Deployment (by Robson David)                     [—] [口] [X]   │
├──────────────────────┬─────────────────────────────────────────────────────────────────┤
│  WIZARD STEPS        │  [1. Project]  [2. Navigation]  [3. Theme]  [4. Permissions]    │
│                      │                                                                 │
│  📁 1. Project Info  │  SMART PERMISSION WIZARD                                        │
│  🧭 2. Navigation    │  Select the device capabilities your app will require:          │
│  🎨 3. Theme & Colors│                                                                 │
│  🛡️ 4. Permissions   │  [✓] Camera               (Adds NSCameraUsageDescription)       │
│  ⚙️ 5. Native Config │  [✓] Location (GPS)       (Configures Android & iOS background) │
│                      │  [✓] Push Notifications   (Pre-wires permission handler & token)│
│  PRESET:             │  [✓] Photos / Gallery     (Ready for image picker)              │
│  [ SaaS / Indie ▾ ]  │  [✓] Biometrics           (Face ID / Fingerprint Auth)          │
│                      │                                                                 │
│  NAVIGATION STYLE:   │  NATIVE PLATFORM CONFIG                                         │
│  (●) Modern Tabs     │  Android Min SDK: [ 24 ▾ ]  | MultiDex: [✓] Enabled             │
│  ( ) Drawer / Menu   │  iOS Target:     [ 15.0 ▾ ] | Swift/Kotlin: [✓] Latest          │
│  ( ) Adaptive Rail   │                                                                 │
│                      │  SMART CONTRAST THEME ENGINE                                    │
│                      │  Seed: [ #6366F1 ]  | Contrast Ratio: 7.2:1 (AAA Compliant ✨)  │
├──────────────────────┴─────────────────────────────────────────────────────────────────┤
│  Target: C:/Projects/my_awesome_app                 [ PREVIEW APP ]  [ GENERATE & OPEN 🚀 ]│
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Getting Started

You can use **FLRD** in two ways: via the sleek **Desktop GUI** or via the **Companion CLI**.

### Option A: Companion CLI (Fast Terminal Scaffolding)

1. Run directly or activate globally:
   ```bash
   # Quick interactive wizard:
   dart run bin/flrd.dart

   # Or scaffold via direct flags:
   dart run bin/flrd.dart create my_saas_app --preset=saas --nav=tabs

   # Enterprise Clean-Lite scaffold:
   dart run bin/flrd.dart create my_corp_app --preset=clean-lite --nav=adaptive --org=com.company
   ```

---

### Option B: Native Desktop GUI

1. Clone the repository:
   ```bash
   git clone https://github.com/iRoobsoN/flrd.git
   cd flrd
   ```

2. Get dependencies:
   ```bash
   flutter pub get
   ```

3. Run the desktop application:
   ```bash
   # Windows
   flutter run -d windows

   # macOS
   flutter run -d macos

   # Linux
   flutter run -d linux
   ```

---

## 🛠️ Architecture & Anti-Obsolescence

FLRD is designed from the ground up to avoid the classic "scaffolding rot" that kills code generation tools:

- 🛡️ **Host SDK Grounded**: Delegates root project creation to your machine's active `flutter create` command.
- 📦 **Dynamic Package Solver**: Resolves live dependencies at generation time via the `pub.dev` API and `flutter pub add`.
- 🧩 **Decoupled Templates**: Templates are synchronized and independent from the desktop binary.
- 🔍 **Semantic Parsers**: Uses AST, XML, and Plist parsers to safely inject permissions and configurations without breaking native files.
- 🔄 **Continuous Canary Testing**: Automated weekly CI testing every template against the latest Flutter releases.

> 📖 Read our full [**ARCHITECTURE.md**](ARCHITECTURE.md) for detailed diagrams, state flow, and system design.

---

## 🗺️ Roadmap

- [x] Initial project identity and architecture design
- [x] Premium Desktop UI Shell (Obsidian Glass, custom titlebar & 6-step wizard)
- [x] Native AST Injectors (Semantic AndroidManifest & iOS Info.plist mutation)
- [x] Production-Ready Code Presets:
  - [x] Preset 1: SaaS / Indie Hacker (Riverpod + Supabase + Auth Router Guards)
  - [x] Preset 2: Clean-Lite (BLoC + Dio + GetIt service locator)
  - [ ] Preset 3: Offline-First (Drift / SQLite + SharedPreferences)
- [x] Companion CLI Mode (`bin/flrd.dart` for terminal lovers)
- [ ] GitHub Actions Canary CI/CD pipeline
- [ ] Custom community template plugins / bricks support

---

## ☕ Support the Project / Apoie o Projeto

If **FLRD** saves you hours of boilerplate setup or helps you ship your MVP faster, consider supporting ongoing development:

<div align="center">

| 🌎 International (PayPal) | 🇧🇷 Brasil (Pix) |
| :---: | :---: |
| [![PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=robson.dv14@gmail.com&currency_code=USD) | [![PIX](https://img.shields.io/badge/Chave_Pix-robson.dv14@gmail.com-32BCAD?style=for-the-badge&logo=pix&logoColor=white)](#) |
| **Email:** `robson.dv14@gmail.com` | **Chave Pix (E-mail):** `robson.dv14@gmail.com` |

</div>

---

## 🤝 Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.

---

<div align="center">

Crafted with 💙 by **[Robson David](https://github.com/iRoobsoN)**  
*Building tools to supercharge Flutter developers worldwide.*

</div>
