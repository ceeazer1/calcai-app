import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  // Load real bundled fonts before fake test clocks start. This also makes
  // missing font assets fail the suite, rather than silently fetching online.
  for (final weight in [
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
  ]) {
    GoogleFonts.inter(fontWeight: weight);
    GoogleFonts.outfit(fontWeight: weight);
    GoogleFonts.robotoMono(fontWeight: weight);
  }
  await GoogleFonts.pendingFonts();
  await testMain();
}
