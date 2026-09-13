import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const privacyPolicyUrl = 'https://calcai.cc/privacy';
const termsOfServiceUrl = 'https://calcai.cc/terms';

Future<void> openPublicLink(BuildContext context, String url) async {
  try {
    if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (_) {
    // Keep a failed browser launch from becoming an unhandled UI exception.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open $url. Please try again.')),
    );
  }
}
