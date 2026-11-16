import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:calcai_app/services/bounded_response.dart';
import 'package:calcai_app/utils/private_photo.dart';
import 'package:calcai_app/utils/resilient_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'photo_view_session_test.dart' show png;

const _url = 'https://ai.calcai.cc/ai/image/view/fixture?access=fixture-signed';

class _StreamClient extends http.BaseClient {
  _StreamClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

Uint8List _pngWithDimensions(int width, int height) {
  final value = Uint8List.fromList(png);
  final data = ByteData.sublistView(value);
  data.setUint32(16, width);
  data.setUint32(20, height);
  var crc = 0xffffffff;
  for (final byte in value.sublist(12, 29)) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  data.setUint32(29, (crc ^ 0xffffffff) & 0xffffffff);
  return value;
}

class _AnimatedCodec extends Fake implements ui.Codec {
  bool disposed = false;
  @override
  int get frameCount => 2;
  @override
  void dispose() => disposed = true;
}

Future<(int, int)> _resolve(ResilientNetworkImage provider) async {
  final result = Completer<(int, int)>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener(
    (info, _) {
      if (!result.isCompleted) {
        result.complete((info.image.width, info.image.height));
      }
      info.dispose();
    },
    onError: (error, stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  try {
    return await result.future.timeout(const Duration(seconds: 3));
  } finally {
    stream.removeListener(listener);
  }
}

void main() {
  test(
    'private photo requests refuse redirects while preserving private headers and signed query',
    () async {
      var sends = 0;
      final client = _StreamClient((request) async {
        sends++;
        expect(request.url.toString(), _url);
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'], 'Bearer fixture-token');
        return http.StreamedResponse(
          Stream.value([]),
          302,
          headers: {'location': 'https://outside.example/private.png'},
        );
      });
      addTearDown(client.close);
      await expectLater(
        downloadPrivatePhoto(client, _url, 'fixture-token'),
        throwsA(
          isA<PhotoDownloadException>().having(
            (error) => error.statusCode,
            'status',
            302,
          ),
        ),
      );
      expect(sends, 1);
    },
  );

  test(
    'a foreign photo URL is rejected before an injected client sends anything',
    () async {
      var sends = 0;
      final client = _StreamClient((request) async {
        sends++;
        throw StateError('not reachable');
      });
      addTearDown(client.close);
      await expectLater(
        downloadPrivatePhoto(
          client,
          'https://outside.example/image.png',
          'fixture-token',
        ),
        throwsFormatException,
      );
      expect(sends, 0);
    },
  );

  test(
    'injected streamed photo body cancels on the first excess chunk without reading its tail',
    () async {
      var produced = 0;
      var cancelled = false;
      Stream<List<int>> body() async* {
        try {
          final chunk = Uint8List(1024 * 1024);
          for (var i = 0; i < 12; i++) {
            produced++;
            yield chunk;
          }
        } finally {
          cancelled = true;
        }
      }

      final client = _StreamClient(
        (_) async => http.StreamedResponse(body(), 200),
      );
      addTearDown(client.close);
      await expectLater(
        downloadPrivatePhoto(client, _url, 'fixture-token'),
        throwsA(isA<ResponseTooLargeException>()),
      );
      expect(produced, 11);
      expect(cancelled, isTrue);
    },
  );

  test(
    'known oversized bodies are cancelled before reading data; the exact bound is accepted',
    () async {
      var cancelled = false;
      var produced = 0;
      Stream<List<int>> body() async* {
        produced++;
        yield [1];
      }

      final stream = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final oversized = http.StreamedResponse(
        stream.stream,
        200,
        contentLength: 5,
      );
      await expectLater(
        readBoundedResponse(oversized, maxResponseBytes: 4),
        throwsA(isA<ResponseTooLargeException>()),
      );
      expect(cancelled, isTrue);
      await stream.close();
      expect(produced, 0);
      expect(
        await readBoundedResponse(
          http.StreamedResponse(body(), 200, contentLength: 1),
          maxResponseBytes: 1,
        ),
        [1],
      );
    },
  );

  for (final dimensions in [(8193, 1), (4097, 4096)]) {
    testWidgets(
      'preview and export reject ${dimensions.$1}x${dimensions.$2} before allocating a frame',
      (tester) async {
        final encoded = _pngWithDimensions(dimensions.$1, dimensions.$2);
        var decoderCalls = 0;
        await tester.runAsync(() async {
          await expectLater(
            decodePrivatePhoto(
              encoded,
              decoder: (buffer) async {
                decoderCalls++;
                buffer.dispose();
                throw StateError('pixel decoder must not run');
              },
            ),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'reason',
                'Photo is too large',
              ),
            ),
          );
          await expectLater(
            privatePhotoAsPng(encoded),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'reason',
                'Photo is too large',
              ),
            ),
          );
        });
        expect(decoderCalls, 0);
      },
    );
  }

  testWidgets(
    'preview rejects unsupported multiple frames and disposes the rejected codec',
    (tester) async {
      final codec = _AnimatedCodec();
      await tester.runAsync(() async {
        await expectLater(
          decodePrivatePhoto(
            png,
            decoder: (buffer) async {
              buffer.dispose();
              return codec;
            },
          ),
          throwsFormatException,
        );
      });
      expect(codec.disposed, isTrue);
    },
  );

  testWidgets(
    'valid PNG preview keeps the framework decoder and export remains normalized PNG',
    (tester) async {
      var decoderCalls = 0;
      await tester.runAsync(() async {
        final codec = await decodePrivatePhoto(
          png,
          decoder: (buffer) {
            decoderCalls++;
            return ui.instantiateImageCodecWithSize(buffer);
          },
        );
        final image = (await codec.getNextFrame()).image;
        expect((image.width, image.height), (1, 1));
        image.dispose();
        codec.dispose();
        final normalized = await privatePhotoAsPng(png);
        expect(normalized.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
      });
      expect(decoderCalls, 1);
    },
  );

  testWidgets(
    'actual preview provider rejects a huge image and recovers on a fresh retry',
    (tester) async {
      var reads = 0;
      final client = _StreamClient((request) async {
        expect(request.followRedirects, isFalse);
        reads++;
        return http.StreamedResponse(
          Stream.value(reads == 1 ? _pngWithDimensions(8193, 1) : png),
          200,
        );
      });
      addTearDown(client.close);
      final provider = ResilientNetworkImage(
        _url,
        token: 'fixture-token',
        client: client,
      );
      await tester.runAsync(() async {
        await expectLater(_resolve(provider), throwsFormatException);
        await Future<void>.delayed(
          Duration.zero,
        ); // Failed cache entry eviction.
        expect(await _resolve(provider), (1, 1));
      });
      expect(reads, 2);
    },
  );
}
