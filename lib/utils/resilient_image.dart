import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../services/resilient_http_client.dart';
import 'private_photo.dart';

export 'private_photo.dart' show privateImageHeaders;

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
  const ResilientNetworkImage(
    this.url, {
    this.scale = 1.0,
    this.token,
    this.client,
  });

  final String url;
  final double scale;
  final String? token;
  final http.Client? client;

  /// One client for every image; each request opens its own socket.
  static final http.Client _client = createResilientClient(
    maxResponseBytes: maxPrivatePhotoBytes,
  );

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
      final bytes = await downloadPrivatePhoto(
        key.client ?? _client,
        key.url,
        key.token,
      );
      // Await asynchronous validation so failures reach cache eviction below.
      return await decodePrivatePhoto(bytes, decoder: (buffer) => decode(buffer));
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
      identical(other.client, client) &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale, token, identityHashCode(client));

  @override
  String toString() => 'ResilientNetworkImage(private photo, scale: $scale)';
}
