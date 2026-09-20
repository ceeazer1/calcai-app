import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Hosts with an optional DNS-over-HTTPS fallback. Native hostname resolution
/// runs first so IPv6 and network-specific DNS64/NAT64 synthesis can work.
const Set<String> _dohHosts = {'ai.calcai.cc'};

/// DoH JSON endpoints, addressed **by IP** so no bootstrap DNS is needed. We
/// query several in parallel so resolution still succeeds when a network blocks
/// one provider. Cloudflare serves the JSON API at /dns-query; Google at
/// /resolve.
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

Future<String?> _firstNonNull(List<Future<String?>> futures) {
  final c = Completer<String?>();
  var remaining = futures.length;
  if (remaining == 0) return Future.value(null);
  for (final f in futures) {
    f
        .then((v) {
          remaining--;
          if (v != null && v.isNotEmpty) {
            if (!c.isCompleted) c.complete(v);
          } else if (remaining == 0 && !c.isCompleted) {
            c.complete(null);
          }
        })
        .catchError((_) {
          remaining--;
          if (remaining == 0 && !c.isCompleted) c.complete(null);
        });
  }
  return c.future;
}

/// Resolves [host] via DoH (multiple providers, in parallel). Returns null on
/// failure so the caller can fall back to the OS resolver.
Future<String?> _resolveViaDoh(String host) async {
  final cached = _dohCache[host];
  if (cached != null && cached.expiry.isAfter(DateTime.now())) return cached.ip;
  final ip = await _firstNonNull(
    _dohEndpoints.map((e) => _queryDoh(e, host)).toList(),
  );
  if (ip != null) {
    _dohCache[host] = _DohEntry(
      ip,
      DateTime.now().add(const Duration(minutes: 5)),
    );
  }
  return ip;
}

/// Connects by hostname first, preserving IPv6 support. If connecting fails,
/// tries DoH with the original hostname for certificate verification and SNI.
/// Only connection establishment is retried; requests are never replayed.
http.Client createResilientClient() {
  // dart:io (HttpClient / Socket / IOClient) doesn't exist on web — touching it
  // throws `Unsupported operation: Platform._version` and takes down every
  // screen that reads CloudService. Browsers also do their own DNS (often
  // already DoH), so the custom resolver isn't needed there anyway.
  if (kIsWeb) return http.Client();
  return _ResilientClient();
}

class _ResilientClient extends http.BaseClient {
  late final http.Client _client;

  _ResilientClient() {
    final native = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30);
    native.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null || !_dohHosts.contains(uri.host)) {
        return Socket.startConnect(
          proxyHost ?? uri.host,
          proxyPort ?? uri.port,
        );
      }
      var cancelled = false;
      Socket? connected;
      Future<Socket> connect() async {
        Socket socket;
        try {
          socket = await Socket.connect(
            uri.host,
            uri.port,
            timeout: const Duration(seconds: 5),
          );
        } catch (_) {
          if (cancelled) rethrow;
          final ip = await _resolveViaDoh(uri.host);
          if (ip == null || cancelled) rethrow;
          socket = await Socket.connect(
            ip,
            uri.port,
            timeout: const Duration(seconds: 5),
          );
        }
        connected = socket;
        if (cancelled) {
          socket.destroy();
          throw const SocketException('Connection cancelled');
        }
        return socket;
      }

      // HttpClient owns HTTP framing, connection reuse and TLS verification
      // against the original URI hostname, including after a DNS fallback.
      return ConnectionTask.fromSocket(connect(), () {
        cancelled = true;
        connected?.destroy();
      });
    };
    _client = IOClient(native);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _client.send(request);

  @override
  void close() {
    _client.close();
    super.close();
  }
}
