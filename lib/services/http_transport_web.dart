import 'package:http/http.dart' as http;

/// The browser owns DNS, TLS, proxy settings, and connection reuse.
http.Client createResilientClient() => http.Client();
