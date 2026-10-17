import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';

/// Shared Home/Settings wording, based only on confirmed key metadata.
class ProviderFundingLabel extends StatelessWidget {
  const ProviderFundingLabel({
    super.key,
    required this.cloud,
    required this.provider,
    this.onRetry,
    this.currentModel = false,
  });
  final CloudService cloud;
  final String provider;
  final VoidCallback? onRetry;
  final bool currentModel;

  @override
  Widget build(BuildContext context) {
    final detail = cloud.providerFundingDetail(
      provider,
      currentModel: currentModel,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cloud.providerFundingLabel(provider, currentModel: currentModel),
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 3),
          Text(
            detail,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
        if ((cloud.apiKeysError != null ||
                (currentModel &&
                    cloud.currentModelFunding == null &&
                    !cloud.modelSettingsLoading)) &&
            onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
