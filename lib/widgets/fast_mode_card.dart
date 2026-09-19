import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

String? fastModeProvider(String model) => switch (model) {
  'gpt-5.6-sol' || 'gpt-5.6-terra' || 'gpt-5.6-luna' => 'openai',
  'claude-opus-5' || 'claude-opus-4-8' => 'anthropic',
  _ => null,
};

class FastModeCard extends StatelessWidget {
  const FastModeCard({
    super.key,
    required this.model,
    required this.enabled,
    required this.hasPersonalKey,
    required this.onChanged,
    this.saving = false,
  });
  final String model;
  final bool enabled, hasPersonalKey, saving;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final provider = fastModeProvider(model);
    final available = provider != null && hasPersonalKey;
    final active = available && enabled;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 23,
                color: active ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Fast mode',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (saving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch.adaptive(
                  value: active,
                  activeThumbColor: AppColors.textPrimary,
                  activeTrackColor: const Color(0xFF6D7180),
                  onChanged: available ? onChanged : null,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 33),
            child: Text(
              'High API Cost',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
