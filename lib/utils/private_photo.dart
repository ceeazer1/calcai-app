import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../services/bounded_response.dart';
import 'safe_image.dart';

const maxPrivatePhotoBytes = 10 * 1024 * 1024;
const maxPrivatePhotoDimension = 8192;
const maxPrivatePhotoPixels = 16 * 1024 * 1024;

Map<String, String> privateImageHeaders(String url, String? token) =>
    token == null || safeImageUrl(url) == null
    ? const {}
    : {'Authorization': 'Bearer $token'};

class PhotoDownloadException implements Exception {
  const PhotoDownloadException(this.statusCode);
  final int statusCode;
}

/// Also bounds injected clients that do not use the native transport factory.
Future<Uint8List> downloadPrivatePhoto(
  http.Client client,
  String url,
  String? token,
) async {
  if (safeImageUrl(url) == null) {
    throw const FormatException('Unsupported photo URL');
  }
  final abort = Completer<void>();
  void cancel() {
    if (!abort.isCompleted) {
      abort.complete();
    }
  }

  final timer = Timer(const Duration(seconds: 30), cancel);
  try {
    final request =
        http.AbortableRequest('GET', Uri.parse(url), abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll(privateImageHeaders(url, token));
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final bytes = await readBoundedResponse(
      response,
      maxResponseBytes: maxPrivatePhotoBytes,
      abortTrigger: abort.future,
      onLimitExceeded: cancel,
    );
    if (response.statusCode != 200) {
      throw PhotoDownloadException(response.statusCode);
    }
    return bytes;
  } finally {
    timer.cancel();
  }
}

void _checkScope(bool Function()? isCurrent) {
  if (isCurrent != null && !isCurrent()) {
    throw const FormatException('Photo session changed');
  }
}

/// Native codecs can defer reading encoded data until getNextFrame. Retain the
/// descriptor and buffer until the caller releases the codec, as the export
/// path did before validation was shared with the preview provider.
class _RetainedPhotoCodec implements ui.Codec {
  _RetainedPhotoCodec(this._codec, this._descriptor, this._buffer);
  final ui.Codec _codec;
  final ui.ImageDescriptor _descriptor;
  final ui.ImmutableBuffer _buffer;
  bool _disposed = false;

  @override
  int get frameCount => _codec.frameCount;
  @override
  int get repetitionCount => _codec.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() => _codec.getNextFrame();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _codec.dispose();
    _descriptor.dispose();
    _buffer.dispose();
  }
}

/// Inspect encoded dimensions before allocating pixels. The returned codec is
/// owned by the caller. A framework decoder takes ownership of its buffer.
Future<ui.Codec> decodePrivatePhoto(
  Uint8List encoded, {
  Future<ui.Codec> Function(ui.ImmutableBuffer)? decoder,
  bool Function()? isCurrent,
}) async {
  const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
  const pngEnd = [0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];
  bool matches(int offset, List<int> values) =>
      offset >= 0 &&
      offset + values.length <= encoded.length &&
      List.generate(
        values.length,
        (i) => encoded[offset + i] == values[i],
      ).every((match) => match);
  final isPng =
      matches(0, pngSignature) &&
      matches(encoded.length - pngEnd.length, pngEnd);
  final isJpeg =
      matches(0, [255, 216, 255]) && matches(encoded.length - 2, [255, 217]);
  if (encoded.length > maxPrivatePhotoBytes || (!isPng && !isJpeg)) {
    throw const FormatException('Unsupported photo');
  }
  ui.ImmutableBuffer? buffer;
  ui.ImmutableBuffer? decoderBuffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    _checkScope(isCurrent);
    buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    _checkScope(isCurrent);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    _checkScope(isCurrent);
    if (descriptor.width <= 0 ||
        descriptor.height <= 0 ||
        descriptor.width > maxPrivatePhotoDimension ||
        descriptor.height > maxPrivatePhotoDimension ||
        descriptor.width * descriptor.height > maxPrivatePhotoPixels) {
      throw const FormatException('Photo is too large');
    }
    if (decoder == null) {
      codec = await descriptor.instantiateCodec();
    } else {
      // A framework decoder owns/disposes its input. Give it independent
      // encoded storage rather than a buffer used by the validation descriptor.
      decoderBuffer = await ui.ImmutableBuffer.fromUint8List(encoded);
      _checkScope(isCurrent);
      final transferred = decoderBuffer;
      decoderBuffer = null;
      codec = await decoder(transferred);
    }
    _checkScope(isCurrent);
    if (codec.frameCount != 1) {
      throw const FormatException('Unsupported animated photo');
    }
    final ui.Codec result;
    if (decoder == null) {
      result = _RetainedPhotoCodec(codec, descriptor, buffer);
      descriptor = null;
      buffer = null;
    } else {
      result = codec;
    }
    codec = null;
    return result;
  } finally {
    codec?.dispose();
    decoderBuffer?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Future<Uint8List> privatePhotoAsPng(
  Uint8List encoded, {
  bool Function()? isCurrent,
}) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await decodePrivatePhoto(encoded, isCurrent: isCurrent);
    _checkScope(isCurrent);
    image = (await codec.getNextFrame()).image;
    _checkScope(isCurrent);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    _checkScope(isCurrent);
    if (png == null || png.lengthInBytes == 0) {
      throw const FormatException('Photo could not be encoded');
    }
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
