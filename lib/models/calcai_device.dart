import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Represents a discovered CalcAI BLE device.
class CalcAiDevice {
  /// Creates a [CalcAiDevice].
  CalcAiDevice({
    required this.device,
    required this.rssi,
    this.advertisementName,
  });

  /// The underlying flutter_blue_plus device handle.
  final BluetoothDevice device;

  /// Last-known signal strength.
  int rssi;

  /// Name from advertisement data (may differ from device.platformName).
  final String? advertisementName;

  /// Resolved display name, preferring advertisement data.
  String get name =>
      advertisementName?.isNotEmpty == true
          ? advertisementName!
          : device.platformName.isNotEmpty
              ? device.platformName
              : 'CalcAI Device';

  /// Unique device identifier.
  String get id => device.remoteId.str;

  /// Returns 0–4 signal level from RSSI.
  int get signalLevel {
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    if (rssi >= -80) return 1;
    return 0;
  }

  /// Returns the icon for signal level.
  IconData get signalIcon {
    switch (signalLevel) {
      case 4:
        return Icons.signal_cellular_4_bar;
      case 3:
        return Icons.signal_cellular_alt;
      case 2:
        return Icons.signal_cellular_alt_2_bar;
      case 1:
        return Icons.signal_cellular_alt_1_bar;
      default:
        return Icons.signal_cellular_0_bar;
    }
  }

  /// Signal color matching the quality level.
  Color get signalColor => AppColors.signalColor(rssi);

  /// Human-readable signal label.
  String get signalLabel {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Good';
    if (rssi >= -70) return 'Fair';
    if (rssi >= -80) return 'Weak';
    return 'Very Weak';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalcAiDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CalcAiDevice(name: $name, rssi: $rssi)';
}

/// Connection state of the CalcAI device.
enum DeviceConnectionState {
  disconnected,
  connecting,
  connected,
  discovering,
  ready,
  error;

  /// Whether the device has an active BLE connection.
  bool get isConnected =>
      this == connected || this == discovering || this == ready;

  /// Human-readable label.
  String get label {
    switch (this) {
      case DeviceConnectionState.disconnected:
        return 'Disconnected';
      case DeviceConnectionState.connecting:
        return 'Connecting…';
      case DeviceConnectionState.connected:
        return 'Connected';
      case DeviceConnectionState.discovering:
        return 'Discovering Services…';
      case DeviceConnectionState.ready:
        return 'Ready';
      case DeviceConnectionState.error:
        return 'Error';
    }
  }

  /// Status dot color.
  Color get color {
    switch (this) {
      case DeviceConnectionState.disconnected:
        return AppColors.textTertiary;
      case DeviceConnectionState.connecting:
      case DeviceConnectionState.discovering:
        return AppColors.warning;
      case DeviceConnectionState.connected:
      case DeviceConnectionState.ready:
        return AppColors.success;
      case DeviceConnectionState.error:
        return AppColors.error;
    }
  }
}

/// WiFi provisioning state.
enum ProvisioningState {
  idle,
  scanning,
  sendingCredentials,
  waitingForConnection,
  success,
  failed;

  /// Human-readable label.
  String get label {
    switch (this) {
      case ProvisioningState.idle:
        return 'Idle';
      case ProvisioningState.scanning:
        return 'Scanning Networks…';
      case ProvisioningState.sendingCredentials:
        return 'Sending Credentials…';
      case ProvisioningState.waitingForConnection:
        return 'Connecting to WiFi…';
      case ProvisioningState.success:
        return 'Connected!';
      case ProvisioningState.failed:
        return 'Failed';
    }
  }
}
