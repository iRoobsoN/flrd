import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../projects/models/registered_project.dart';
import '../../../wizard/models/project_config.dart';
import '../../models/route_node.dart';

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
  final bool isExpanded;
  final VoidCallback? onToggleExpand;

  const DeviceScreenEmulator({
    super.key,
    this.node,
    this.project,
    this.isExpanded = false,
    this.onToggleExpand,
  });

  /// Opens the emulator inside a modal dialog.
  static Future<void> showModal(
    BuildContext context, {
    required RouteNode node,
    RegisteredProject? project,
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
    if (oldWidget.node?.id != widget.node?.id) {
      _simulationKey = UniqueKey();
      _isDynamicIslandExpanded = false;
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
                  child: _buildInteractiveScreenContent(),
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
