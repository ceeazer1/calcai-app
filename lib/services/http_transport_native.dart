import 'dart:io';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:objective_c/objective_c.dart';

/// Include only the numeric native code, never request URLs or credentials.
String connectionFailureMessage(http.ClientException error) {
  final detail = error is NSErrorClientException
      ? ' (Apple network error ${error.error.code})'
      : '';
  return 'Could not reach CalcAI$detail. Check your internet connection and try again.';
}

/// Reuse this client for the service lifetime and close it on disposal.
/// Platform transports own DNS, certificate validation, and connection pooling.
/// Do not replay authentication codes or other mutations on network failures.
http.Client createResilientClient() {
  if (Platform.isIOS || Platform.isMacOS) {
    final configuration =
        URLSessionConfiguration.ephemeralSessionConfiguration()
          // Account data must not survive in a disk cache or cookie store.
          ..cache = null
          ..requestCachePolicy =
              NSURLRequestCachePolicy.NSURLRequestReloadIgnoringLocalCacheData
          ..httpShouldSetCookies = false
          ..httpCookieAcceptPolicy =
              NSHTTPCookieAcceptPolicy.NSHTTPCookieAcceptPolicyNever
          ..allowsCellularAccess = true
          ..allowsConstrainedNetworkAccess = true
          ..allowsExpensiveNetworkAccess = true
          ..timeoutIntervalForRequest = const Duration(seconds: 20)
          // Surface offline errors promptly. Service-level deadlines remain
          // responsible for the total time a user action can take.
          ..waitsForConnectivity = false;
    return CupertinoClient.fromSessionConfiguration(configuration);
  }

  return IOClient(
    HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30),
  );
}
