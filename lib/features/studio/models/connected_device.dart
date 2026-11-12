import 'package:flutter/foundation.dart';

/// Lifecycle states of a live Android device debug/run session.
enum DeviceRunStatus {
  idle,
  scanning,
  launching,
  running,
  reloading,
  error,
}

/// High-level root cause classification when no ready Android device is detected.
enum AndroidConnectionIssueType {
  none,
  unauthorized,
  offline,
  adbReadyFlutterBlocked,
  usbInterfaceWithoutSdk,
  unconfiguredSdkFound,
  usbPhoneWithoutAdbInterface,
  driverOrUsbModeSuspected,
  missingAndroidSdk,
  noDeviceConnected,
  scanError,
}

/// Verification state of a single prerequisite during Android connection testing.
enum DiagnosticCheckStatus {
  ok,
  warning,
  error,
}

/// Represents a single environment or hardware check step shown to the user.
@immutable
class AndroidEnvironmentCheck {
  final String label;
  final DiagnosticCheckStatus status;
  final String detail;

  const AndroidEnvironmentCheck({
    required this.label,
    required this.status,
    required this.detail,
  });
}

/// Parsed entry from `adb devices -l`.
@immutable
class AdbDeviceEntry {
  final String serial;
  final String state;
  final String? model;
  final String rawLine;

  const AdbDeviceEntry({
    required this.serial,
    required this.state,
    this.model,
    required this.rawLine,
  });

  bool get isReady => state == 'device';
  bool get isUnauthorized => state == 'unauthorized' || state == 'authorizing';
  bool get isOffline => state == 'offline';

  String get displayName =>
      (model != null && model!.isNotEmpty) ? '$model ($serial)' : serial;
}

/// Parsed USB PnP device snapshot returned by Windows CIM/WMI query.
@immutable
class WindowsUsbDeviceInfo {
  final String name;
  final String status;
  final int errorCode;
  final String service;
  final String deviceId;
  final List<String> compatibleIds;

  const WindowsUsbDeviceInfo({
    required this.name,
    required this.status,
    required this.errorCode,
    required this.service,
    required this.deviceId,
    this.compatibleIds = const [],
  });

  bool get isHealthy => status.toUpperCase() == 'OK' && errorCode == 0;

  bool get isAdbInterface {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('adb interface') || lowerName.contains('android adb')) {
      return true;
    }
    return compatibleIds.any(
      (id) => id.toLowerCase().contains('class_ff&subclass_42&prot_01'),
    );
  }

  /// Extracts `VID_xxxx&PID_xxxx` to correlate sibling USB interfaces (MTP + ADB).
  String? get vidPidKey {
    final match = RegExp(
      r'VID_[0-9A-F]{4}&PID_[0-9A-F]{4}',
      caseSensitive: false,
    ).firstMatch(deviceId);
    return match?.group(0)?.toUpperCase();
  }

  bool get isPhoneLike {
    if (service.toUpperCase() == 'WUDFWPDMTP') return true;
    final lower = name.toLowerCase();
    return lower.contains('samsung') ||
        lower.contains('galaxy') ||
        lower.contains('s25') ||
        lower.contains('s24') ||
        lower.contains('s23') ||
        lower.contains('pixel') ||
        lower.contains('android') ||
        lower.contains('motorola') ||
        lower.contains('xiaomi') ||
        lower.contains('redmi') ||
        lower.contains('poco') ||
        lower.contains('oneplus') ||
        lower.contains('realme') ||
        lower.contains('sm-');
  }
}

/// Structured live diagnosis and actionable remediation guide for Android USB connection issues.
@immutable
class AndroidConnectionDiagnostic {
  final List<ConnectedAndroidDevice> devices;
  final AndroidConnectionIssueType issueType;
  final String title;
  final String summary;
  final List<String> steps;
  final List<AndroidEnvironmentCheck> checks;
  final String? detectedUsbDeviceName;
  final String? discoveredSdkPath;
  final String? adbPath;
  final bool hasJava;
  final String? suggestedCommand;
  final String? actionUrl;
  final String? actionUrlLabel;

  const AndroidConnectionDiagnostic({
    this.devices = const [],
    this.issueType = AndroidConnectionIssueType.none,
    required this.title,
    required this.summary,
    this.steps = const [],
    this.checks = const [],
    this.detectedUsbDeviceName,
    this.discoveredSdkPath,
    this.adbPath,
    this.hasJava = false,
    this.suggestedCommand,
    this.actionUrl,
    this.actionUrlLabel,
  });

  bool get hasDevices => devices.isNotEmpty;

  bool get hasActionableIssue =>
      devices.isEmpty && issueType != AndroidConnectionIssueType.none;

  bool get needsToolchainSetup =>
      issueType == AndroidConnectionIssueType.usbInterfaceWithoutSdk ||
      issueType == AndroidConnectionIssueType.missingAndroidSdk ||
      issueType == AndroidConnectionIssueType.unconfiguredSdkFound ||
      issueType == AndroidConnectionIssueType.adbReadyFlutterBlocked;
}

/// Represents a physical or emulated Android device reported by Flutter CLI.
@immutable
class ConnectedAndroidDevice {
  final String id;
  final String name;
  final String targetPlatform;
  final String sdk;
  final bool isEmulator;

  const ConnectedAndroidDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    this.sdk = 'Android',
    this.isEmulator = false,
  });

  /// Constructs a [ConnectedAndroidDevice] from an entry of `flutter devices --machine`.
  factory ConnectedAndroidDevice.fromFlutterJson(Map<String, dynamic> json) {
    return ConnectedAndroidDevice(
      id: (json['id'] ?? '').toString().trim(),
      name: (json['name'] ?? 'Android Device').toString().trim(),
      targetPlatform: (json['targetPlatform'] ?? 'android').toString().trim(),
      sdk: (json['sdk'] ?? 'Android').toString().trim(),
      isEmulator: json['emulator'] == true,
    );
  }

  String get displayLabel => isEmulator ? '$name (Emulador)' : name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectedAndroidDevice &&
        other.id == id &&
        other.name == name &&
        other.targetPlatform == targetPlatform &&
        other.sdk == sdk &&
        other.isEmulator == isEmulator;
  }

  @override
  int get hashCode => Object.hash(id, name, targetPlatform, sdk, isEmulator);

  @override
  String toString() =>
      'ConnectedAndroidDevice(id: $id, name: $name, platform: $targetPlatform, emulator: $isEmulator)';
}

/// A single structured console entry captured from a live Android debug session.
@immutable
class DeviceLogEntry {
  final DateTime timestamp;
  final String message;
  final bool isError;
  final bool isSystem;

  const DeviceLogEntry({
    required this.timestamp,
    required this.message,
    this.isError = false,
    this.isSystem = false,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
