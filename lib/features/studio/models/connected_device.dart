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
