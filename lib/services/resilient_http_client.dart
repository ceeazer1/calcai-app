import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Hostnames we resolve via DNS-over-HTTPS. Everything else connects normally.
const Set<String> _dohHosts = {'ai.calcai.cc'};

class _DohEntry {
  final String ip;
  final DateTime expiry;
  _DohEntry(this.ip, this.expiry);
}

final Map<String, _DohEntry> _dohCache = {};

/// Resolves [host] via DNS-over-HTTPS, querying Cloudflare/Google **by IP** so
/// it works even when the local router's DNS is blocking the domain (common
/// with "advanced security" / ad-blocking routers and newly-registered
/// domains). Returns `null` on failure so callers fall back to the OS resolver.
Future<String?> _resolveViaDoh(String host) async {
  final cached = _dohCache[host];
  if (cached != null && cached.expiry.isAfter(DateTime.now())) return cached.ip;

  Future<String?> query(String resolverIp) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      // resolverIp is a literal IP, so this needs no DNS to bootstrap. The
      // 1.1.1.1 / 8.8.8.8 TLS certs include those IPs as SANs, so normal cert
      // validation still passes.
      final req = await client.getUrl(
        Uri.parse('https://$resolverIp/dns-query?name=$host&type=A'),
      );
      req.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final resp = await req.close().timeout(const Duration(seconds: 6));
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

  final ip = await query('1.1.1.1') ?? await query('8.8.8.8');
  if (ip != null) {
    _dohCache[host] =
        _DohEntry(ip, DateTime.now().add(const Duration(minutes: 5)));
  }
  return ip;
}

/// An [http.Client] that resolves our API host via DoH and connects to the
/// resulting IP, while TLS SNI and certificate validation still use the real
/// hostname. This makes the app immune to home routers that block the domain
/// at the DNS layer (matching how browsers bypass it with encrypted DNS).
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
