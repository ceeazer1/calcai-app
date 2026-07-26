import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Hostnames we resolve via DNS-over-HTTPS. Everything else connects normally.
const Set<String> _dohHosts = {'ai.calcai.cc'};

/// DoH JSON endpoints, addressed **by IP** so no bootstrap DNS is needed. We
/// query several in parallel so the app still resolves when a network blocks
/// one provider (e.g. routers that force their own DNS often block 1.1.1.1 but
/// miss Google's, or block port 53 but not DoH on 443). Cloudflare serves the
/// JSON API at /dns-query; Google serves it at /resolve.
const List<String> _dohEndpoints = [
  'https://1.1.1.1/dns-query',
  'https://1.0.0.1/dns-query',
  'https://8.8.8.8/resolve',
  'https://8.8.4.4/resolve',
];

class _DohEntry {
  final String ip;
  final DateTime expiry;
  _DohEntry(this.ip, this.expiry);
}

final Map<String, _DohEntry> _dohCache = {};

/// One DoH query. Returns the first A-record IP, or null on any failure.
Future<String?> _queryDoh(String endpoint, String host) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  try {
    final req = await client.getUrl(Uri.parse('$endpoint?name=$host&type=A'));
    req.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
    final resp = await req.close().timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) return null;
    final body = await resp.transform(utf8.decoder).join();
    final data = jsonDecode(body);
    final answers = (data is Map ? data['Answer'] as List? : null) ?? const [];
    for (final a in answers) {
      if (a is Map && a['type'] == 1) {
        final ip = a['data']?.toString();
        if (ip != null && ip.isNotEmpty) return ip;
      }
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Completes with the first non-null result, or null once all have finished.
Future<String?> _firstNonNull(List<Future<String?>> futures) {
  final c = Completer<String?>();
  var remaining = futures.length;
  if (remaining == 0) return Future.value(null);
  for (final f in futures) {
    f.then((v) {
      remaining--;
      if (v != null && v.isNotEmpty) {
        if (!c.isCompleted) c.complete(v);
      } else if (remaining == 0 && !c.isCompleted) {
        c.complete(null);
      }
    }).catchError((_) {
      remaining--;
      if (remaining == 0 && !c.isCompleted) c.complete(null);
    });
  }
  return c.future;
}

/// Resolves [host] via DNS-over-HTTPS (multiple providers, in parallel), so it
/// works even when the local router's DNS is blocking the domain. Returns null
/// on failure so callers fall back to the OS resolver.
Future<String?> _resolveViaDoh(String host) async {
  final cached = _dohCache[host];
  if (cached != null && cached.expiry.isAfter(DateTime.now())) return cached.ip;

  final ip = await _firstNonNull(
    _dohEndpoints.map((e) => _queryDoh(e, host)).toList(),
  );
  if (ip != null) {
    _dohCache[host] =
        _DohEntry(ip, DateTime.now().add(const Duration(minutes: 5)));
  }
  return ip;
}

/// An [http.Client] that resolves our API host via DoH and connects to the
/// resulting IP, while TLS SNI and certificate validation still use the real
/// hostname. Makes the app immune to home routers that block the domain at the
/// DNS layer (matching how browsers bypass it with encrypted DNS).
http.Client createResilientClient() {
  final inner = HttpClient();
  inner.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) {
    final defaultPort = uri.scheme == 'https' ? 443 : 80;
    // Honor any configured proxy untouched.
    if (proxyHost != null) {
      return Socket.startConnect(proxyHost, proxyPort ?? defaultPort);
    }
    final port = uri.hasPort ? uri.port : defaultPort;
    if (_dohHosts.contains(uri.host)) {
      return _resolveViaDoh(uri.host).then((ip) {
        // Fall back to the OS resolver (uri.host) if DoH couldn't resolve.
        return Socket.startConnect(ip ?? uri.host, port);
      });
    }
    return Socket.startConnect(uri.host, port);
  };
  return IOClient(inner);
}
