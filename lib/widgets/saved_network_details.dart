import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import 'phone_hotspot_option.dart';

class SavedNetworkDetails extends StatefulWidget {
  const SavedNetworkDetails({
    super.key,
    required this.ble,
    required this.ssid,
    required this.onConnect,
  });
  final BleService ble;
  final String ssid;
  final void Function(String password, bool hotspot) onConnect;

  @override
  State<SavedNetworkDetails> createState() => _SavedNetworkDetailsState();
}

class _SavedNetworkDetailsState extends State<SavedNetworkDetails> {
  final _password = TextEditingController();
  bool _editingPassword = false;
  bool _updating = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      const Divider(height: 1, color: AppColors.glassBorder),
      const SizedBox(height: 8),
      PhoneHotspotOption(
        value: widget.ble.isIphoneHotspotNetwork(widget.ssid),
        onChanged: _updating
            ? null
            : (value) async {
                setState(() {
                  _updating = true;
                  _error = null;
                });
                final success = await widget.ble.setIphoneHotspotKeepAlive(
                  widget.ssid,
                  value,
                );
                if (!mounted) return;
                setState(() {
                  _updating = false;
                  if (!success) {
                    _error =
                        widget.ble.error ?? 'Could not update hotspot setting.';
                  }
                });
              },
      ),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: AppColors.error)),
      if (!_editingPassword)
        Align(
          alignment: Alignment.centerLeft,
          heightFactor: 1,
          child: TextButton(
            onPressed: _updating
                ? null
                : () => setState(() => _editingPassword = true),
            child: const Text('Update password'),
          ),
        )
      else ...[
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Wi-Fi password',
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _updating
              ? null
              : () {
                  FocusScope.of(context).unfocus();
                  widget.onConnect(
                    _password.text,
                    widget.ble.isIphoneHotspotNetwork(widget.ssid),
                  );
                },
          child: const Text('Connect'),
        ),
      ],
    ],
  );
}
