import 'package:flutter/material.dart';

enum NavigationStyle {
  tabs(
    title: 'Modern Tabs (Bottom Bar)',
    description: 'Bottom navigation bar with animated floating pill indicators. Ideal for mobile-first MVPs.',
    icon: Icons.tab_rounded,
  ),
  drawer(
    title: 'Navigation Drawer & Dropdown',
    description: 'Collapsible side drawer menu with clean hierarchy. Perfect for multi-feature utilities.',
    icon: Icons.menu_open_rounded,
  ),
  adaptiveRail(
    title: 'Adaptive Shell (Tabs + Rail)',
    description: 'Auto-adapts: Bottom tabs on mobile screens, elegant Navigation Rail on Desktop & Tablets.',
    icon: Icons.splitscreen_rounded,
  );

  final String title;
  final String description;
  final IconData icon;

  const NavigationStyle({
    required this.title,
    required this.description,
    required this.icon,
  });
}

enum PresetType {
  saas(
    name: 'SaaS / Indie Hacker',
    tagline: 'Riverpod + GoRouter + Supabase + Modern UI',
    icon: Icons.rocket_launch_rounded,
  ),
  cleanLite(
    name: 'Clean-Lite Scalable',
    tagline: 'BLoC + Dio + GetIt + Feature-First Folders',
    icon: Icons.layers_rounded,
  ),
  offline(
    name: 'Offline-First Utility',
    tagline: 'Drift / Isar + Provider + Dynamic Material 3',
    icon: Icons.wifi_off_rounded,
  );

  final String name;
  final String tagline;
  final IconData icon;

  const PresetType({
    required this.name,
    required this.tagline,
    required this.icon,
  });
}

enum DevicePermission {
  camera(
    name: 'Camera',
    description: 'Capturing photos, video recording, or scanning QR codes.',
    androidTag: 'android.permission.CAMERA',
    iosKey: 'NSCameraUsageDescription',
    iosDefaultReason: 'This app requires camera access to scan documents or take photos.',
    icon: Icons.camera_alt_rounded,
  ),
  location(
    name: 'Location (GPS)',
    description: 'Access precise device location in foreground.',
    androidTag: 'android.permission.ACCESS_FINE_LOCATION',
    iosKey: 'NSLocationWhenInUseUsageDescription',
    iosDefaultReason: 'This app needs access to your location to provide personalized local services.',
    icon: Icons.location_on_rounded,
  ),
  notifications(
    name: 'Push Notifications',
    description: 'Send engagement notifications and transaction alerts.',
    androidTag: 'android.permission.POST_NOTIFICATIONS',
    iosKey: 'NSPushNotificationUsageDescription',
    iosDefaultReason: 'We need permission to send you critical updates and reminders.',
    icon: Icons.notifications_active_rounded,
  ),
  photoLibrary(
    name: 'Photo Gallery',
    description: 'Select existing photos and media from the user device.',
    androidTag: 'android.permission.READ_MEDIA_IMAGES',
    iosKey: 'NSPhotoLibraryUsageDescription',
    iosDefaultReason: 'This app requires access to your photo library to upload profile pictures or media.',
    icon: Icons.photo_library_rounded,
  ),
  biometrics(
    name: 'Biometrics (Face ID / Touch ID)',
    description: 'Secure authentication using hardware fingerprint or Face ID.',
    androidTag: 'android.permission.USE_BIOMETRIC',
    iosKey: 'NSFaceIDUsageDescription',
    iosDefaultReason: 'We use Face ID / Touch ID to securely authenticate you without typing a password.',
    icon: Icons.fingerprint_rounded,
  );

  final String name;
  final String description;
  final String androidTag;
  final String iosKey;
  final String iosDefaultReason;
  final IconData icon;

  const DevicePermission({
    required this.name,
    required this.description,
    required this.androidTag,
    required this.iosKey,
    required this.iosDefaultReason,
    required this.icon,
  });
}

class ProjectConfig {
  final String projectName;
  final String orgId;
  final String outputPath;
  final PresetType preset;
  final NavigationStyle navigationStyle;
  final Set<DevicePermission> permissions;
  final Color seedColor;
  final bool enableDarkTheme;
  final int androidMinSdk;
  final bool enableMultiDex;
  final String iosTarget;
  final Set<String> targetPlatforms;

  const ProjectConfig({
    this.projectName = 'my_awesome_app',
    this.orgId = 'com.example',
    this.outputPath = '',
    this.preset = PresetType.saas,
    this.navigationStyle = NavigationStyle.tabs,
    this.permissions = const {DevicePermission.notifications},
    this.seedColor = const Color(0xFF6366F1),
    this.enableDarkTheme = true,
    this.androidMinSdk = 24,
    this.enableMultiDex = true,
    this.iosTarget = '15.0',
    this.targetPlatforms = const {'android', 'ios', 'web'},
  });

  ProjectConfig copyWith({
    String? projectName,
    String? orgId,
    String? outputPath,
    PresetType? preset,
    NavigationStyle? navigationStyle,
    Set<DevicePermission>? permissions,
    Color? seedColor,
    bool? enableDarkTheme,
    int? androidMinSdk,
    bool? enableMultiDex,
    String? iosTarget,
    Set<String>? targetPlatforms,
  }) {
    return ProjectConfig(
      projectName: projectName ?? this.projectName,
      orgId: orgId ?? this.orgId,
      outputPath: outputPath ?? this.outputPath,
      preset: preset ?? this.preset,
      navigationStyle: navigationStyle ?? this.navigationStyle,
      permissions: permissions ?? this.permissions,
      seedColor: seedColor ?? this.seedColor,
      enableDarkTheme: enableDarkTheme ?? this.enableDarkTheme,
      androidMinSdk: androidMinSdk ?? this.androidMinSdk,
      enableMultiDex: enableMultiDex ?? this.enableMultiDex,
      iosTarget: iosTarget ?? this.iosTarget,
      targetPlatforms: targetPlatforms ?? this.targetPlatforms,
    );
  }
}
