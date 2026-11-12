import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../projects/models/registered_project.dart';
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

/// Archetype category for route classification.
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
    final emulatorKey = GlobalKey<DeviceScreenEmulatorState>();
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
              child: Scaffold(
                backgroundColor: AppColors.surfaceCard,
                body: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.phone_iphone_rounded, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Live Device Preview • ${node.title}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            key: const Key('modal_screenshot_button'),
                            icon: const Icon(Icons.camera_alt_rounded, size: 14),
                            label: const Text('📸 Screenshot', style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: const Size(0, 30),
                            ),
                            onPressed: () {
                              emulatorKey.currentState?.captureScreenshot(targetContext: dialogContext);
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: 'Close Modal',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: DeviceScreenEmulator(
                        key: emulatorKey,
                        node: node,
                        project: project,
                        sourceCode: sourceCode,
                        isExpanded: true,
                        onToggleExpand: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  State<DeviceScreenEmulator> createState() => DeviceScreenEmulatorState();
}

class DeviceScreenEmulatorState extends State<DeviceScreenEmulator> {
  final GlobalKey _viewportScreenshotKey = GlobalKey();
  EmulatorDevice _selectedDevice = EmulatorDevice.iphone15Pro;
  bool _isDarkMode = true;
  double? _customScale; // null means auto-fit
  bool _isDynamicIslandExpanded = false;
  Key _simulationKey = UniqueKey();
  ParsedScreenData? _parsedData;
  bool _isCapturingScreenshot = false;

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

  void _resetSimulation() {
    setState(() {
      _simulationKey = UniqueKey();
      _isDynamicIslandExpanded = false;
      _parsedData = null;
    });
  }

  /// Captures a high-resolution 2.0x PNG screenshot of the mobile screen emulator viewport
  /// and saves it to Directory.current.path/screenshots/.
  Future<String?> captureScreenshot({BuildContext? targetContext}) async {
    if (_isCapturingScreenshot) return null;
    setState(() => _isCapturingScreenshot = true);

    try {
      final boundary = _viewportScreenshotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('Screenshot failed: RenderRepaintBoundary not found');
        return null;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('Screenshot failed: byteData is null');
        return null;
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final rawRoute = widget.node?.path ?? widget.node?.id ?? 'screen';
      final sanitizedRoute = rawRoute
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceFirst(RegExp(r'^_+'), '')
          .replaceFirst(RegExp(r'_+$'), '');
      final routeStr = sanitizedRoute.isEmpty ? 'screen' : sanitizedRoute;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'flrd_screen_${routeStr}_$timestamp.png';

      final screenshotsDir = Directory('${Directory.current.path}/screenshots');
      if (!screenshotsDir.existsSync()) {
        screenshotsDir.createSync(recursive: true);
      }

      final filePath = '${screenshotsDir.path}/$filename';
      final file = File(filePath);
      file.writeAsBytesSync(pngBytes);

      final displayPath = 'screenshots/$filename';
      final effectiveContext = targetContext ?? (mounted ? context : null);
      if (effectiveContext != null && effectiveContext.mounted) {
        AppToast.success(
          effectiveContext,
          '📸 Screenshot salvo em: $displayPath',
          duration: const Duration(seconds: 3),
        );
      }
      return filePath;
    } catch (e) {
      debugPrint('Error capturing screenshot: $e');
      final effectiveContext = targetContext ?? (mounted ? context : null);
      if (effectiveContext != null && effectiveContext.mounted) {
        AppToast.error(effectiveContext, 'Erro ao capturar screenshot: $e');
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isCapturingScreenshot = false);
      }
    }
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

                final availableW = constraints.maxWidth - 20;
                final availableH = constraints.maxHeight - 20;

                // Determine scale factor
                double scale;
                if (_customScale != null) {
                  scale = _customScale!;
                } else {
                  final scaleX = availableW / deviceW;
                  final scaleY = availableH / deviceH;
                  final fitScale = math.min(scaleX, scaleY);
                  // When displayed in full vertical studio workspace (~750-850px height),
                  // provide natural comfortable scale ~90-100% without looking far away.
                  if (constraints.maxHeight >= 680 && scaleX >= 0.88 && fitScale < 0.90) {
                    scale = math.min(scaleX, 0.92).clamp(0.90, 1.0);
                  } else {
                    scale = fitScale.clamp(0.2, 1.0);
                  }
                }

                return Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: deviceW,
                            height: deviceH,
                            child: RepaintBoundary(
                              key: _viewportScreenshotKey,
                              child: _buildSmartphoneShell(),
                            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // Device Switcher & Route Badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                      size: 13,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<EmulatorDevice>(
                        value: _selectedDevice,
                        isDense: true,
                        dropdownColor: AppColors.surfaceCard,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        icon: const Icon(Icons.arrow_drop_down_rounded,
                            size: 15, color: AppColors.textSecondary),
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
              const SizedBox(width: 6),
              if (widget.node != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHover,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.node!.icon, size: 11, color: AppColors.secondary),
                      const SizedBox(width: 4),
                      Text(
                        widget.node!.path,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Theme Toggle (Dark / Light)
                IconButton(
                  tooltip: _isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                  icon: Icon(
                    _isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    size: 15,
                    color: _isDarkMode ? AppColors.secondary : Colors.amber,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
                ),
                const SizedBox(width: 2),

                // Scale Presets
                _buildScaleButton('Fit', null),
                _buildScaleButton('75%', 0.75),
                _buildScaleButton('100%', 1.0),
                const SizedBox(width: 4),

                // Screenshot / Print Button
                Tooltip(
                  message: 'Tirar Screenshot da Tela (PNG)',
                  child: InkWell(
                    key: const Key('screenshot_button'),
                    onTap: _isCapturingScreenshot ? null : () => captureScreenshot(),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isCapturingScreenshot)
                            const SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                            )
                          else
                            const Icon(Icons.camera_alt_rounded, size: 12, color: AppColors.primary),
                          const SizedBox(width: 4),
                          const Text(
                            '📸 Screenshot',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // Reset Interactive Simulation
                IconButton(
                  tooltip: 'Reset Screen Simulation',
                  icon: const Icon(Icons.refresh_rounded, size: 15, color: AppColors.textMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: _resetSimulation,
                ),

                // Fullscreen Modal Toggle (if provided)
                if (widget.onToggleExpand != null) ...[
                  IconButton(
                    tooltip: widget.isExpanded ? 'Exit Fullscreen' : 'Expand Emulator',
                    icon: Icon(
                      widget.isExpanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      size: 16,
                      color: AppColors.textPrimary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: widget.onToggleExpand,
                  ),
                ],
              ],
            ),
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
  // SCREEN CONTENT ROUTER (PURE CODE LIVE SYNC REALITY)
  // ===========================================================================

  Widget _buildScreenContent() {
    return _buildDynamicCodeRenderedScreen();
  }

  // ===========================================================================
  // DYNAMIC CODE-DRIVEN RENDERING ENGINE
  // ===========================================================================

  Widget _buildDynamicCodeRenderedScreen() {
    if (widget.sourceCode == null || widget.sourceCode!.trim().isEmpty) {
      return _buildRealRouteFallbackScreen();
    }

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
              AppToast.info(
                context,
                'Triggered ${node.label}',
                duration: const Duration(seconds: 2),
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
              AppToast.info(
                context,
                'Triggered ${node.label}',
                duration: const Duration(seconds: 2),
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
              AppToast.info(
                context,
                'Triggered ${node.label}',
                duration: const Duration(seconds: 2),
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
  // SLEEK DYNAMIC REAL ROUTE FALLBACK (WHEN NO SOURCE CODE LOADED)
  // ===========================================================================

  Widget _buildRealRouteFallbackScreen() {
    final textColor = _isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtextColor =
        _isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBg =
        _isDarkMode ? const Color(0xFF141B2D) : Colors.white;
    final borderColor =
        _isDarkMode ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0);
    final statusBarHeight = _selectedDevice.hasDynamicIsland ? 48.0 : 40.0;

    final node = widget.node;
    final title = node?.title ?? 'Route Screen';
    final path = node?.path ?? '/';
    final subtitle = node?.subtitle ?? 'Live Code Sync ready for editing';
    final icon = node?.icon ?? Icons.alt_route_rounded;

    return Container(
      color: _isDarkMode ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Dynamic Top Navigation Bar with Real Route Metadata
          Container(
            color: _isDarkMode ? const Color(0xFF111726) : Colors.white,
            padding: EdgeInsets.only(
              top: statusBarHeight,
              left: 16,
              right: 16,
              bottom: 12,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'LIVE READY',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Central Real Route Info Box
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 36),
                  // Glowing Route Icon
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryGlow.withOpacity(0.2),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(icon, size: 38, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Route Title & Path Chip
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHover,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Text(
                      path,
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subtextColor,
                      fontSize: 12,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 28),

                  // Reality Card explaining Pure Code Live Sync
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.code_rounded, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pure Reality Live Sync',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No fake archetype mock screens. The emulator renders what is actually written in Dart source code.',
                          style: TextStyle(
                            color: subtextColor,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.background.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.bolt_rounded, size: 14, color: AppColors.secondary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Write or edit widgets in the code tab to see instant live preview.',
                                  style: TextStyle(
                                    color: subtextColor,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (node?.filePath != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Target File: ',
                      style: TextStyle(
                        color: subtextColor.withOpacity(0.7),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
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
