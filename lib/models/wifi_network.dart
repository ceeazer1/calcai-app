import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Represents a WiFi network discovered by the ESP32.
class WifiNetwork {
  /// Creates a [WifiNetwork].
  const WifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.isSecured,
    this.authMode = WifiAuthMode.wpa2,
  });

  /// The human-readable network name.
  final String ssid;

  /// Received signal strength indicator in dBm (negative value).
  final int rssi;

  /// Whether the network requires a password.
  final bool isSecured;

  /// The authentication mode of the network.
  final WifiAuthMode authMode;

  /// Returns a 0–4 signal quality level.
  int get signalLevel {
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    if (rssi >= -80) return 1;
    return 0;
  }

  /// Returns the appropriate signal icon.
  IconData get signalIcon {
    switch (signalLevel) {
      case 4:
        return Icons.signal_wifi_4_bar;
      case 3:
        return Icons.network_wifi_3_bar;
      case 2:
        return Icons.network_wifi_2_bar;
      case 1:
        return Icons.network_wifi_1_bar;
      default:
        return Icons.signal_wifi_0_bar;
    }
  }

  /// Returns a color representing signal quality.
  Color get signalColor => AppColors.signalColor(rssi);

  /// Descriptive signal quality label.
  String get signalLabel {
    switch (signalLevel) {
      case 4:
        return 'Excellent';
      case 3:
        return 'Good';
      case 2:
        return 'Fair';
      case 1:
        return 'Weak';
      default:
        return 'Very Weak';
    }
  }

  /// Creates a [WifiNetwork] from a JSON map (received over BLE).
  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    return WifiNetwork(
      ssid: json['ssid'] as String? ?? '',
      rssi: json['rssi'] as int? ?? -100,
      isSecured: json['secured'] as bool? ?? true,
      authMode: WifiAuthMode.fromInt(json['auth'] as int? ?? 3),
    );
  }

  /// Serialises the network to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'ssid': ssid,
        'rssi': rssi,
        'secured': isSecured,
        'auth': authMode.index,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WifiNetwork &&
          runtimeType == other.runtimeType &&
          ssid == other.ssid;

  @override
  int get hashCode => ssid.hashCode;

  @override
  String toString() =>
      'WifiNetwork(ssid: $ssid, rssi: $rssi, secured: $isSecured)';
}

/// WiFi authentication mode reported by the ESP32.
enum WifiAuthMode {
  open,
  wep,
  wpaPsk,
  wpa2,
  wpaWpa2,
  wpa3,
  unknown;

  /// Converts an integer auth mode from the ESP32 to an enum value.
  static WifiAuthMode fromInt(int value) {
    switch (value) {
      case 0:
        return WifiAuthMode.open;
      case 1:
        return WifiAuthMode.wep;
      case 2:
        return WifiAuthMode.wpaPsk;
      case 3:
        return WifiAuthMode.wpa2;
      case 4:
        return WifiAuthMode.wpaWpa2;
      case 5:
        return WifiAuthMode.wpa3;
      default:
        return WifiAuthMode.unknown;
    }
  }

  /// Human-readable label.
  String get label {
    switch (this) {
      case WifiAuthMode.open:
        return 'Open';
      case WifiAuthMode.wep:
        return 'WEP';
      case WifiAuthMode.wpaPsk:
        return 'WPA';
      case WifiAuthMode.wpa2:
        return 'WPA2';
      case WifiAuthMode.wpaWpa2:
        return 'WPA/WPA2';
      case WifiAuthMode.wpa3:
        return 'WPA3';
      case WifiAuthMode.unknown:
        return 'Unknown';
    }
  }
}
