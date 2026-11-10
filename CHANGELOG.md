# 📜 Changelog

All notable changes to **FLRD (Flutter Rapid Deployment)** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.1] - 2026-11-10

### 🛡️ Marketplace Guardian Suite & Anti-Plagiarism Engine

This release introduces the **Marketplace Guardian Suite**, protecting the developer ecosystem from market prostitution, low-effort clones, and security leaks.

#### ✨ Highlights
* **Category Price Floors (`isPriceFloorValid`)**:
  * Enforces mandatory price minimums across template categories: Micro-Modules (\$15 USD), Starter Kits (\$29 USD), and Full Apps (\$49 USD) to eradicate race-to-the-bottom pricing.
* **AST Structural Fingerprinting & Anti-Plagiarism (`TemplateFingerprint`)**:
  * Deconstructs projects into class hierarchies, custom widgets, routes, and file topologies.
  * Calculates Jaccard similarity index; automatically flags and blocks candidate submissions that exceed 70% structural similarity with existing catalog templates.
* **Security & Secret Leak Audit (`auditSecurity`)**:
  * Scans project files prior to packaging, blocking `.env` files, `.pem` keys, and hardcoded Google API or Stripe tokens.
* **Creator Submission Suite (`PublishTemplateDialog`)**:
  * Interactive publishing dialog accessible from the Marketplace and App Studio.
  * Real-time 75% creator / 25% platform revenue split calculator.
  * 1-click automated security & anti-plagiarism verification checklist.
  * Generates signed `.flrd/manifest.json` with cryptographic provenance.
* **Test Suite Expansion**: Added 7 automated tests for the Guardian Suite; all 66 tests passing.

---

## [0.2.0] - 2026-11-10

### 🚀 Major Release: The Complete App Studio & Ecosystem Suite

Version 0.2.0 transforms **FLRD** from a project scaffolding wizard into a complete, visual **Flutter App Studio**, featuring an interactive route canvas, embedded code editor, real Google Gemini 1.5 Flash AI generation, existing project reverse engineering, a curated templates marketplace with anti-drift consistency manifests, and a native Windows cloud release pipeline.

### ✨ What's New in v0.2.0

#### 🌐 FLRD Studio Hub & Multi-language Support (i18n)
* **Interactive Home Hub (`HubScreen`)**:
  * Hero banner with dynamic welcome and fast status pill.
  * Anti-obsolescence pillar highlights explaining the native AST and host SDK philosophy.
  * Quick action launchpad: **Novo Projeto**, **Importar Projeto Existente**, and **Explorar Marketplace**.
  * Integrated CLI terminal quick-copy command banner.
  * Recognized projects section and community footer with creator links.
* **Instant Reactive i18n (`LanguageSelectorWidget`)**:
  * Real-time language switching without restart: Português (🇧🇷), English (🇺🇸), and Español (🇪🇸).
  * Backed by `LanguageNotifier` and central `AppStrings` dictionary.

#### 🗺️ Interactive Route Flowchart Canvas (`AppStudioScreen`)
* **Visual Route Architecture Map**:
  * Interactive canvas with infinite panning, smooth zoom in/out, and reset/center controls powered by `InteractiveViewer`.
  * Custom Bézier connector painter (`RouteConnectorPainter`) with directional arrows and obsidian blueprint dot grid.
  * Draggable `RouteNodeCard` components displaying route paths, `AuthGuard` status pills, `AI Gen` badges, and required native permissions.
* **App Studio Multi-Tab Workspace**:
  * **Fluxo de Rotas**: Visual route canvas and node inspector.
  * **Permissões Nativas**: Real-time permission audit with direct `AndroidManifest.xml` & `Info.plist` synchronization.
  * **Arquitetura & Pacotes**: Active dependencies and structural inspection.

