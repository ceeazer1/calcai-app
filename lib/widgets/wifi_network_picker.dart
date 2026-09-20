import 'package:flutter/material.dart';
import '../models/wifi_network.dart';
import '../theme/app_colors.dart';
import 'phone_hotspot_option.dart';
import 'wifi_network_tile.dart';

/// Uses the same selected network tile and inline fields as initial setup.
class WifiNetworkPicker extends StatefulWidget {
  const WifiNetworkPicker({
    super.key,
    required this.networks,
    required this.onConnect,
  });
  final List<WifiNetwork> networks;
  final void Function(WifiNetwork, String, bool) onConnect;

  @override
  State<WifiNetworkPicker> createState() => _WifiNetworkPickerState();
}

class _WifiNetworkPickerState extends State<WifiNetworkPicker> {
  final _password = TextEditingController();
  WifiNetwork? _selected;
  bool _hotspot = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _connect() {
    final network = _selected;
    if (network == null) return;
    if (network.isSecured && _password.text.isEmpty) {
      setState(() => _error = 'Enter the network password.');
      return;
    }
    FocusScope.of(context).unfocus();
    widget.onConnect(
      network,
      network.isSecured ? _password.text : '',
      _hotspot,
    );
  }

  @override
  Widget build(BuildContext context) {
    final networks = [
      if (_selected != null) _selected!,
      ...widget.networks.where((n) => n.ssid != _selected?.ssid),
    ];
    if (networks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('No networks found. Try scanning again.'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: networks
          .map(
            (network) => WifiNetworkTile(
              key: ValueKey(network.ssid),
              network: network,
              isSelected: _selected?.ssid == network.ssid,
              onTap: () {
                FocusScope.of(context).unfocus();
                setState(() {
                  _selected = _selected?.ssid == network.ssid ? null : network;
                  _password.clear();
                  _error = null;
                  _hotspot = false;
                  _obscure = true;
                });
              },
              expandedChild: _selected?.ssid != network.ssid
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(
                            height: 1,
                            color: AppColors.glassBorder,
                          ),
                          const SizedBox(height: 18),
                          if (network.isSecured)
                            TextField(
                              controller: _password,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              onSubmitted: (_) => _connect(),
                              onChanged: (_) {
                                if (_error != null) {
                                  setState(() => _error = null);
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Wi-Fi password',
                                errorText: _error,
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                            )
                          else
                            const Text('No password needed.'),
                          const SizedBox(height: 8),
                          PhoneHotspotOption(
                            value: _hotspot,
                            onChanged: (value) =>
                                setState(() => _hotspot = value),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 46,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.textPrimary,
                                foregroundColor: AppColors.background,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _connect,
                              child: const Text('Connect'),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          )
          .toList(),
    );
  }
}
