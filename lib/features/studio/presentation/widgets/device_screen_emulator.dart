import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../projects/models/registered_project.dart';
import '../../../wizard/models/project_config.dart';
import '../../models/route_node.dart';

/// Mode for preview in the device screen emulator.
enum EmulatorPreviewMode {
  codeLiveSync,
  archetypeMock,
}

/// Supported mobile device emulator frame configurations.
enum EmulatorDevice {
  iphone15Pro(
    name: 'iPhone 15 Pro',
    platform: TargetPlatform.iOS,
    width: 393,
    height: 852,
    cornerRadius: 50,
    bezelWidth: 10,
    hasDynamicIsland: true,
    hasPunchHole: false,
    hasHomeIndicator: true,
  ),
  pixel8(
    name: 'Pixel 8',
    platform: TargetPlatform.android,
    width: 412,
    height: 892,
    cornerRadius: 42,
    bezelWidth: 9,
    hasDynamicIsland: false,
    hasPunchHole: true,
    hasHomeIndicator: true,
  );

  final String name;
  final TargetPlatform platform;
  final double width;
  final double height;
  final double cornerRadius;
  final double bezelWidth;
  final bool hasDynamicIsland;
  final bool hasPunchHole;
  final bool hasHomeIndicator;

  const EmulatorDevice({
    required this.name,
    required this.platform,
    required this.width,
    required this.height,
    required this.cornerRadius,
    required this.bezelWidth,
    required this.hasDynamicIsland,
    required this.hasPunchHole,
    required this.hasHomeIndicator,
  });
}

/// Archetype category for simulating screens.
enum RouteArchetype {
  splash,
  auth,
  dashboard,
  explore,
  profile,
  custom,
}

/// High-fidelity smartphone shell emulator with interactive screen simulation.
class DeviceScreenEmulator extends StatefulWidget {
  final RouteNode? node;
  final RegisteredProject? project;
  final String? sourceCode;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;

  const DeviceScreenEmulator({
    super.key,
    this.node,
    this.project,
    this.sourceCode,
    this.isExpanded = false,
    this.onToggleExpand,
  });

