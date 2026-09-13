import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show ImmutableBuffer;
import 'package:http/http.dart' as http;

import '../services/resilient_http_client.dart';

Map<String, String> privateImageHeaders(String url, String? token) {
  final uri = Uri.tryParse(url);
  if (token == null ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'ai.calcai.cc' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      !uri.path.startsWith('/ai/image/view/')) {
    return const {};
  }
  return {'Authorization': 'Bearer $token'};
}

/// An [ImageProvider] that loads over the app's DoH-resolving client.
///
/// `Image.network` goes through Flutter's own HttpClient, which uses the OS
/// resolver — the exact resolver `createResilientClient()` exists to work
/// around. On a network that blocks or hijacks `ai.calcai.cc`, that split meant
/// history text loaded (CloudService uses the resilient client) while every
/// photo failed, and retrying never helped because the retry used the same
/// blocked resolver.
///
/// Plugging into ImageProvider rather than fetching bytes by hand keeps
/// Flutter's image cache, so a thumbnail already on screen is not re-fetched
/// when it is opened full screen.
@immutable
class ResilientNetworkImage extends ImageProvider<ResilientNetworkImage> {
  const ResilientNetworkImage(this.url, {this.scale = 1.0, this.token});

  final String url;
  final double scale;
  final String? token;

  /// One client for every image; each request opens its own socket.
  static final http.Client _client = createResilientClient();

  @override
  Future<ResilientNetworkImage> obtainKey(ImageConfiguration _) =>
      SynchronousFuture<ResilientNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
    ResilientNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: key.scale,
      debugLabel: 'Private CalcAI photo',
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
      ],
    );
  }

  Future<ui.Codec> _load(
    ResilientNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final resp = await _client
          .get(
            Uri.parse(key.url),
            headers: privateImageHeaders(key.url, key.token),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw NetworkImageLoadException(
          statusCode: resp.statusCode,
          uri: Uri.parse(key.url).replace(query: ''),
        );
      }
      if (resp.bodyBytes.isEmpty) {
        throw Exception('Empty photo response');
      }
      return decode(await ImmutableBuffer.fromUint8List(resp.bodyBytes));
    } catch (_) {
      // Drop the failed entry so a later retry actually re-requests instead of
      // replaying the cached error.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ResilientNetworkImage &&
      other.url == url &&
      other.token == token &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale, token);

  @override
  String toString() => 'ResilientNetworkImage(private photo, scale: $scale)';
}