#### 💻 Embedded Code Viewer & Editor (`EmbeddedCodeViewer`)
* **Glassmorphic Inspector Panel**:
  * 440px wide slide-in panel with segmented switcher: `[⚙️ Detalhes da Rota]` and `[💻 Ver Código Dart]`.
  * Monospace line numbers gutter and real-time Dart token syntax highlighting matching Obsidian Glass dark theme.
  * Automatic disk file loading with fallback template synthesis when files are yet to be generated.
  * **Salvar no Disco**: Direct atomic disk write (`File.writeAsString(..., flush: true)`).
  * **Copiar Código**: One-click clipboard copy (`Clipboard.setData`).
  * **Modal Fullscreen Dialog**: 750px wide high-resolution code viewer modal (`_showFullscreenCodeModal`) with dark elevated chrome.

#### 🧠 Real AI Screen Studio (Google Gemini 1.5 Flash)
* **Gemini REST Engine (`GeminiAiService`)**:
  * Direct Google Gemini 1.5 Flash REST integration (`gemini-1.5-flash:generateContent`).
  * BYOK (Bring Your Own Key) architecture with local secure key storage.
  * Strict architectural prompt conditioning enforcing Material 3, clean code guidelines, and Obsidian Glass tokens.
  * Automated markdown extraction, code cleaning, and physical `.dart` file creation on disk with parent folder scaffolding.
  * Resilient offline fallback generator for guaranteed continuity without network access.
  * Dynamic insertion of generated screens into the active route flowchart.

#### 🛍️ Community Templates Marketplace & Manifest Engine
* **Curated Template Showcase (`MarketplaceView`)**:
  * Category filters (SaaS, FinTech, Delivery, Offline, Health) with real-time text search.
  * 5 launch kits: **NovaBank** (Digital banking), **SaaSHero** (Subscription SaaS), **FoodDelivery Pro** (Logistics), **OfflineVault** (Encrypted local storage), and **FitPulse** (Health tracking).
* **Anti-Drift Consistency Manifest (`.flrd/manifest.json`)**:
  * `TemplateManifestContext` locks design tokens, state management rules, and AI prompt conditioning.
  * Protects generated and customized projects from visual and architectural fragmentation over time.
* **Creator Monetization**:
  * Integrated 75% creator / 25% FLRD platform revenue split model for community creators.

#### 📂 Reverse Engineering & Project Ingestion
* **Deep Project Scanner (`ProjectAnalyzerService`)**:
  * Analyzes any pre-existing Flutter project on disk containing `pubspec.yaml`.
  * Detects active architecture (Riverpod, BLoC, SQLite, Provider).
  * Scans `AndroidManifest.xml` and `Info.plist` to extract configured permissions.
  * Recursively scans `lib/` for `*_screen.dart` and `*_page.dart`, constructing visual `RouteNode` graphs.
  * Synthesizes `.flrd/manifest.json` ensuring full compatibility with FLRD Studio features.
* **Import Modal Dialog (`ImportProjectDialog`)**:
  * 1-click import with directory picker and quick path shortcut chips.

#### 💰 Monetization & Financial Suite
* **Centralized Configuration (`MonetizationConfig`)**:
  * Official Lemon Squeezy checkout integration.
  * Community support gateways: Pix (`robson.dv14@gmail.com`) and PayPal donation links.
  * FLRD Pro subscription options: $19/mo or $49 lifetime license.
* **Global Settings Modal (`SettingsAndBillingDialog`)**:
  * 3 dedicated tabs: **IA / Gemini BYOK**, **Plano & Faturamento**, and **Apoie a Comunidade**.
  * Quick-access settings icon in `CustomTitleBar`.

#### ⚙️ Automated Windows Native Build & Cloud Release
* **GitHub Actions Release Pipeline (`.github/workflows/release.yml`)**:
  * Automated Windows x64 compilation on `windows-latest` runners upon pushing `v*` tags.
  * Runs lint analysis, test suite, and generates `flrd-windows-x64.zip`.
  * Publishes binary assets directly to GitHub Releases with auto-generated release notes.

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
