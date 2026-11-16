import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calcai_app/screens/photo_view_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/utils/photo_export_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);
const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
const galChannel = MethodChannel('gal');

class _StreamingPhotoClient extends http.BaseClient {
  _StreamingPhotoClient(this.response);
  final http.StreamedResponse Function(http.BaseRequest) response;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      response(request);
}

class _PhotoScopeAuth extends FakeAuthService {
  String? _calculator = 'ca1ca1000001';

  @override
  String? get primaryMac => _calculator;

  void changeCalculator(String? mac) {
    _calculator = mac;
    notifyListeners();
  }
}

dynamic photoAction(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon)).onPressed;

Future<FakeAuthService> showPhoto(
  WidgetTester tester,
  http.Client client,
  Future<Directory> Function() temporary, {
  FakeAuthService? auth,
}) async {
  auth ??= FakeAuthService();
  await auth.init();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: MaterialApp(
        home: PhotoViewScreen(
          imageUrl: 'https://ai.calcai.cc/ai/image/view/fixture',
          client: client,
          imageProvider: MemoryImage(png),
          temporaryDirectoryProvider: temporary,
        ),
      ),
    ),
  );
  await tester.pump();
  return auth;
}

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('calcai-photo-test-');
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(galChannel, null);
    await temporary.delete(recursive: true);
  });

  for (final nextCalculator in ['ca1ca1000002', null]) {
    testWidgets(
      'calculator ${nextCalculator == null ? 'unlink' : 'switch'} invalidates cached photo and stale export actions',
      (tester) async {
        var exports = 0;
        var downloads = 0;
        final auth = _PhotoScopeAuth();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(shareChannel, (_) async {
              exports++;
              return 'fixture';
            });
        await showPhoto(
          tester,
          MockClient((_) async {
            downloads++;
            return http.Response.bytes(png, 200);
          }),
          () async => temporary,
          auth: auth,
        );
        final dynamic staleAction = photoAction(
          tester,
          Icons.ios_share_rounded,
        );
        await tester.runAsync(() async => await staleAction());
        await tester.pump();
        expect(exports, 1);

        auth.changeCalculator(nextCalculator);
        await tester.pump();
        expect(photoAction(tester, Icons.ios_share_rounded), isNull);
        expect(photoAction(tester, Icons.download_rounded), isNull);
        expect(find.byType(InteractiveViewer), findsNothing);
        await tester.runAsync(() async => await staleAction());
        expect(exports, 1);

        auth.changeCalculator('ca1ca1000001');
        await tester.pump();
        expect(photoAction(tester, Icons.ios_share_rounded), isNull);
        expect(find.byType(InteractiveViewer), findsNothing);
        await tester.runAsync(() async => await staleAction());
        expect(exports, 1);
        expect(downloads, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'calculator switch during download prevents temp file and export',
    (tester) async {
      late Completer<http.Response> response;
      var tempCalls = 0;
      var exports = 0;
      final auth = _PhotoScopeAuth();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (_) async {
            exports++;
            return 'fixture';
          });
      await showPhoto(tester, MockClient((_) => response.future), () async {
        tempCalls++;
        return temporary;
      }, auth: auth);
      final dynamic action = photoAction(tester, Icons.ios_share_rounded);
      await tester.runAsync(() async {
        response = Completer<http.Response>();
        final pending = action() as Future<void>;
        auth.changeCalculator('ca1ca1000002');
        response.complete(http.Response.bytes(png, 200));
        await pending.timeout(const Duration(seconds: 5));
      });
      expect(exports, 0);
      expect(tempCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'calculator unlink while waiting for temp storage prevents export',
    (tester) async {
      late Completer<Directory> directory;
      late Completer<void> requested;
      var exports = 0;
      final auth = _PhotoScopeAuth();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (_) async {
            exports++;
            return 'fixture';
          });
      await showPhoto(
        tester,
        MockClient((_) async => http.Response.bytes(png, 200)),
        () {
          requested.complete();
          return directory.future;
        },
        auth: auth,
      );
      final dynamic action = photoAction(tester, Icons.ios_share_rounded);
      await tester.runAsync(() async {
        directory = Completer<Directory>();
        requested = Completer<void>();
        final pending = action() as Future<void>;
        await requested.future.timeout(const Duration(seconds: 5));
        auth.changeCalculator(null);
        directory.complete(temporary);
        await pending.timeout(const Duration(seconds: 5));
        expect(await temporary.list().isEmpty, isTrue);
      });
      expect(exports, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'returning to the same token cannot revive an invalidated photo',
    (tester) async {
      var exports = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (_) async {
            exports++;
            return 'fixture';
          });
      final auth = await showPhoto(
        tester,
        MockClient((_) async => http.Response.bytes(png, 200)),
        () async => temporary,
      );
      final dynamic staleAction = photoAction(tester, Icons.ios_share_rounded);
      await auth.signOut();
      await auth.init();
      await tester.pump();
      expect(photoAction(tester, Icons.ios_share_rounded), isNull);
      expect(find.byType(InteractiveViewer), findsNothing);
      await tester.runAsync(() async => await staleAction());
      expect(exports, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cached photo cannot export after its account signs out', (
    tester,
  ) async {
    var downloads = 0;
    var exports = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          exports++;
          return 'fixture';
        });
    final auth = await showPhoto(
      tester,
      MockClient((_) async {
        downloads++;
        return http.Response.bytes(png, 200);
      }),
      () async => temporary,
    );
    final dynamic staleAction = photoAction(tester, Icons.ios_share_rounded);
    await tester.runAsync(() async => await staleAction());
    await tester.pump();
    expect(exports, 1);
    await auth.signOut();
    await tester.pump();
    expect(photoAction(tester, Icons.ios_share_rounded), isNull);
    expect(
      find.text('Your account or calculator changed. Reopen this photo.'),
      findsOneWidget,
    );
    await tester.runAsync(() async => await staleAction());
    expect(exports, 1);
    expect(downloads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('signout during a download prevents temp file and export', (
    tester,
  ) async {
    late Completer<http.Response> response;
    var tempCalls = 0;
    var exports = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (_) async {
          exports++;
          return 'fixture';
        });
    final auth = await showPhoto(
      tester,
      MockClient((_) => response.future),
      () async {
        tempCalls++;
        return temporary;
      },
    );
    final dynamic action = photoAction(tester, Icons.ios_share_rounded);
    await tester.runAsync(() async {
      response = Completer<http.Response>();
      final pending = action() as Future<void>;
      await auth.signOut();
      response.complete(http.Response.bytes(png, 200));
      await pending.timeout(const Duration(seconds: 5));
    });
    await tester.pump();
    expect(exports, 0);
    expect(tempCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('signout while waiting for temp storage prevents export', (
    tester,
  ) async {
    late Completer<Directory> directory;
    late Completer<void> requested;
    var exports = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (_) async {
          exports++;
          return 'fixture';
        });
    final auth = await showPhoto(
      tester,
      MockClient((_) async => http.Response.bytes(png, 200)),
      () {
        requested.complete();
        return directory.future;
      },
    );
    final dynamic action = photoAction(tester, Icons.ios_share_rounded);
    await tester.runAsync(() async {
      directory = Completer<Directory>();
      requested = Completer<void>();
      final pending = action() as Future<void>;
      await requested.future.timeout(const Duration(seconds: 5));
      await auth.signOut();
      directory.complete(temporary);
      await pending.timeout(const Duration(seconds: 5));
      expect(await temporary.list().isEmpty, isTrue);
    });
    expect(exports, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'share keeps its file until dismissed then removes only its files',
    (tester) async {
      late Completer<String> exported;
      late Completer<String> released;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
            exported.complete(
              ((call.arguments as Map)['paths'] as List).single as String,
            );
            return released.future;
          });
      await showPhoto(
        tester,
        MockClient((_) async => http.Response.bytes(png, 200)),
        () async => temporary,
      );
      final dynamic action = photoAction(tester, Icons.ios_share_rounded);
      await tester.runAsync(() async {
        exported = Completer<String>();
        released = Completer<String>();
        final unrelated = File('${temporary.path}/keep.txt');
        await unrelated.writeAsString('fixture');
        final pending = action() as Future<void>;
        final path = await exported.future.timeout(const Duration(seconds: 5));
        expect(await File(path).exists(), isTrue);
        await removeStalePhotoExports(
          temporary,
          now: DateTime.now().add(const Duration(days: 2)),
        );
        expect(
          await File(path).exists(),
          isTrue,
          reason: 'active shares must survive stale-file cleanup',
        );
        released.complete('fixture');
        await pending.timeout(const Duration(seconds: 5));
        expect(await File(path).exists(), isFalse);
        expect(await File(path).parent.exists(), isFalse);
        expect(await unrelated.exists(), isTrue);
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Gal access checks and requests default to add-only even when denied',
    (tester) async {
      final calls = <(String, bool)>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(galChannel, (call) async {
            calls.add((
              call.method,
              (call.arguments as Map)['toAlbum'] as bool,
            ));
            return false;
          });
      expect(await Gal.hasAccess(), isFalse);
      expect(await Gal.requestAccess(), isFalse);
      expect(calls, [('hasAccess', false), ('requestAccess', false)]);
    },
  );

  for (final denied in [false, true]) {
    testWidgets(
      'gallery ${denied ? 'denial' : 'save'} removes its generated photo',
      (tester) async {
        String? path;
        final accessRequests = <bool>[];
        var putCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(galChannel, (call) async {
              if (call.method == 'requestAccess') {
                accessRequests.add((call.arguments as Map)['toAlbum'] as bool);
                return !denied;
              }
              if (call.method == 'putImage') {
                putCalls++;
                final arguments = call.arguments as Map;
                expect(arguments['album'], isNull);
                path = arguments['path'] as String;
                expect(path, endsWith('.png'));
                expect(await File(path!).exists(), isTrue);
                expect((await File(path!).readAsBytes()).take(8).toList(), [
                  137,
                  80,
                  78,
                  71,
                  13,
                  10,
                  26,
                  10,
                ]);
                if (denied) {
                  throw PlatformException(code: 'ACCESS_DENIED');
                }
              }
              return null;
            });
        await showPhoto(
          tester,
          MockClient((_) async => http.Response.bytes(png, 200)),
          () async => temporary,
        );
        final dynamic action = photoAction(tester, Icons.download_rounded);
        await tester.runAsync(() async {
          await action();
          expect(path, isNotNull);
          expect(await File(path!).exists(), isFalse);
          expect(await temporary.list().isEmpty, isTrue);
        });
        await tester.pump();
        expect(accessRequests, [false]);
        expect(putCalls, 1);
        expect(
          find.text('Saved to your photos'),
          denied ? findsNothing : findsOneWidget,
        );
        if (denied) {
          expect(
            find.text('Allow photo access in Settings to save'),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  final invalidPhotos = <String, List<int>>{
    'empty': [],
    'JSON': utf8.encode('{"ok":true,"message":"not an image"}'),
    'HTML': utf8.encode('<html>temporary upstream error</html>'),
    'truncated PNG': png.sublist(0, png.length - 4),
    'corrupt PNG with valid signature and end': [
      ...png.take(8),
      ...png.skip(png.length - 12),
    ],
    'truncated JPEG': [255, 216, 255, 224, 0, 16, 74, 70],
    'corrupt JPEG with complete markers': [255, 216, 255, 224, 0, 16, 255, 217],
  };

  testWidgets(
    'oversized injected downloads cancel before the tail and never create temp files or export',
    (tester) async {
      var requests = 0;
      var chunks = 0;
      var cancellations = 0;
      var nativeCalls = 0;
      var tempCalls = 0;
      Stream<List<int>> oversized() async* {
        try {
          final chunk = Uint8List(1024 * 1024);
          for (var i = 0; i < 12; i++) {
            chunks++;
            yield chunk;
          }
        } finally {
          cancellations++;
        }
      }

      for (final channel in [galChannel, shareChannel]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              nativeCalls++;
              return null;
            });
      }
      await showPhoto(
        tester,
        _StreamingPhotoClient((request) {
          requests++;
          expect(request.followRedirects, isFalse);
          return http.StreamedResponse(oversized(), 200);
        }),
        () async {
          tempCalls++;
          return temporary;
        },
      );
      for (final icon in [Icons.download_rounded, Icons.ios_share_rounded]) {
        final dynamic action = photoAction(tester, icon);
        await tester.runAsync(() async => await action());
        await tester.pump();
        expect(chunks, requests * 11);
        expect(cancellations, requests);
      }
      expect(requests, 2);
      expect(tempCalls, 0);
      expect(nativeCalls, 0);
      expect(find.text('Saved to your photos'), findsNothing);
      await tester.runAsync(
        () async => expect(await temporary.list().isEmpty, isTrue),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final fixture in invalidPhotos.entries) {
    testWidgets('${fixture.key} 200 response never reaches Photos or sharing', (
      tester,
    ) async {
      var platformCalls = 0;
      var tempCalls = 0;
      for (final channel in [galChannel, shareChannel]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              platformCalls++;
              return null;
            });
      }
      await showPhoto(
        tester,
        MockClient((_) async => http.Response.bytes(fixture.value, 200)),
        () async {
          tempCalls++;
          return temporary;
        },
      );
      for (final icon in [Icons.download_rounded, Icons.ios_share_rounded]) {
        final dynamic action = photoAction(tester, icon);
        await tester.runAsync(() async {
          await action();
          expect(await temporary.list().isEmpty, isTrue);
        });
        await tester.pump();
      }
      expect(platformCalls, 0);
      expect(tempCalls, 0);
      expect(
        find.text('Could not prepare this photo. Try again.'),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'retry after invalid bytes downloads and exports a validated PNG',
    (tester) async {
      var downloads = 0;
      var exports = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
            exports++;
            expect((call.arguments as Map)['mimeTypes'], ['image/png']);
            return 'fixture';
          });
      await showPhoto(
        tester,
        MockClient((_) async {
          downloads++;
          return http.Response.bytes(downloads == 1 ? [] : png, 200);
        }),
        () async => temporary,
      );
      final dynamic action = photoAction(tester, Icons.ios_share_rounded);
      await tester.runAsync(() async => await action());
      await tester.pump();
      expect(exports, 0);
      await tester.runAsync(() async => await action());
      await tester.pump();
      expect(downloads, 2);
      expect(exports, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
