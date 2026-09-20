import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class PhoneHotspotOption extends StatelessWidget {
  const PhoneHotspotOption({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    value: value,
    activeTrackColor: AppColors.textSecondary,
    title: Text(
      'Phone hotspot',
      style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
    ),
    subtitle: Align(
      heightFactor: 1,
      widthFactor: 1,
      alignment: Alignment.centerLeft,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: AppColors.textSecondary,
          textStyle: GoogleFonts.inter(fontSize: 12),
        ),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Phone hotspot'),
            content: const Text(
              'Turn this on when this network is your phone’s hotspot. '
              'CalcAI sends occasional small requests to help keep the hotspot '
              'connected while your phone is locked. This uses some data and '
              'battery. Turn on Personal Hotspot on your phone first.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
        child: const Text('Learn more'),
      ),
    ),
    onChanged: onChanged,
  );
}