  /// Opens the emulator inside a modal dialog.
  static Future<void> showModal(
    BuildContext context, {
    required RouteNode node,
    RegisteredProject? project,
    String? sourceCode,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: AppColors.backgroundSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: SizedBox(
            width: 820,
            height: 900,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: DeviceScreenEmulator(
                node: node,
                project: project,
                sourceCode: sourceCode,
                isExpanded: true,
                onToggleExpand: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  State<DeviceScreenEmulator> createState() => _DeviceScreenEmulatorState();
}

class _DeviceScreenEmulatorState extends State<DeviceScreenEmulator>
    with SingleTickerProviderStateMixin {
  EmulatorDevice _selectedDevice = EmulatorDevice.iphone15Pro;
  bool _isDarkMode = true;
  double? _customScale; // null means auto-fit
  bool _isDynamicIslandExpanded = false;
  Key _simulationKey = UniqueKey();
  EmulatorPreviewMode _previewMode = EmulatorPreviewMode.codeLiveSync;
  ParsedScreenData? _parsedData;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.value = 1.0;
    }
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant DeviceScreenEmulator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node?.id != widget.node?.id ||
        oldWidget.sourceCode != widget.sourceCode) {
      _simulationKey = UniqueKey();
      _isDynamicIslandExpanded = false;
      _parsedData = null;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _resetSimulation() {
    setState(() {
      _simulationKey = UniqueKey();
      _isDynamicIslandExpanded = false;
      _parsedData = null;
    });
  }

  RouteArchetype _detectArchetype(RouteNode? node) {
    if (node == null) return RouteArchetype.custom;
    final title = node.title.toLowerCase();
    final path = node.path.toLowerCase();
    final id = node.id.toLowerCase();

    if (path == '/' ||
        title.contains('splash') ||
        id.contains('splash') ||
        title.contains('authguard') ||
        id == 'root') {
      return RouteArchetype.splash;
    }
    if (title.contains('login') ||
        title.contains('register') ||
        title.contains('auth') ||
        title.contains('sign') ||
        path.contains('auth') ||
        id == 'login' ||
        id == 'register') {
      return RouteArchetype.auth;
    }
    if (title.contains('profile') ||
        title.contains('user') ||
        title.contains('account') ||
        path.contains('profile') ||
        id == 'profile') {
      return RouteArchetype.profile;
    }
    if (title.contains('explore') ||
        title.contains('feed') ||
        title.contains('catalog') ||
        title.contains('discover') ||
        path.contains('explore') ||
        id == 'explore') {
      return RouteArchetype.explore;
    }
    if (title.contains('dashboard') ||
        title.contains('home') ||
        title.contains('metrics') ||
        title.contains('stats') ||
        path.contains('dashboard') ||
        id == 'dashboard') {
      return RouteArchetype.dashboard;
    }
    return RouteArchetype.custom;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Emulator Control Toolbar
          _buildToolbar(),

          // Main Viewport Area with Phone Shell
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final deviceW = _selectedDevice.width + (_selectedDevice.bezelWidth * 2);
                final deviceH = _selectedDevice.height + (_selectedDevice.bezelWidth * 2);

                final availableW = constraints.maxWidth - 24;
                final availableH = constraints.maxHeight - 24;

                // Determine scale factor
                double scale;
                if (_customScale != null) {
                  scale = _customScale!;
                } else {
                  final scaleX = availableW / deviceW;
                  final scaleY = availableH / deviceH;
                  scale = math.min(scaleX, scaleY).clamp(0.2, 1.0);
                }

                return Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: deviceW,
                            height: deviceH,
                            child: _buildSmartphoneShell(),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TOOLBAR CONTROLS
  // ===========================================================================

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // Device Switcher & Route Badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _selectedDevice == EmulatorDevice.iphone15Pro
                          ? Icons.phone_iphone_rounded
                          : Icons.phone_android_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 5),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<EmulatorDevice>(
                        value: _selectedDevice,
                        isDense: true,
                        dropdownColor: AppColors.surfaceCard,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        icon: const Icon(Icons.arrow_drop_down_rounded,
                            size: 16, color: AppColors.textSecondary),
                        items: EmulatorDevice.values.map((device) {
                          return DropdownMenuItem<EmulatorDevice>(
                            value: device,
                            child: Text(device.name),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedDevice = val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (widget.node != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHover,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.node!.icon, size: 12, color: AppColors.secondary),
                      const SizedBox(width: 4),
                      Text(
                        widget.node!.path,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          // Code Live Sync vs Archetype Mock Toggle Pill
          _buildModeTogglePill(),

          // Scale & Theme & Action Controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Theme Toggle (Dark / Light)
              IconButton(
                tooltip: _isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                icon: Icon(
                  _isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  size: 16,
                  color: _isDarkMode ? AppColors.secondary : Colors.amber,
                ),
                onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
              ),

              // Scale Presets
              _buildScaleButton('Fit', null),
              _buildScaleButton('75%', 0.75),
              _buildScaleButton('100%', 1.0),

              // Reset Interactive Simulation
              IconButton(
                tooltip: 'Reset Screen Simulation',
                icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.textMuted),
                onPressed: _resetSimulation,
              ),

              // Fullscreen Modal Toggle (if provided)
              if (widget.onToggleExpand != null) ...[
                IconButton(
                  tooltip: widget.isExpanded ? 'Exit Fullscreen' : 'Expand Emulator',
                  icon: Icon(
                    widget.isExpanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    size: 17,
                    color: AppColors.textPrimary,
                  ),
                  onPressed: widget.onToggleExpand,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeTogglePill() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      padding: const EdgeInsets.all(2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPillOption(
              key: const Key('toggle_code_live_sync'),
              mode: EmulatorPreviewMode.codeLiveSync,
              label: '⚡ Code Live Sync',
            ),
            _buildPillOption(
              key: const Key('toggle_archetype_mock'),
              mode: EmulatorPreviewMode.archetypeMock,
              label: '🎨 Archetype Mock',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillOption({
    required Key key,
    required EmulatorPreviewMode mode,
    required String label,
  }) {
    final isSelected = _previewMode == mode;
    return InkWell(
      key: key,
      onTap: () {
        setState(() {
          _previewMode = mode;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildScaleButton(String label, double? targetScale) {
    final isSelected = _customScale == targetScale;
    return InkWell(
      onTap: () => setState(() => _customScale = targetScale),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SMARTPHONE HARDWARE SHELL
  // ===========================================================================

  Widget _buildSmartphoneShell() {
    final dev = _selectedDevice;
    final isIos = dev.platform == TargetPlatform.iOS;

    // Shell Bezel Styling
    final outerDecoration = BoxDecoration(
      color: isIos ? const Color(0xFF1E2128) : const Color(0xFF1C1E22),
      borderRadius: BorderRadius.circular(dev.cornerRadius),
      border: Border.all(
        color: isIos ? const Color(0xFF3B404E) : const Color(0xFF333742),
        width: 2.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.55),
          blurRadius: 36,
          spreadRadius: 4,
          offset: const Offset(0, 16),
        ),
        BoxShadow(
          color: AppColors.primaryGlow.withOpacity(0.12),
          blurRadius: 48,
          spreadRadius: -8,
        ),
      ],
    );

    // Inner Phone Screen
    final screenBgColor = _isDarkMode ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
    final statusColor = _isDarkMode ? Colors.white : const Color(0xFF0F172A);

    return Container(
      decoration: outerDecoration,
      padding: EdgeInsets.all(dev.bezelWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(dev.cornerRadius - dev.bezelWidth),
        child: Container(
          color: screenBgColor,
          child: Stack(
            children: [
              // Screen Body Content
              Positioned.fill(
                child: KeyedSubtree(
                  key: _simulationKey,
                  child: _buildScreenContent(),
                ),
              ),

              // Status Bar Layer (Always on top)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildStatusBar(dev, statusColor),
              ),

              // Bottom Home Indicator (iOS Capsule / Android Gesture Pill)
              if (dev.hasHomeIndicator) ...[
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: isIos ? 134 : 72,
                      height: isIos ? 5 : 4,
                      decoration: BoxDecoration(
                        color: _isDarkMode
                            ? Colors.white.withOpacity(0.5)
                            : Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // REALISTIC STATUS BAR & NOTCH / DYNAMIC ISLAND
  // ===========================================================================

  Widget _buildStatusBar(EmulatorDevice dev, Color statusColor) {
    if (dev.hasDynamicIsland) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left: Clock
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '9:41',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),

            // Center: Dynamic Island
            _buildDynamicIsland(),

            // Right: Connectivity & Battery Icons
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.signal_cellular_alt_rounded, size: 14, color: statusColor),
                    const SizedBox(width: 3),
                    Text(
                      '5G',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.wifi_rounded, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    _buildBatteryIndicator(statusColor),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Pixel 8 with Center Punch Hole
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left: Time & notification dot
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '9:41',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Center: Punch hole camera
            _buildPunchHoleCamera(),

            // Right: Pixel status icons
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_rounded, size: 13, color: statusColor),
                    const SizedBox(width: 3),
                    Icon(Icons.signal_cellular_4_bar_rounded, size: 13, color: statusColor),
                    const SizedBox(width: 3),
                    Text(
                      '94%',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.battery_full_rounded, size: 13, color: statusColor),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDynamicIsland() {
    final width = _isDynamicIslandExpanded ? 160.0 : 112.0;
    final height = _isDynamicIslandExpanded ? 36.0 : 30.0;

    return GestureDetector(
      key: const Key('dynamic_island'),
      onTap: () => setState(() => _isDynamicIslandExpanded = !_isDynamicIslandExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRect(
          child: OverflowBox(
            maxWidth: 180,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left Island sensor / icon
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F1A30),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFF28549C),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    if (_isDynamicIslandExpanded) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'FLRD Dev',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),

                // Right Island micro-activity indicator
                if (_isDynamicIslandExpanded) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.graphic_eq_rounded, size: 14, color: AppColors.secondary),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // Subtle camera lens
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPunchHoleCamera() {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.7),
      ),
      child: Center(
        child: Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: Color(0xFF1D3557),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildBatteryIndicator(Color statusColor) {
    return Container(
      width: 22,
      height: 11,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: statusColor, width: 1.1),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: statusColor,
          borderRadius: BorderRadius.circular(1.5),
        ),
      ),
    );
  }

  // ===========================================================================
  // SCREEN CONTENT ROUTER (CODE LIVE SYNC vs ARCHETYPE MOCK)
  // ===========================================================================

  Widget _buildScreenContent() {
    final hasSource =
        widget.sourceCode != null && widget.sourceCode!.trim().isNotEmpty;
    if (_previewMode == EmulatorPreviewMode.codeLiveSync && hasSource) {
      return _buildDynamicCodeRenderedScreen();
    }
    return _buildInteractiveScreenContent();
  }

  // ===========================================================================
  // DYNAMIC CODE-DRIVEN RENDERING ENGINE
  // ===========================================================================

  Widget _buildDynamicCodeRenderedScreen() {
    final parsed = _parsedData ??= DartCodeScreenParser.parse(
      widget.sourceCode!,
      isDarkMode: _isDarkMode,
      nodeTitle: widget.node?.title,
    );

    final screenBg = parsed.scaffoldBackgroundColor ??
        (_isDarkMode ? const Color(0xFF090D16) : const Color(0xFFF8FAFC));
    final textColor = _isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final statusBarHeight = _selectedDevice.hasDynamicIsland ? 48.0 : 40.0;

    return Container(
      color: screenBg,
      child: Column(
        children: [
          // Dynamic AppBar extracted from code
          if (parsed.appBar != null) ...[
            Container(
              color: parsed.appBar!.backgroundColor ??
                  (_isDarkMode ? const Color(0xFF111726) : Colors.white),
              padding: EdgeInsets.only(
                top: statusBarHeight,
                left: 16,
                right: 16,
                bottom: 8,
              ),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    if (parsed.appBar!.leadingIcon != null) ...[
                      Icon(
                        parsed.appBar!.leadingIcon,
                        size: 20,
                        color: parsed.appBar!.titleColor ?? textColor,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        parsed.appBar!.title,
                        style: TextStyle(
                          color: parsed.appBar!.titleColor ?? textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...parsed.appBar!.actionIcons.map(
                      (icon) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          icon,
                          size: 18,
                          color: parsed.appBar!.titleColor ?? textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Body Content with dynamic cards, text, buttons, inputs
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                top: parsed.appBar != null ? 16 : (statusBarHeight + 16),
                left: 16,
                right: 16,
                bottom: 32,
              ),
              child: _buildParsedBodyContent(parsed, textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParsedBodyContent(ParsedScreenData parsed, Color textColor) {
    final List<Widget> items = [];

    // Prominent main card / container (e.g. from template or code body)
    if (parsed.mainCard != null) {
      final cardWidget = _buildParsedCard(parsed.mainCard!, textColor);
      if (parsed.isCentered) {
        items.add(Center(child: cardWidget));
      } else {
        items.add(cardWidget);
      }
    }

    // Remaining body widgets (buttons, inputs, texts, icons, etc.)
    for (final node in parsed.bodyWidgets) {
      if (items.isNotEmpty) {
        items.add(const SizedBox(height: 12));
      }
      items.add(_buildParsedWidget(node, textColor));
    }

    if (items.isEmpty && parsed.mainCard == null) {
      return Center(
        child: Text(
          widget.node?.title ?? 'Screen',
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (parsed.isCentered && parsed.mainCard == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: items,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }

  Widget _buildParsedCard(ParsedContainerCard card, Color textColor) {
    return Container(
      padding: card.padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: card.backgroundColor ??
            (_isDarkMode ? const Color(0xFF141B2D) : Colors.white),
        borderRadius: BorderRadius.circular(card.borderRadius ?? 16),
        border: Border.all(
          color: card.borderColor ??
              (_isDarkMode ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < card.children.length; i++) ...[
            if (i > 0 && !(card.children[i] is ParsedSizedBoxNode || card.children[i - 1] is ParsedSizedBoxNode))
              const SizedBox(height: 10),
            _buildParsedWidget(card.children[i], textColor, isInsideCard: true),
          ],
        ],
      ),
    );
  }

  Widget _buildParsedWidget(
    ParsedWidgetNode node,
    Color textColor, {
    bool isInsideCard = false,
  }) {
    if (node is ParsedIconNode) {
      return Icon(
        node.icon,
        size: node.size ?? (isInsideCard ? 48 : 28),
        color: node.color ?? AppColors.primary,
      );
    } else if (node is ParsedTextNode) {
      return Text(
        node.text,
        textAlign: node.textAlign ??
            (isInsideCard ? TextAlign.center : TextAlign.start),
        style: TextStyle(
          color: node.color ?? textColor,
          fontSize: node.fontSize ?? 14,
          fontWeight: node.fontWeight ?? FontWeight.normal,
        ),
      );
    } else if (node is ParsedButtonNode) {
      switch (node.type) {
        case ParsedButtonType.elevated:
          return ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: node.backgroundColor ?? AppColors.primary,
              foregroundColor: node.foregroundColor ?? Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Triggered ${node.label}')),
              );
            },
            icon: node.icon != null ? Icon(node.icon, size: 16) : const SizedBox.shrink(),
            label: Text(
              node.label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          );
        case ParsedButtonType.outlined:
          return OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: node.foregroundColor ?? AppColors.secondary,
              side: BorderSide(color: node.backgroundColor ?? AppColors.secondary),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Triggered ${node.label}')),
              );
            },
            icon: node.icon != null ? Icon(node.icon, size: 16) : const SizedBox.shrink(),
            label: Text(
              node.label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          );
        case ParsedButtonType.text:
          return TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: node.foregroundColor ?? AppColors.secondary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Triggered ${node.label}')),
              );
            },
            icon: node.icon != null ? Icon(node.icon, size: 16) : const SizedBox.shrink(),
            label: Text(node.label, style: const TextStyle(fontSize: 12)),
          );
      }
    } else if (node is ParsedInputNode) {
      return _InteractiveInputWidget(
        input: node,
        isDarkMode: _isDarkMode,
      );
    } else if (node is ParsedContainerCard) {
      return _buildParsedCard(node, textColor);
    } else if (node is ParsedSizedBoxNode) {
      return SizedBox(height: node.height);
    }
    return const SizedBox.shrink();
  }

  // ===========================================================================
  // INTERACTIVE SCREEN SIMULATIONS TAILORED TO ROUTENODE ARCHETYPES
  // ===========================================================================

  Widget _buildInteractiveScreenContent() {
    final archetype = _detectArchetype(widget.node);

    switch (archetype) {
      case RouteArchetype.splash:
        return _buildSplashScreenSimulation();
      case RouteArchetype.auth:
        return _buildAuthScreenSimulation();
      case RouteArchetype.dashboard:
        return _buildDashboardScreenSimulation();
      case RouteArchetype.explore:
        return _buildExploreScreenSimulation();
      case RouteArchetype.profile:
        return _buildProfileScreenSimulation();
      case RouteArchetype.custom:
        return _buildCustomScreenSimulation();
    }
  }

  // ---------------------------------------------------------------------------
  // 1. ProfileScreen Simulation (Avatar, Settings, Pro Badge, Toggles)
  // ---------------------------------------------------------------------------
  Widget _buildProfileScreenSimulation() {
    return _InteractiveProfileSimulation(
      isDarkMode: _isDarkMode,
      node: widget.node,
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Login / Register Screen Simulation (Email/Password, CTAs, Tabs)
  // ---------------------------------------------------------------------------
  Widget _buildAuthScreenSimulation() {
    return _InteractiveAuthSimulation(
      isDarkMode: _isDarkMode,
      node: widget.node,
    );
  }

  // ---------------------------------------------------------------------------
  // 3. DashboardScreen Simulation (KPI cards, Recent Activity, Bottom Nav)
  // ---------------------------------------------------------------------------
  Widget _buildDashboardScreenSimulation() {
    return _InteractiveDashboardSimulation(
      isDarkMode: _isDarkMode,
      node: widget.node,
    );
  }

  // ---------------------------------------------------------------------------
  // 4. ExploreScreen Simulation (Search Bar, Filter Chips, Feed Cards)
  // ---------------------------------------------------------------------------
  Widget _buildExploreScreenSimulation() {
    return _InteractiveExploreSimulation(
      isDarkMode: _isDarkMode,
      node: widget.node,
    );
  }

  // ---------------------------------------------------------------------------
  // 5. SplashScreen Simulation (Pulsing Logo, AuthGuard Pipeline)
  // ---------------------------------------------------------------------------
  Widget _buildSplashScreenSimulation() {
    return _InteractiveSplashSimulation(
      isDarkMode: _isDarkMode,
      pulseAnimation: _pulseAnimation,
      node: widget.node,
    );
  }

  // ---------------------------------------------------------------------------
  // 6. Generic / AI Screen Simulation
  // ---------------------------------------------------------------------------
  Widget _buildCustomScreenSimulation() {
    return _InteractiveCustomSimulation(
      isDarkMode: _isDarkMode,
      node: widget.node,
    );
  }
}

// =============================================================================
// INTERACTIVE PROFILE SCREEN IMPLEMENTATION
// =============================================================================
class _InteractiveProfileSimulation extends StatefulWidget {
  final bool isDarkMode;
  final RouteNode? node;

  const _InteractiveProfileSimulation({
    required this.isDarkMode,
    this.node,
  });

  @override
  State<_InteractiveProfileSimulation> createState() =>
      _InteractiveProfileSimulationState();
}

class _InteractiveProfileSimulationState
    extends State<_InteractiveProfileSimulation> {
  bool _biometrics = true;
  bool _notifications = true;
  bool _developerMode = true;
  bool _autoSync = false;
  int _cacheMb = 142;
  String _profileName = 'Alex Morgan';
  final String _userRole = 'Senior Mobile Architect';

  void _clearCache() {
    setState(() => _cacheMb = 0);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Storage cache cleared successfully (0 MB)'),
        duration: Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtextColor =
        widget.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBg =
        widget.isDarkMode ? const Color(0xFF141B2D) : Colors.white;
    final borderColor =
        widget.isDarkMode ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // App Bar Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Profile',
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit_note_rounded, color: subtextColor, size: 20),
                onPressed: () {
                  setState(() {
                    _profileName = _profileName == 'Alex Morgan'
                        ? 'Alexandra M. Dev'
                        : 'Alex Morgan';
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          // User Avatar & Pro Badge
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF38BDF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(3),
                child: CircleAvatar(
                  backgroundColor: cardBg,
                  child: const Icon(
                    Icons.person_rounded,
                    size: 48,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 12, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // User Name & Role
          Text(
            _profileName,
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '$_userRole • @alex.flutter',
            style: TextStyle(color: subtextColor, fontSize: 12),
          ),
          const SizedBox(height: 10),

          // FLRD Pro Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded, size: 14, color: Colors.amber),
                SizedBox(width: 4),
                Text(
                  'FLRD PRO TIER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Stats Metric Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('24', 'Projects', textColor, subtextColor),
                Container(height: 24, width: 1, color: borderColor),
                _buildStatItem('1.4k', 'Stars', textColor, subtextColor),
                Container(height: 24, width: 1, color: borderColor),
                _buildStatItem('99.4%', 'Uptime', textColor, subtextColor),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Interactive Preferences Toggles
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  SwitchListTile(
                  dense: true,
                  title: Text(
                    'Biometric Authentication',
                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('FaceID & Fingerprint security',
                      style: TextStyle(color: subtextColor, fontSize: 11)),
                  secondary: const Icon(Icons.fingerprint_rounded, color: AppColors.primary, size: 20),
                  value: _biometrics,
                  onChanged: (v) => setState(() => _biometrics = v),
                ),
                Divider(height: 1, color: borderColor),
                SwitchListTile(
                  dense: true,
                  title: Text(
                    'Push Notifications',
                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('Realtime deployment alerts',
                      style: TextStyle(color: subtextColor, fontSize: 11)),
                  secondary: const Icon(Icons.notifications_active_rounded,
                      color: AppColors.secondary, size: 20),
                  value: _notifications,
                  onChanged: (v) => setState(() => _notifications = v),
                ),
                Divider(height: 1, color: borderColor),
                SwitchListTile(
                  dense: true,
                  title: Text(
                    'Developer Sandbox Mode',
                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('Enable local route inspector',
                      style: TextStyle(color: subtextColor, fontSize: 11)),
                  secondary: const Icon(Icons.developer_mode_rounded,
                      color: Colors.amber, size: 20),
                  value: _developerMode,
                  onChanged: (v) => setState(() => _developerMode = v),
                ),
                Divider(height: 1, color: borderColor),
                SwitchListTile(
                  dense: true,
                  title: Text(
                    'Auto Cloud Sync',
                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('Sync schemas with Supabase',
                      style: TextStyle(color: subtextColor, fontSize: 11)),
                  secondary: const Icon(Icons.cloud_sync_rounded,
                      color: Color(0xFF10B981), size: 20),
                  value: _autoSync,
                  onChanged: (v) => setState(() => _autoSync = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

          // Cache and Storage Action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.storage_rounded, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Local Cache: $_cacheMb MB',
                          style: TextStyle(color: textColor, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _cacheMb > 0 ? _clearCache : null,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  child: const Text('Clear Cache', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String val, String label, Color textColor, Color subtextColor) {
    return Column(
      children: [
        Text(
          val,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: subtextColor, fontSize: 10),
        ),
      ],
    );
  }
}

// =============================================================================
// INTERACTIVE AUTH SCREEN IMPLEMENTATION
// =============================================================================
class _InteractiveAuthSimulation extends StatefulWidget {
  final bool isDarkMode;
  final RouteNode? node;

  const _InteractiveAuthSimulation({
    required this.isDarkMode,
    this.node,
  });

  @override
  State<_InteractiveAuthSimulation> createState() =>
      _InteractiveAuthSimulationState();
}

class _InteractiveAuthSimulationState extends State<_InteractiveAuthSimulation> {
  int _authTabIndex = 0; // 0: Login, 1: Register
  bool _isPasswordVisible = false;
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _statusMessage;

  final TextEditingController _nameController =
      TextEditingController(text: 'Alex Morgan');
  final TextEditingController _emailController =
      TextEditingController(text: 'alex.morgan@flutter.dev');
  final TextEditingController _passwordController =
      TextEditingController(text: 'SecretPass123!');

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submitAuth() {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = _authTabIndex == 0
            ? 'Authenticated as ${_emailController.text}'
            : 'Account registered for ${_emailController.text}!';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtextColor =
        widget.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final inputBg =
        widget.isDarkMode ? const Color(0xFF141B2D) : const Color(0xFFF1F5F9);
    final borderColor =
        widget.isDarkMode ? const Color(0x1FFFFFFF) : const Color(0xFFCBD5E1);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // App Logo Icon
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.bolt_rounded, size: 32, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),

          // Title & Subtitle
          Text(
            _authTabIndex == 0 ? 'Welcome Back' : 'Create Free Account',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _authTabIndex == 0
                ? 'Sign in to access your cloud workspace'
                : 'Rapidly architect production Flutter apps',
            textAlign: TextAlign.center,
            style: TextStyle(color: subtextColor, fontSize: 12),
          ),
          const SizedBox(height: 18),

          // Segmented Auth Mode Switcher
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _authTabIndex = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _authTabIndex == 0
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Sign In',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _authTabIndex == 0
                              ? Colors.white
                              : subtextColor,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _authTabIndex = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _authTabIndex == 1
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Register',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _authTabIndex == 1
                              ? Colors.white
                              : subtextColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Full Name Input (Register mode)
          if (_authTabIndex == 1) ...[
            Text('Full Name', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              style: TextStyle(color: textColor, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: inputBg,
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Email Input
          Text('Email Address', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _emailController,
            style: TextStyle(color: textColor, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: inputBg,
              prefixIcon: const Icon(Icons.email_outlined, size: 18, color: AppColors.textMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),

          // Password Input
          Text('Password', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            style: TextStyle(color: textColor, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: inputBg,
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textMuted),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),

          // Remember Me Checkbox & Forgot Password
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _rememberMe = v ?? true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('Remember me', style: TextStyle(color: subtextColor, fontSize: 11)),
                ],
              ),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password reset link simulated')),
                  );
                },
                child: const Text('Forgot?', style: TextStyle(fontSize: 11, color: AppColors.secondary)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Primary Submit CTA Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _isLoading ? null : _submitAuth,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _authTabIndex == 0 ? 'Sign In to Workspace' : 'Create Free Account',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
          ),

          // Status Feedback Banner
          if (_statusMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
              ),
              child: Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Social Auth Divider
          Row(
            children: [
              Expanded(child: Divider(color: borderColor)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('OR CONTINUE WITH', style: TextStyle(color: subtextColor, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
              Expanded(child: Divider(color: borderColor)),
            ],
          ),
          const SizedBox(height: 12),

          // Social Login Buttons
          Row(
            children: [
              Expanded(child: _buildSocialBtn(Icons.g_mobiledata_rounded, 'Google', inputBg, borderColor, textColor)),
              const SizedBox(width: 8),
              Expanded(child: _buildSocialBtn(Icons.terminal_rounded, 'GitHub', inputBg, borderColor, textColor)),
              const SizedBox(width: 8),
              Expanded(child: _buildSocialBtn(Icons.apple_rounded, 'Apple', inputBg, borderColor, textColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSocialBtn(IconData icon, String label, Color bg, Color border, Color text) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: bg,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: () {
        setState(() => _statusMessage = 'Signed in via $label simulation');
      },
      icon: Icon(icon, size: 16, color: text),
      label: Text(label, style: TextStyle(color: text, fontSize: 10)),
    );
  }
}

// =============================================================================
// INTERACTIVE DASHBOARD SCREEN IMPLEMENTATION
// =============================================================================
class _InteractiveDashboardSimulation extends StatefulWidget {
  final bool isDarkMode;
  final RouteNode? node;

  const _InteractiveDashboardSimulation({
    required this.isDarkMode,
    this.node,
  });

  @override
  State<_InteractiveDashboardSimulation> createState() =>
      _InteractiveDashboardSimulationState();
}

class _InteractiveDashboardSimulationState
    extends State<_InteractiveDashboardSimulation> {
  int _activeNavIndex = 0;
  String _selectedRange = '30D';
  int _unreadNotifications = 3;

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtextColor =
        widget.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBg =
        widget.isDarkMode ? const Color(0xFF141B2D) : Colors.white;
    final borderColor =
        widget.isDarkMode ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0);

    return Column(
      children: [
        // Scrollable Dashboard Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 54, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Greeting & Notification Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome back, Alex 👋',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Production Architecture Overview',
                            style: TextStyle(color: subtextColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Badge(
                        isLabelVisible: _unreadNotifications > 0,
                        label: Text('$_unreadNotifications'),
                        child: Icon(Icons.notifications_outlined, color: textColor, size: 20),
                      ),
                      onPressed: () {
                        setState(() => _unreadNotifications = 0);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Notifications marked as read')),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Range Filter Chips
                Row(
                  children: ['Today', '7D', '30D', '1Y'].map((range) {
                    final isSelected = _selectedRange == range;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(range),
                        labelStyle: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : subtextColor,
                        ),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        backgroundColor: cardBg,
                        onSelected: (_) => setState(() => _selectedRange = range),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // KPI Metric Cards (2x2 Grid)
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        'Total Revenue',
                        '\$24,850',
                        '+18.4%',
                        const Color(0xFF10B981),
                        cardBg,
                        borderColor,
                        textColor,
                        subtextColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricCard(
                        'Active Users',
                        '4,821',
                        '+7.2%',
                        AppColors.secondary,
                        cardBg,
                        borderColor,
                        textColor,
                        subtextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        'API Latency',
                        '38 ms',
                        '-14%',
                        Colors.purpleAccent,
                        cardBg,
                        borderColor,
                        textColor,
                        subtextColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricCard(
                        'Error Rate',
                        '0.02%',
                        'Optimal',
                        const Color(0xFF10B981),
                        cardBg,
                        borderColor,
                        textColor,
                        subtextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Quick Action Buttons
                Text(
                  'Quick Actions',
                  style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildQuickAction('Deploy Screen', Icons.rocket_launch_rounded, AppColors.primary),
                      _buildQuickAction('Inspect Routes', Icons.alt_route_rounded, AppColors.secondary),
                      _buildQuickAction('Run Doctor', Icons.health_and_safety_rounded, const Color(0xFF10B981)),
                      _buildQuickAction('Security Audit', Icons.shield_rounded, Colors.amber),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Recent Activity Feed
                Text(
                  'Recent Activity',
                  style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      children: [
                        _buildActivityItem('Release v2.4.0 deployed to Cloud', '12m ago', Icons.cloud_done_rounded, const Color(0xFF10B981), textColor, subtextColor),
                        Divider(height: 1, color: borderColor),
                        _buildActivityItem('GoRouter tree synchronized (5 nodes)', '1h ago', Icons.route_rounded, AppColors.secondary, textColor, subtextColor),
                        Divider(height: 1, color: borderColor),
                        _buildActivityItem('Database migration verified', '3h ago', Icons.storage_rounded, AppColors.primary, textColor, subtextColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Interactive Bottom Navigation Bar
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: cardBg,
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.dashboard_rounded, 'Home'),
              _buildNavItem(1, Icons.explore_rounded, 'Explore'),
              _buildNavItem(2, Icons.analytics_rounded, 'Metrics'),
              _buildNavItem(3, Icons.person_rounded, 'Profile'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    String badge,
    Color badgeColor,
    Color bg,
    Color border,
    Color text,
    Color subtext,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: subtext, fontSize: 10),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(badge, style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildQuickAction(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.15),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Triggered $title')),
          );
        },
        icon: Icon(icon, size: 14),
        label: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildActivityItem(
    String title,
    String time,
    IconData icon,
    Color iconColor,
    Color text,
    Color subtext,
  ) {
    return ListTile(
      dense: true,
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 14),
      ),
      title: Text(title, style: TextStyle(color: text, fontSize: 11, fontWeight: FontWeight.w500)),
      trailing: Text(time, style: TextStyle(color: subtext, fontSize: 9)),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _activeNavIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeNavIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 19,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// INTERACTIVE EXPLORE SCREEN IMPLEMENTATION
// =============================================================================
class _InteractiveExploreSimulation extends StatefulWidget {
  final bool isDarkMode;
  final RouteNode? node;

  const _InteractiveExploreSimulation({
    required this.isDarkMode,
    this.node,
  });

  @override
  State<_InteractiveExploreSimulation> createState() =>
      _InteractiveExploreSimulationState();
}

class _InteractiveExploreSimulationState
    extends State<_InteractiveExploreSimulation> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  final Set<String> _favoriteIds = {'saas_dashboard'};
  final Set<String> _installedIds = {'supabase_auth'};

  final List<Map<String, dynamic>> _catalogItems = [
    {
      'id': 'saas_dashboard',
      'title': 'SaaS Dashboard Pro',
      'category': 'UI Kits',
      'rating': 4.9,
      'downloads': '1.2k',
      'desc': 'Clean Riverpod 2.5 + GoRouter architecture with responsive glass charts.',
      'tag': 'Featured',
    },
    {
      'id': 'supabase_auth',
      'title': 'Supabase Clean Auth',
      'category': 'Auth',
      'rating': 4.8,
      'downloads': '890',
      'desc': 'OAuth2, Biometric guard, session refreshing & role-based route access.',
      'tag': 'Popular',
    },
    {
      'id': 'ai_copilot',
      'title': 'Gemini 1.5 Code Copilot',
      'category': 'AI Agents',
      'rating': 5.0,
      'downloads': '2.4k',
      'desc': 'Context-aware screen generator with live AST patching and syntax highlighting.',
      'tag': 'Trending',
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtextColor =
        widget.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBg =
        widget.isDarkMode ? const Color(0xFF141B2D) : Colors.white;
    final inputBg =
        widget.isDarkMode ? const Color(0xFF111726) : const Color(0xFFF1F5F9);
    final borderColor =
        widget.isDarkMode ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0);

    final filteredItems = _catalogItems.where((item) {
      if (_selectedCategory != 'All' && item['category'] != _selectedCategory) {
        return false;
      }
      if (_searchController.text.isNotEmpty) {
        final query = _searchController.text.toLowerCase();
        return item['title'].toString().toLowerCase().contains(query) ||
            item['desc'].toString().toLowerCase().contains(query);
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 54, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Input
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: textColor, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: inputBg,
              hintText: 'Search templates, packages, AI screens...',
              hintStyle: TextStyle(color: subtextColor, fontSize: 11),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () => setState(() => _searchController.clear()),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
            ),
          ),
          const SizedBox(height: 12),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'UI Kits', 'Auth', 'AI Agents', 'Packages'].map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(cat),
                    labelStyle: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : subtextColor,
                    ),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: cardBg,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Featured Hero Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF38BDF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('FLUTTER 3.24 READY', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Architectural Blueprints',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Instant clean-architecture scaffolds for production apps.',
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.rocket_rounded, size: 38, color: Colors.white),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Feed Cards
          Text(
            'Explore Blueprints (${filteredItems.length})',
            style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          ...filteredItems.map((item) {
            final id = item['id'] as String;
            final isFav = _favoriteIds.contains(id);
            final isInstalled = _installedIds.contains(id);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item['title'] as String,
                          style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 16,
                          color: isFav ? AppColors.danger : AppColors.textMuted,
                        ),
                        onPressed: () {
                          setState(() {
                            if (isFav) {
                              _favoriteIds.remove(id);
                            } else {
                              _favoriteIds.add(id);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  Text(
                    item['desc'] as String,
                    style: TextStyle(color: subtextColor, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                      const SizedBox(width: 3),
                      Text('${item['rating']}', style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      Icon(Icons.download_rounded, size: 13, color: subtextColor),
                      const SizedBox(width: 2),
                      Text('${item['downloads']}', style: TextStyle(color: subtextColor, fontSize: 10)),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isInstalled ? AppColors.success : AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () {
                          setState(() {
                            if (isInstalled) {
                              _installedIds.remove(id);
                            } else {
                              _installedIds.add(id);
                            }
                          });
                        },
                        child: Text(
                          isInstalled ? 'Installed' : 'Install',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// =============================================================================
// INTERACTIVE SPLASH SCREEN IMPLEMENTATION
// =============================================================================
class _InteractiveSplashSimulation extends StatefulWidget {
  final bool isDarkMode;
  final Animation<double> pulseAnimation;
  final RouteNode? node;

  const _InteractiveSplashSimulation({
    required this.isDarkMode,
    required this.pulseAnimation,
    this.node,
  });

  @override
  State<_InteractiveSplashSimulation> createState() =>
      _InteractiveSplashSimulationState();
}

class _InteractiveSplashSimulationState
    extends State<_InteractiveSplashSimulation> {
  bool _isAuthGuardVerified = true;
  bool _isEngineReady = true;
  bool _hasProceeded = false;

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtextColor =
        widget.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBg =
        widget.isDarkMode ? const Color(0xFF141B2D) : Colors.white;
    final borderColor =
        widget.isDarkMode ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing Flutter / FLRD Brand Icon
            AnimatedBuilder(
              animation: widget.pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: widget.pulseAnimation.value,
                  child: child,
                );
              },
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.45),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.alt_route_rounded, size: 48, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // App Brand Name & Tagline
            Text(
              'FLRD Studio',
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Architecting Next-Gen Flutter Apps',
              style: TextStyle(color: subtextColor, fontSize: 12),
            ),
            const SizedBox(height: 24),

            // AuthGuard Status Pipeline Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.security_rounded, size: 14, color: Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'GoRouter AuthGuard Pipeline',
                          style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildCheckStep(
                    'Flutter Engine & Isolate initialization',
                    _isEngineReady,
                    textColor,
                    onTap: () => setState(() => _isEngineReady = !_isEngineReady),
                  ),
                  const SizedBox(height: 6),
                  _buildCheckStep(
                    'Supabase JWT token validation',
                    _isAuthGuardVerified,
                    textColor,
                    onTap: () => setState(() => _isAuthGuardVerified = !_isAuthGuardVerified),
                  ),
                  const SizedBox(height: 6),
                  _buildCheckStep(
                    'Target Route: ${widget.node?.path ?? "/"}',
                    true,
                    textColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Interactive Launch Simulation Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _hasProceeded ? AppColors.success : AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                setState(() => _hasProceeded = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Simulated transition: Route guard approved')),
                );
              },
              icon: Icon(
                _hasProceeded ? Icons.check_circle_rounded : Icons.play_arrow_rounded,
                size: 16,
              ),
              label: Text(
                _hasProceeded ? 'Route Guard Approved' : 'Simulate Launch Transition',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckStep(
    String text,
    bool isChecked,
    Color textColor, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              isChecked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 14,
              color: isChecked ? const Color(0xFF10B981) : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: textColor, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// INTERACTIVE CUSTOM / AI SCREEN IMPLEMENTATION
// =============================================================================
class _InteractiveCustomSimulation extends StatefulWidget {
  final bool isDarkMode;
  final RouteNode? node;

  const _InteractiveCustomSimulation({
    required this.isDarkMode,
    this.node,
  });

  @override
  State<_InteractiveCustomSimulation> createState() =>
      _InteractiveCustomSimulationState();
}

class _InteractiveCustomSimulationState
    extends State<_InteractiveCustomSimulation> {
  final Map<DevicePermission, bool> _permissionState = {};
  final TextEditingController _paramController =
      TextEditingController(text: 'sample_query_param');
  String? _executionResult;

  @override
  void initState() {
    super.initState();
    for (final perm in widget.node?.requiredPermissions ?? []) {
      _permissionState[perm] = true;
    }
  }

  @override
  void dispose() {
    _paramController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtextColor =
        widget.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBg =
        widget.isDarkMode ? const Color(0xFF141B2D) : Colors.white;
    final borderColor =
        widget.isDarkMode ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 54, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card with Node Info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.node?.icon ?? Icons.widgets_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.node?.title ?? 'Custom Screen',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (widget.node?.isAIGenerated == true) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purpleAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('AI Screen', style: TextStyle(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.node?.subtitle ?? 'Synthesized dynamically from RouteNode schema',
                        style: TextStyle(color: subtextColor, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Permissions Checklist
          if (widget.node?.requiredPermissions.isNotEmpty == true) ...[
            Text('Required Permissions', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: widget.node!.requiredPermissions.map((perm) {
                    final isGranted = _permissionState[perm] ?? false;
                    return SwitchListTile(
                      dense: true,
                      title: Text(perm.name, style: TextStyle(color: textColor, fontSize: 12)),
                      subtitle: Text(perm.description, style: TextStyle(color: subtextColor, fontSize: 10)),
                      value: isGranted,
                      onChanged: (v) => setState(() => _permissionState[perm] = v),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Interactive Screen Action Simulation
          Text('Interactive Controller Action', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _paramController,
                  style: TextStyle(color: textColor, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Screen State / Action Parameter',
                    labelStyle: TextStyle(color: subtextColor, fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () {
                    setState(() {
                      _executionResult = 'State updated successfully with ${_paramController.text}';
                    });
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Dispatch Screen Action', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                if (_executionResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                    ),
                    child: Text(
                      _executionResult!,
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INTERACTIVE CODE-DRIVEN INPUT WIDGET
// =============================================================================

class _InteractiveInputWidget extends StatefulWidget {
  final ParsedInputNode input;
  final bool isDarkMode;

  const _InteractiveInputWidget({
    required this.input,
    required this.isDarkMode,
  });

  @override
  State<_InteractiveInputWidget> createState() =>
      _InteractiveInputWidgetState();
}

class _InteractiveInputWidgetState extends State<_InteractiveInputWidget> {
  late final TextEditingController _controller;
  bool _obscure = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _obscure = widget.input.obscureText;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtextColor =
        widget.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final inputBg =
        widget.isDarkMode ? const Color(0xFF141B2D) : const Color(0xFFF1F5F9);
    final borderColor =
        widget.isDarkMode ? const Color(0x1FFFFFFF) : const Color(0xFFCBD5E1);

    return TextField(
      controller: _controller,
      obscureText: _obscure,
      style: TextStyle(color: textColor, fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.input.labelText,
        hintText: widget.input.hintText,
        labelStyle: TextStyle(color: subtextColor, fontSize: 12),
        hintStyle: TextStyle(color: subtextColor, fontSize: 12),
        prefixIcon: widget.input.prefixIcon != null
            ? Icon(widget.input.prefixIcon, size: 18, color: subtextColor)
            : null,
        suffixIcon: widget.input.obscureText
            ? IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 18,
                  color: subtextColor,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
        filled: true,
        fillColor: inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

// =============================================================================
// PARSED SCREEN DATA MODEL & NODES
// =============================================================================

class ParsedScreenData {
  final Color? scaffoldBackgroundColor;
  final ParsedAppBar? appBar;
  final List<ParsedWidgetNode> bodyWidgets;
  final bool isCentered;
  final ParsedContainerCard? mainCard;
  final Map<String, Color> colorTokens;

  const ParsedScreenData({
    this.scaffoldBackgroundColor,
    this.appBar,
    this.bodyWidgets = const [],
    this.isCentered = false,
    this.mainCard,
    this.colorTokens = const {},
  });
}

class ParsedAppBar {
  final String title;
  final Color? backgroundColor;
  final Color? titleColor;
  final IconData? leadingIcon;
  final List<IconData> actionIcons;

  const ParsedAppBar({
    required this.title,
    this.backgroundColor,
    this.titleColor,
    this.leadingIcon,
    this.actionIcons = const [],
  });
}

abstract class ParsedWidgetNode {}

class ParsedTextNode extends ParsedWidgetNode {
  final String text;
  final double? fontSize;
  final FontWeight? fontWeight;
  final Color? color;
  final TextAlign? textAlign;

  ParsedTextNode({
    required this.text,
    this.fontSize,
    this.fontWeight,
    this.color,
    this.textAlign,
  });
}

class ParsedIconNode extends ParsedWidgetNode {
  final IconData icon;
  final Color? color;
  final double? size;

  ParsedIconNode({
    required this.icon,
    this.color,
    this.size,
  });
}

enum ParsedButtonType { elevated, outlined, text }

class ParsedButtonNode extends ParsedWidgetNode {
  final String label;
  final IconData? icon;
  final ParsedButtonType type;
  final Color? backgroundColor;
  final Color? foregroundColor;

  ParsedButtonNode({
    required this.label,
    this.icon,
    this.type = ParsedButtonType.elevated,
    this.backgroundColor,
    this.foregroundColor,
  });
}

class ParsedInputNode extends ParsedWidgetNode {
  final String? labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final bool obscureText;

  ParsedInputNode({
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.obscureText = false,
  });
}

class ParsedContainerCard extends ParsedWidgetNode {
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final List<ParsedWidgetNode> children;

  ParsedContainerCard({
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.padding,
    this.children = const [],
  });
}

class ParsedSizedBoxNode extends ParsedWidgetNode {
  final double height;
  ParsedSizedBoxNode(this.height);
}

// =============================================================================
// DART CODE SCREEN PARSER IMPLEMENTATION
// =============================================================================

class DartCodeScreenParser {
  static int _findMatchingParen(String text, int openParenIndex) {
    int depth = 0;
    for (int i = openParenIndex; i < text.length; i++) {
      if (text[i] == '(') {
        depth++;
      } else if (text[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static ParsedScreenData parse(
    String code, {
    bool isDarkMode = true,
    String? nodeTitle,
  }) {
    if (code.trim().isEmpty) {
      return const ParsedScreenData();
    }

    try {
      // 1. Color tokens extraction
      final colorTokens = _extractColorTokens(code);

      // 2. Scaffold background color
      Color? scaffoldBg;
      final scaffoldBgMatch = RegExp(
        r'Scaffold\s*\([^;]*?backgroundColor:\s*([a-zA-Z0-9_.]+|\bColor\([^)]+\))',
        dotAll: true,
      ).firstMatch(code);
      if (scaffoldBgMatch != null) {
        scaffoldBg =
            _resolveColor(scaffoldBgMatch.group(1)!, colorTokens, isDarkMode);
      }

      // 3. AppBar extraction
      ParsedAppBar? appBar;
      final appBarRegexMatch = RegExp(r'\bAppBar\s*\(').firstMatch(code);
      if (appBarRegexMatch != null) {
        final openParen = appBarRegexMatch.end - 1;
        final closeParen = _findMatchingParen(code, openParen);
        final appBarContent = closeParen != -1
            ? code.substring(openParen + 1, closeParen)
            : code.substring(openParen + 1);

        // Title
        String title = '';
        final titleMatch = RegExp(
          r'''title:\s*(?:const\s+)?Text\s*\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
          dotAll: true,
        ).firstMatch(appBarContent);
        if (titleMatch != null) {
          title = titleMatch.group(1) ?? titleMatch.group(2) ?? '';
          if (title.contains(r'$displayTitle') && nodeTitle != null) {
            title = title.replaceAll(r'$displayTitle', nodeTitle);
          }
        }

        // Title Color
        Color? titleColor;
        final titleColorMatch = RegExp(
          r'color:\s*([^,\n\)]+(?:\([^)]*\))?)',
        ).firstMatch(appBarContent);
        if (titleColorMatch != null) {
          titleColor =
              _resolveColor(titleColorMatch.group(1)!, colorTokens, isDarkMode);
        }

        // Background Color
        Color? appBarBg;
        final appBarBgMatch = RegExp(
          r'backgroundColor:\s*([^,\n\)]+(?:\([^)]*\))?)',
        ).firstMatch(appBarContent);
        if (appBarBgMatch != null) {
          appBarBg =
              _resolveColor(appBarBgMatch.group(1)!, colorTokens, isDarkMode);
        }

        // Leading icon
        IconData? leadingIcon;
        final leadingMatch =
            RegExp(r'leading:\s*[^)]*?Icons\.([a-zA-Z0-9_]+)')
                .firstMatch(appBarContent);
        if (leadingMatch != null) {
          leadingIcon = _resolveIcon(leadingMatch.group(1)!);
        }

        // Action icons
        final List<IconData> actionIcons = [];
        for (final m
            in RegExp(r'Icons\.([a-zA-Z0-9_]+)').allMatches(appBarContent)) {
          final icon = _resolveIcon(m.group(1)!);
          if (icon != leadingIcon && !actionIcons.contains(icon)) {
            actionIcons.add(icon);
          }
        }

        appBar = ParsedAppBar(
          title: title,
          backgroundColor: appBarBg,
          titleColor: titleColor,
          leadingIcon: leadingIcon,
          actionIcons: actionIcons,
        );
      }

      // 4. Extract body section
      String bodyCode = code;
      final bodyMatch = RegExp(
        r'body:\s*(.*?)(?:\n\s*floatingActionButton:|\n\s*bottomNavigationBar:|\n\s*\);|\Z)',
        dotAll: true,
      ).firstMatch(code);
      if (bodyMatch != null) {
        bodyCode = bodyMatch.group(1)!;
      }

      // Check if centered
      final isCentered = RegExp(
        r'(?:Center\s*\(|mainAxisAlignment:\s*MainAxisAlignment\.center)',
      ).hasMatch(bodyCode);

      // 5. Check for Container / Card
      ParsedContainerCard? mainCard;
      int? containerStart;
      int? containerEnd;

      final containerRegexMatch = RegExp(r'\bContainer\s*\(').firstMatch(bodyCode);
      if (containerRegexMatch != null) {
        final openParen = containerRegexMatch.end - 1;
        final closeParen = _findMatchingParen(bodyCode, openParen);
        if (closeParen != -1) {
          final containerContent = bodyCode.substring(openParen + 1, closeParen);
          if (containerContent.contains('BoxDecoration')) {
            containerStart = containerRegexMatch.start;
            containerEnd = closeParen + 1;

            Color? cardBg;
            Color? borderColor;
            double? borderRadius;

            final decoRegexMatch = RegExp(r'\bBoxDecoration\s*\(').firstMatch(containerContent);
            if (decoRegexMatch != null) {
              final dOpen = decoRegexMatch.end - 1;
              final dClose = _findMatchingParen(containerContent, dOpen);
              final decoContent = dClose != -1
                  ? containerContent.substring(dOpen + 1, dClose)
                  : containerContent.substring(dOpen + 1);

              final colorMatch = RegExp(r'color:\s*([^,\n\)]+(?:\([^)]*\))?)').firstMatch(decoContent);
              if (colorMatch != null) {
                cardBg = _resolveColor(colorMatch.group(1)!, colorTokens, isDarkMode);
              }

              final radiusMatch = RegExp(r'BorderRadius\.circular\s*\(\s*([0-9.]+)\s*\)').firstMatch(decoContent);
              if (radiusMatch != null) {
                borderRadius = double.tryParse(radiusMatch.group(1)!);
              }

              final borderMatch = RegExp(r'Border\.all\s*\([^)]*?color:\s*([^,\n\)]+(?:\([^)]*\))?)', dotAll: true).firstMatch(decoContent);
              if (borderMatch != null) {
                borderColor = _resolveColor(borderMatch.group(1)!, colorTokens, isDarkMode);
              }
            }

            // Padding
            EdgeInsetsGeometry? padding;
            final padMatch = RegExp(
              r'padding:\s*(?:const\s+)?EdgeInsets\.all\s*\(\s*([0-9.]+)\s*\)',
            ).firstMatch(containerContent);
            if (padMatch != null) {
              padding = EdgeInsets.all(double.tryParse(padMatch.group(1)!) ?? 16.0);
            } else {
              final symPad = RegExp(
                r'padding:\s*(?:const\s+)?EdgeInsets\.symmetric\s*\([^)]*horizontal:\s*([0-9.]+)[^)]*vertical:\s*([0-9.]+)',
                dotAll: true,
              ).firstMatch(containerContent);
              if (symPad != null) {
                padding = EdgeInsets.symmetric(
                  horizontal: double.tryParse(symPad.group(1)!) ?? 16.0,
                  vertical: double.tryParse(symPad.group(2)!) ?? 16.0,
                );
              }
            }

            final cardWidgets = _extractWidgetsFromSnippet(
              containerContent,
              colorTokens,
              isDarkMode,
              nodeTitle: nodeTitle,
            );

            mainCard = ParsedContainerCard(
              backgroundColor: cardBg,
              borderColor: borderColor,
              borderRadius: borderRadius,
              padding: padding,
              children: cardWidgets,
            );
          }
        }
      }

      // Also extract remaining body widgets (or all body widgets if no container)
      final allBodyWidgets = _extractWidgetsFromSnippet(
        bodyCode,
        colorTokens,
        isDarkMode,
        excludeStart: containerStart,
        excludeEnd: containerEnd,
        nodeTitle: nodeTitle,
      );

      return ParsedScreenData(
        scaffoldBackgroundColor: scaffoldBg,
        appBar: appBar,
        bodyWidgets: allBodyWidgets,
        isCentered: isCentered,
        mainCard: mainCard,
        colorTokens: colorTokens,
      );
    } catch (_) {
      return const ParsedScreenData();
    }
  }

  static Map<String, Color> _extractColorTokens(String code) {
    final Map<String, Color> tokens = {};
    final regex = RegExp(
      r'(?:static\s+const\s+|const\s+)?Color\s+([a-zA-Z0-9_]+)\s*=\s*(?:const\s+)?Color\s*\(\s*(0x[0-9a-fA-F]+)\s*\)',
    );
    for (final m in regex.allMatches(code)) {
      final name = m.group(1)!;
      final val = int.tryParse(m.group(2)!);
      if (val != null) {
        tokens[name] = Color(val);
      }
    }
    return tokens;
  }

  static Color? _resolveColor(
    String expr,
    Map<String, Color> tokens,
    bool isDarkMode,
  ) {
    final clean = expr.trim().replaceAll(';', '').replaceAll(',', '');

    // Check hex Color(0x...) or 0x...
    final hexMatch = RegExp(r'0x[0-9a-fA-F]+').firstMatch(clean);
    if (hexMatch != null) {
      final hex = int.tryParse(hexMatch.group(0)!);
      if (hex != null) return Color(hex);
    }

    // AppColors.<token> or <token>
    final tokenName = clean.startsWith('AppColors.')
        ? clean.substring('AppColors.'.length)
        : clean;
    if (tokens.containsKey(tokenName)) {
      return tokens[tokenName];
    }

    // Material Colors.<name> (must have word boundary)
    final materialMatch = RegExp(r'\bColors\.([a-zA-Z0-9_]+)').firstMatch(clean);
    if (materialMatch != null) {
      final name = materialMatch.group(1)!.toLowerCase();
      switch (name) {
        case 'white':
          return Colors.white;
        case 'black':
          return Colors.black;
        case 'transparent':
          return Colors.transparent;
        case 'blue':
          return Colors.blue;
        case 'indigo':
          return Colors.indigo;
        case 'amber':
          return Colors.amber;
        case 'red':
          return Colors.red;
        case 'green':
          return Colors.green;
        case 'purple':
          return Colors.purple;
        case 'cyan':
          return Colors.cyan;
        case 'teal':
          return Colors.teal;
        case 'grey':
        case 'gray':
          return Colors.grey;
        case 'orange':
          return Colors.orange;
        case 'deeporange':
          return Colors.deepOrange;
        case 'deeppurple':
          return Colors.deepPurple;
        case 'lightgreen':
          return Colors.lightGreen;
        case 'lightblue':
          return Colors.lightBlue;
        case 'yellow':
          return Colors.yellow;
        default:
          return Colors.blue;
      }
    }

    switch (tokenName) {
      case 'background':
        return isDarkMode ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
      case 'backgroundSecondary':
        return isDarkMode ? const Color(0xFF0D121F) : const Color(0xFFF1F5F9);
      case 'surface':
        return isDarkMode ? const Color(0xFF111726) : Colors.white;
      case 'surfaceCard':
        return isDarkMode ? const Color(0xFF141B2D) : Colors.white;
      case 'border':
        return isDarkMode ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0);
      case 'primary':
        return const Color(0xFF6366F1);
      case 'secondary':
        return const Color(0xFF38BDF8);
      case 'success':
        return const Color(0xFF10B981);
      case 'danger':
        return const Color(0xFFEF4444);
      case 'textPrimary':
        return isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
      case 'textSecondary':
        return isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
      case 'textMuted':
        return const Color(0xFF64748B);
      default:
        return null;
    }
  }

  static IconData _resolveIcon(String name) {
    final clean = name
        .toLowerCase()
        .replaceAll('_rounded', '')
        .replaceAll('_outlined', '')
        .replaceAll('_sharp', '');
    switch (clean) {
      case 'widgets':
        return Icons.widgets_rounded;
      case 'alt_route':
        return Icons.alt_route_rounded;
      case 'person':
      case 'account_circle':
        return Icons.person_rounded;
      case 'settings':
        return Icons.settings_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'dashboard':
      case 'space_dashboard':
        return Icons.dashboard_rounded;
      case 'explore':
        return Icons.explore_rounded;
      case 'search':
        return Icons.search_rounded;
      case 'favorite':
        return Icons.favorite_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'bolt':
      case 'flash_on':
        return Icons.bolt_rounded;
      case 'rocket':
      case 'rocket_launch':
        return Icons.rocket_launch_rounded;
      case 'security':
      case 'shield':
        return Icons.security_rounded;
      case 'lock':
        return Icons.lock_rounded;
      case 'lock_open':
        return Icons.lock_open_rounded;
      case 'email':
      case 'mail':
        return Icons.email_rounded;
      case 'notifications':
      case 'notifications_active':
        return Icons.notifications_rounded;
      case 'storage':
        return Icons.storage_rounded;
      case 'cloud':
      case 'cloud_sync':
      case 'cloud_done':
        return Icons.cloud_rounded;
      case 'camera':
      case 'camera_alt':
        return Icons.camera_alt_rounded;
      case 'qr_code':
      case 'qr_code_scanner':
        return Icons.qr_code_scanner_rounded;
      case 'check':
      case 'check_circle':
        return Icons.check_circle_rounded;
      case 'close':
      case 'cancel':
        return Icons.close_rounded;
      case 'add':
        return Icons.add_rounded;
      case 'refresh':
        return Icons.refresh_rounded;
      case 'edit':
      case 'edit_note':
        return Icons.edit_rounded;
      case 'delete':
      case 'delete_outline':
        return Icons.delete_rounded;
      case 'phone':
        return Icons.phone_rounded;
      case 'menu':
        return Icons.menu_rounded;
      case 'arrow_back':
        return Icons.arrow_back_rounded;
      case 'arrow_forward':
        return Icons.arrow_forward_rounded;
      case 'play_arrow':
        return Icons.play_arrow_rounded;
      case 'code':
        return Icons.code_rounded;
      case 'analytics':
        return Icons.analytics_rounded;
      default:
        return Icons.widgets_rounded;
    }
  }

  static List<ParsedWidgetNode> _extractWidgetsFromSnippet(
    String snippet,
    Map<String, Color> colorTokens,
    bool isDarkMode, {
    int? excludeStart,
    int? excludeEnd,
    String? nodeTitle,
  }) {
    final List<_SnippetMatch> matches = [];

    bool isExcluded(int start, int end) {
      if (excludeStart != null && excludeEnd != null) {
        if (start >= excludeStart && end <= excludeEnd) return true;
      }
      return false;
    }

    final List<List<int>> consumedRanges = [];

    // 1. Cards
    final cardRegex = RegExp(r'\bCard\s*\(');
    for (final m in cardRegex.allMatches(snippet)) {
      if (isExcluded(m.start, m.end)) continue;
      final openParen = m.end - 1;
      final closeParen = _findMatchingParen(snippet, openParen);
      if (closeParen == -1) continue;

      consumedRanges.add([m.start, closeParen + 1]);
      final cardBody = snippet.substring(openParen + 1, closeParen);

      Color? cardColor;
      final cMatch = RegExp(
        r'color:\s*([^,\n\)]+(?:\([^)]*\))?)',
      ).firstMatch(cardBody);
      if (cMatch != null) {
        cardColor = _resolveColor(cMatch.group(1)!, colorTokens, isDarkMode);
      }

      final cardWidgets = _extractWidgetsFromSnippet(
        cardBody,
        colorTokens,
        isDarkMode,
        nodeTitle: nodeTitle,
      );
      matches.add(_SnippetMatch(
        start: m.start,
        node: ParsedContainerCard(
          backgroundColor: cardColor,
          borderRadius: 12,
          padding: const EdgeInsets.all(16),
          children: cardWidgets,
        ),
      ));
    }

    // 2. Buttons (ElevatedButton, OutlinedButton, TextButton)
    final btnRegex = RegExp(
      r'\b(ElevatedButton|OutlinedButton|TextButton)(?:\.icon)?\s*\(',
    );
    for (final m in btnRegex.allMatches(snippet)) {
      if (isExcluded(m.start, m.end)) continue;
      final openParen = m.end - 1;
      final closeParen = _findMatchingParen(snippet, openParen);
      if (closeParen == -1) continue;

      consumedRanges.add([m.start, closeParen + 1]);
      final btnTypeStr = m.group(1)!;
      final btnBody = snippet.substring(openParen + 1, closeParen);

      ParsedButtonType type = ParsedButtonType.elevated;
      if (btnTypeStr == 'OutlinedButton') type = ParsedButtonType.outlined;
      if (btnTypeStr == 'TextButton') type = ParsedButtonType.text;

      String label = 'Button';
      final labelMatch = RegExp(
        r'''(?:child|label):\s*(?:const\s+)?Text\s*\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
        dotAll: true,
      ).firstMatch(btnBody);
      if (labelMatch != null) {
        label = labelMatch.group(1) ?? labelMatch.group(2) ?? 'Button';
      }

      IconData? icon;
      final iconMatch = RegExp(r'Icons\.([a-zA-Z0-9_]+)').firstMatch(btnBody);
      if (iconMatch != null) {
        icon = _resolveIcon(iconMatch.group(1)!);
      }

      Color? bg;
      final bgMatch = RegExp(
        r'backgroundColor:\s*([^,\n\)]+(?:\([^)]*\))?)',
      ).firstMatch(btnBody);
      if (bgMatch != null) {
        bg = _resolveColor(bgMatch.group(1)!, colorTokens, isDarkMode);
      }

      Color? fg;
      final fgMatch = RegExp(
        r'foregroundColor:\s*([^,\n\)]+(?:\([^)]*\))?)',
      ).firstMatch(btnBody);
      if (fgMatch != null) {
        fg = _resolveColor(fgMatch.group(1)!, colorTokens, isDarkMode);
      }

      matches.add(_SnippetMatch(
        start: m.start,
        node: ParsedButtonNode(
          label: label,
          icon: icon,
          type: type,
          backgroundColor: bg,
          foregroundColor: fg,
        ),
      ));
    }

    // 3. Inputs (TextField, TextFormField)
    final inputRegex = RegExp(
      r'\b(TextField|TextFormField)\s*\(',
    );
    for (final m in inputRegex.allMatches(snippet)) {
      if (isExcluded(m.start, m.end)) continue;
      final openParen = m.end - 1;
      final closeParen = _findMatchingParen(snippet, openParen);
      if (closeParen == -1) continue;

      consumedRanges.add([m.start, closeParen + 1]);
      final inputBody = snippet.substring(openParen + 1, closeParen);

      String? labelText;
      final labelMatch = RegExp(
        r'''labelText:\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
      ).firstMatch(inputBody);
      if (labelMatch != null) {
        labelText = labelMatch.group(1) ?? labelMatch.group(2);
      }

      String? hintText;
      final hintMatch = RegExp(
        r'''hintText:\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
      ).firstMatch(inputBody);
      if (hintMatch != null) {
        hintText = hintMatch.group(1) ?? hintMatch.group(2);
      }

      IconData? prefixIcon;
      final iconMatch = RegExp(r'Icons\.([a-zA-Z0-9_]+)').firstMatch(inputBody);
      if (iconMatch != null) prefixIcon = _resolveIcon(iconMatch.group(1)!);

      final obscure = RegExp(r'obscureText:\s*true').hasMatch(inputBody);

      matches.add(_SnippetMatch(
        start: m.start,
        node: ParsedInputNode(
          labelText: labelText,
          hintText: hintText,
          prefixIcon: prefixIcon,
          obscureText: obscure,
        ),
      ));
    }

    bool isConsumed(int start) {
      for (final r in consumedRanges) {
        if (start >= r[0] && start < r[1]) return true;
      }
      return false;
    }

    // 4. Icons
    final iconRegex = RegExp(
      r'\bIcon\s*\(\s*Icons\.([a-zA-Z0-9_]+)(?:[^)]*?color:\s*([^,\n\)]+(?:\([^)]*\))?))?(?:[^)]*?size:\s*([0-9.]+))?',
      dotAll: true,
    );
    for (final m in iconRegex.allMatches(snippet)) {
      if (isExcluded(m.start, m.end)) continue;
      if (isConsumed(m.start)) continue;

      final iconName = m.group(1)!;
      final colorStr = m.group(2);
      final sizeStr = m.group(3);

      final icon = _resolveIcon(iconName);
      final color = colorStr != null
          ? _resolveColor(colorStr, colorTokens, isDarkMode)
          : null;
      final size = sizeStr != null ? double.tryParse(sizeStr) : null;

      matches.add(_SnippetMatch(
        start: m.start,
        node: ParsedIconNode(
          icon: icon,
          color: color,
          size: size,
        ),
      ));
    }

    // 5. Text widgets
    final textRegex = RegExp(
      r'''\bText\s*\(\s*(?:const\s+)?(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")(.*?)\)''',
      dotAll: true,
    );
    for (final m in textRegex.allMatches(snippet)) {
      if (isExcluded(m.start, m.end)) continue;
      if (isConsumed(m.start)) continue;

      String text = m.group(1) ?? m.group(2) ?? '';
      if (text.contains(r'$displayTitle') && nodeTitle != null) {
        text = text.replaceAll(r'$displayTitle', nodeTitle);
      }
      final textParams = m.group(3) ?? '';

      double? fontSize;
      final fontMatch = RegExp(r'fontSize:\s*([0-9.]+)').firstMatch(textParams);
      if (fontMatch != null) fontSize = double.tryParse(fontMatch.group(1)!);

      FontWeight? fontWeight;
      final weightMatch =
          RegExp(r'fontWeight:\s*FontWeight\.([a-zA-Z0-9_]+)')
              .firstMatch(textParams);
      if (weightMatch != null) {
        final wStr = weightMatch.group(1)!;
        switch (wStr) {
          case 'bold':
          case 'w700':
            fontWeight = FontWeight.bold;
            break;
          case 'w600':
            fontWeight = FontWeight.w600;
            break;
          case 'w500':
            fontWeight = FontWeight.w500;
            break;
          case 'w300':
          case 'light':
            fontWeight = FontWeight.w300;
            break;
          default:
            fontWeight = FontWeight.normal;
        }
      }

      Color? color;
      final colorMatch = RegExp(
        r'color:\s*([^,\n\)]+(?:\([^)]*\))?)',
      ).firstMatch(textParams);
      if (colorMatch != null) {
        color = _resolveColor(colorMatch.group(1)!, colorTokens, isDarkMode);
      }

      matches.add(_SnippetMatch(
        start: m.start,
        node: ParsedTextNode(
          text: text,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
        ),
      ));
    }

    // 6. SizedBox heights
    final sizeBoxRegex = RegExp(r'\bSizedBox\s*\(\s*height:\s*([0-9.]+)\s*\)');
    for (final m in sizeBoxRegex.allMatches(snippet)) {
      if (isExcluded(m.start, m.end)) continue;
      if (isConsumed(m.start)) continue;

      final h = double.tryParse(m.group(1)!);
      if (h != null) {
        matches.add(_SnippetMatch(
          start: m.start,
          node: ParsedSizedBoxNode(h),
        ));
      }
    }

    matches.sort((a, b) => a.start.compareTo(b.start));

    return matches.map((m) => m.node).toList();
  }
}

class _SnippetMatch {
  final int start;
  final ParsedWidgetNode node;
  _SnippetMatch({required this.start, required this.node});
}
