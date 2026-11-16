import 'package:http/http.dart' as http;

import 'deferred_close_client.dart';

/// The browser owns DNS, TLS, proxy settings, and connection reuse.
http.Client createResilientClient({int? maxResponseBytes}) =>
    maxResponseBytes == null
    ? http.Client()
    : DeferredCloseClient(http.Client(), maxResponseBytes: maxResponseBytes);

String connectionFailureMessage(http.ClientException error) =>
    'Could not reach CalcAI. Check your internet connection and try again.';
