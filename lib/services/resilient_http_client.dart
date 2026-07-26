import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Hostnames we resolve via DNS-over-HTTPS and connect to over a manually
/// TLS-wrapped socket. Everything else uses the normal client.
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

/// Resolves [host] via DoH (multiple providers, in parallel). Returns null on
/// failure so the caller can fall back to the OS resolver.
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

/// An [http.Client] that, for our API host, resolves the IP via DoH and talks
/// to it over a socket TLS-wrapped with the real hostname as SNI. This is
/// immune to routers/ISPs that hijack or block the domain at the DNS layer
/// (Dart's HttpClient can't do DoH + custom SNI, so we do the request by hand).
http.Client createResilientClient() => _ResilientClient();

class _ResilientClient extends http.BaseClient {
  final http.Client _fallback = IOClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final uri = request.url;
    if (uri.scheme == 'https' && _dohHosts.contains(uri.host)) {
      return _sendSecure(request);
    }
    return _fallback.send(request);
  }

  @override
  void close() {
    _fallback.close();
    super.close();
  }

  Future<http.StreamedResponse> _sendSecure(http.BaseRequest request) async {
    final uri = request.url;
    final host = uri.host;
    final port = uri.hasPort ? uri.port : 443;
    final ip = await _resolveViaDoh(host) ?? host;

    final raw = await Socket.connect(ip, port,
        timeout: const Duration(seconds: 12));
    SecureSocket tls;
    try {
      tls = await SecureSocket.secure(raw, host: host)
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      raw.destroy();
      rethrow;
    }

    final bodyBytes = await request.finalize().toBytes();

    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    final head = StringBuffer()
      ..write('${request.method} $path$query HTTP/1.1\r\n')
      ..write('Host: $host\r\n');
    request.headers.forEach((k, v) {
      final lk = k.toLowerCase();
      // We manage these ourselves.
      if (lk == 'host' ||
          lk == 'content-length' ||
          lk == 'connection' ||
          lk == 'accept-encoding') {
        return;
      }
      head.write('$k: $v\r\n');
    });
    head
      ..write('Accept-Encoding: identity\r\n')
      ..write('Content-Length: ${bodyBytes.length}\r\n')
      ..write('Connection: close\r\n\r\n');

    tls.add(utf8.encode(head.toString()));
    if (bodyBytes.isNotEmpty) tls.add(bodyBytes);
    await tls.flush();

    // Connection: close → read until EOF, then parse.
    final resBytes =
        await _readAll(tls).timeout(const Duration(seconds: 35));
    tls.destroy();

    return _parse(resBytes, request);
  }

  static Future<Uint8List> _readAll(Stream<List<int>> s) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in s) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  static int _indexOfCrlfCrlf(Uint8List b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  http.StreamedResponse _parse(Uint8List bytes, http.BaseRequest request) {
    final sep = _indexOfCrlfCrlf(bytes);
    if (sep < 0) {
      throw const HttpException('Malformed HTTP response');
    }
    final headText = latin1.decode(bytes.sublist(0, sep));
    var body = bytes.sublist(sep + 4);

    final lines = headText.split('\r\n');
    final statusLine = lines.isNotEmpty ? lines.first : 'HTTP/1.1 502';
    final parts = statusLine.split(' ');
    final statusCode =
        parts.length >= 2 ? (int.tryParse(parts[1]) ?? 502) : 502;
    final reason = parts.length >= 3 ? parts.sublist(2).join(' ') : null;

    final headers = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim().toLowerCase();
      final val = line.substring(idx + 1).trim();
      headers[key] = headers.containsKey(key) ? '${headers[key]}, $val' : val;
    }

    if ((headers['transfer-encoding'] ?? '').toLowerCase().contains('chunked')) {
      body = _dechunk(body);
    }
    if ((headers['content-encoding'] ?? '').toLowerCase().contains('gzip')) {
      body = Uint8List.fromList(gzip.decode(body));
      headers.remove('content-encoding');
    }
    // Length now reflects the decoded body.
    headers['content-length'] = body.length.toString();

    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      statusCode,
      contentLength: body.length,
      request: request,
      headers: headers,
      reasonPhrase: reason,
    );
  }

  static Uint8List _dechunk(Uint8List data) {
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < data.length) {
      // Read the chunk-size line.
      var j = i;
      while (j + 1 < data.length && !(data[j] == 13 && data[j + 1] == 10)) {
        j++;
      }
      if (j + 1 >= data.length) break;
      final sizeLine = latin1.decode(data.sublist(i, j)).split(';').first.trim();
      final size = int.tryParse(sizeLine, radix: 16) ?? 0;
      i = j + 2; // skip CRLF
      if (size == 0) break;
      if (i + size > data.length) break;
      out.add(data.sublist(i, i + size));
      i += size;
      if (i + 1 < data.length && data[i] == 13 && data[i + 1] == 10) {
        i += 2; // trailing CRLF after chunk
      }
    }
    return out.takeBytes();
  }
}
