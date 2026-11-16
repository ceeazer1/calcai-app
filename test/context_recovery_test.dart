import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _mac = 'ca1ca1000001';

CloudService _cloud(Future<http.Response> Function(http.Request) handle) =>
    CloudService(
      client: MockClient((request) async {
        if (request.url.path.startsWith('/ai/context/')) return handle(request);
        return http.Response('{"error":"unavailable"}', 503);
      }),
    );

const EditSnapshot _base = (text: 'Existing', revision: 0, etag: '"fixture-0"');

http.Response _context(String text, {int revision = 0}) => http.Response(
  jsonEncode({
    'ok': true,
    'context': text,
    'rev': revision,
    'etag': '"fixture-$revision"',
  }),
  200,
);

http.Response _accepted({int revision = 1}) => http.Response(
  jsonEncode({'ok': true, 'rev': revision, 'etag': '"fixture-$revision"'}),
  200,
);

void main() {
  for (final header in [null, '"fixture-0"', 'W/"fixture-0"']) {
    test(
      'read accepts matching representation header $header but captures strong JSON tag',
      () async {
        final cloud = _cloud(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'context': '',
              'rev': 0,
              'etag': '"fixture-0"',
            }),
            200,
            headers: {if (header != null) 'etag': header},
          ),
        );
        addTearDown(cloud.dispose);
        final snapshot = await cloud.readContextSnapshot('session', _mac);
        expect(snapshot, (text: '', revision: 0, etag: '"fixture-0"'));
        expect(cloud.contextError, isNull);
      },
    );
  }

  for (final header in [
    '"fixture-1"',
    'W/"fixture-1"',
    'W/fixture-0',
    'w/"fixture-0"',
  ]) {
    test(
      'read rejects different or malformed response header $header',
      () async {
        var invalid = false;
        final cloud = _cloud(
          (_) async => invalid
              ? http.Response(
                  jsonEncode({
                    'ok': true,
                    'context': 'Unconfirmed',
                    'rev': 0,
                    'etag': '"fixture-0"',
                  }),
                  200,
                  headers: {'etag': header},
                )
              : _context('Verified'),
        );
        addTearDown(cloud.dispose);
        await cloud.readContextSnapshot('session', _mac);
        invalid = true;
        expect(await cloud.readContextSnapshot('session', _mac), isNull);
        expect(cloud.customContext, 'Verified');
        expect(cloud.contextError, contains('unexpected'));
      },
    );
  }

  for (final header in [null, '"fixture-1"', 'W/"fixture-1"']) {
    test(
      'save accepts matching representation header $header without weakening If-Match',
      () async {
        final cloud = _cloud((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'ok': true,
                'context': 'Existing',
                'rev': 0,
                'etag': '"fixture-0"',
              }),
              200,
              headers: {'etag': 'W/"fixture-0"'},
            );
          }
          expect(request.headers['If-Match'], '"fixture-0"');
          expect(jsonDecode(request.body), {
            'mac': _mac,
            'context': 'Saved',
            'expectedRev': 0,
          });
          return http.Response(
            jsonEncode({'ok': true, 'rev': 1, 'etag': '"fixture-1"'}),
            200,
            headers: {if (header != null) 'etag': header},
          );
        });
        addTearDown(cloud.dispose);
        final base = (await cloud.readContextSnapshot('session', _mac))!;
        final accepted = await cloud.writeContextSnapshot(
          'session',
          _mac,
          'Saved',
          base: base,
        );
        expect(accepted, (text: 'Saved', revision: 1, etag: '"fixture-1"'));
        expect(cloud.contextError, isNull);
      },
    );
  }

  for (final header in [
    '"fixture-2"',
    'W/"fixture-2"',
    'W/fixture-1',
    'w/"fixture-1"',
  ]) {
    test(
      'save rejects different or malformed response header $header',
      () async {
        final cloud = _cloud(
          (request) async => request.method == 'GET'
              ? _context('Existing')
              : http.Response(
                  jsonEncode({'ok': true, 'rev': 1, 'etag': '"fixture-1"'}),
                  200,
                  headers: {'etag': header},
                ),
        );
        addTearDown(cloud.dispose);
        final base = (await cloud.readContextSnapshot('session', _mac))!;
        expect(
          await cloud.writeContextSnapshot(
            'session',
            _mac,
            'Saved',
            base: base,
          ),
          isNull,
        );
        expect(cloud.customContext, 'Existing');
        expect(cloud.contextError, contains('unexpected'));
      },
    );
  }

  test(
    'a strong HTTP header cannot make a weak JSON read validator writable',
    () async {
      final cloud = _cloud(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'context': '',
            'rev': 0,
            'etag': 'W/"fixture-0"',
          }),
          200,
          headers: {'etag': '"fixture-0"'},
        ),
      );
      addTearDown(cloud.dispose);
      expect(await cloud.readContextSnapshot('session', _mac), isNull);
      expect(cloud.contextSnapshot, isNull);
    },
  );

  test(
    'a strong HTTP header cannot confirm a weak JSON save validator',
    () async {
      final cloud = _cloud(
        (request) async => request.method == 'GET'
            ? _context('Existing')
            : http.Response(
                jsonEncode({'ok': true, 'rev': 1, 'etag': 'W/"fixture-1"'}),
                200,
                headers: {'etag': '"fixture-1"'},
              ),
      );
      addTearDown(cloud.dispose);
      final base = (await cloud.readContextSnapshot('session', _mac))!;
      expect(
        await cloud.writeContextSnapshot('session', _mac, 'Saved', base: base),
        isNull,
      );
      expect(cloud.customContext, 'Existing');
    },
  );

  test('writes without a captured base never reach the server', () async {
    var writes = 0;
    final cloud = _cloud((_) async {
      writes++;
      return _accepted();
    });
    addTearDown(cloud.dispose);
    expect(await cloud.setContext('session', _mac, 'No base'), isFalse);
    expect(writes, 0);
  });

  test(
    'background cache refresh cannot replace a draft captured validator',
    () async {
      var reads = 0;
      final cloud = _cloud((request) async {
        if (request.method == 'GET') {
          return _context(
            ++reads == 1 ? 'Editor base' : 'Other editor',
            revision: reads,
          );
        }
        expect(request.headers['If-Match'], '"fixture-1"');
        expect((jsonDecode(request.body) as Map)['expectedRev'], 1);
        return http.Response('{"ok":false,"error":"revision_conflict"}', 412);
      });
      addTearDown(cloud.dispose);
      final captured = (await cloud.readContextSnapshot('session', _mac))!;
      await cloud.readContextSnapshot('session', _mac);
      expect(
        await cloud.writeContextSnapshot(
          'session',
          _mac,
          'Draft',
          base: captured,
        ),
        isNull,
      );
      expect(cloud.customContext, 'Other editor');
      expect(cloud.contextConflict, isTrue);
    },
  );

  for (final status in [409, 412]) {
    test(
      'revision conflict $status preserves confirmed text and validators',
      () async {
        final cloud = _cloud(
          (request) async => request.method == 'GET'
              ? _context('Existing')
              : http.Response(
                  '{"ok":false,"error":"revision_conflict"}',
                  status,
                ),
        );
        addTearDown(cloud.dispose);
        final base = (await cloud.readContextSnapshot('session', _mac))!;
        expect(
          await cloud.writeContextSnapshot(
            'session',
            _mac,
            'Draft',
            base: base,
          ),
          isNull,
        );
        expect(cloud.customContext, 'Existing');
        expect(cloud.contextSnapshot, base);
        expect(cloud.contextConflict, isTrue);
      },
    );
  }

  test(
    'malformed or nonadvancing save validators do not confirm a write',
    () async {
      for (final ack in [
        {'ok': true},
        {'ok': true, 'rev': 0, 'etag': '"fixture-1"'},
        {'ok': true, 'rev': 1, 'etag': '"fixture-0"'},
        {'ok': true, 'rev': 1, 'etag': 'W/"fixture-1"'},
      ]) {
        final cloud = _cloud(
          (request) async => request.method == 'GET'
              ? _context('Existing')
              : http.Response(jsonEncode(ack), 200),
        );
        final base = (await cloud.readContextSnapshot('session', _mac))!;
        expect(
          await cloud.writeContextSnapshot(
            'session',
            _mac,
            'Draft',
            base: base,
          ),
          isNull,
        );
        expect(cloud.customContext, 'Existing');
        cloud.dispose();
      }
    },
  );

  test(
    'a lost write reply is reconciled by reading without another mutation',
    () async {
      var stored = 'Existing';
      var revision = 0;
      var writes = 0;
      final cloud = _cloud((request) async {
        if (request.method == 'GET') {
          return _context(stored, revision: revision);
        }
        writes++;
        stored = (jsonDecode(request.body) as Map)['context'] as String;
        revision++;
        throw TimeoutException('Reply lost after commit');
      });
      addTearDown(cloud.dispose);
      final base = (await cloud.readContextSnapshot('session', _mac))!;
      expect(
        await cloud.writeContextSnapshot(
          'session',
          _mac,
          'Desired',
          base: base,
        ),
        isNull,
      );
      expect(cloud.customContext, 'Existing');
      final checked = (await cloud.readContextSnapshot('session', _mac))!;
      expect(checked.text, 'Desired');
      expect(checked.revision, 1);
      expect(writes, 1);
    },
  );

  test(
    'failed context read is unknown rather than a verified empty value',
    () async {
      final cloud = _cloud(
        (_) async => http.Response('{"error":"unavailable"}', 503),
      );
      addTearDown(cloud.dispose);
      expect(await cloud.getContext('session', _mac), isNull);
    },
  );

  test(
    'a slow read cannot restore instructions older than a successful save',
    () async {
      final oldRead = Completer<http.Response>();
      final cloud = _cloud(
        (request) async =>
            request.method == 'GET' ? oldRead.future : _accepted(),
      );
      addTearDown(cloud.dispose);
      final read = cloud.getContext('session', _mac);
      await Future<void>.delayed(Duration.zero);
      expect(
        await cloud.setContext(
          'session',
          _mac,
          'New instructions',
          base: _base,
        ),
        isTrue,
      );
      oldRead.complete(_context('Old instructions'));
      await read;
      expect(cloud.customContext, 'New instructions');
    },
  );

  test(
    'a successful HTTP status without a save acknowledgement is not success',
    () async {
      final cloud = _cloud((_) async => http.Response('{"ok":false}', 200));
      addTearDown(cloud.dispose);
      expect(
        await cloud.setContext(
          'session',
          _mac,
          'Do not claim saved',
          base: _base,
        ),
        isFalse,
      );
      expect(cloud.customContext, isEmpty);
    },
  );

  test(
    'only a confirmed string, including empty, is a successful read',
    () async {
      var response = _context('');
      final cloud = _cloud((_) async => response);
      addTearDown(cloud.dispose);
      expect(await cloud.getContext('session', _mac), '');
      for (final body in [
        '',
        '{}',
        '{"ok":false,"context":"x"}',
        '{"ok":true}',
        '{"ok":true,"context":4}',
        '{"ok":true,"context":"missing validators"}',
        '{"ok":true,"context":"bad revision","rev":-1,"etag":"\\"v\\""}',
        '{"ok":true,"context":"weak validator","rev":0,"etag":"W/\\"v\\""}',
        '{"ok":true,"context":"unquoted validator","rev":0,"etag":"v"}',
        '[]',
      ]) {
        response = http.Response(body, 200);
        expect(await cloud.getContext('session', _mac), isNull, reason: body);
        expect(cloud.contextError, contains('unexpected'));
      }
      response = _context('Recovered');
      expect(await cloud.getContext('session', _mac), 'Recovered');
      expect(cloud.contextError, isNull);
    },
  );

  test(
    'a failed refresh preserves the last confirmed cache but returns unknown',
    () async {
      var response = _context('Confirmed instructions');
      final cloud = _cloud((_) async => response);
      addTearDown(cloud.dispose);
      await cloud.getContext('session', _mac);
      response = http.Response('{"error":"unavailable"}', 503);
      expect(await cloud.getContext('session', _mac), isNull);
      expect(cloud.customContext, 'Confirmed instructions');
      expect(cloud.contextError, isNotNull);
    },
  );

  test(
    'newer reads win without exposing the older response as verified',
    () async {
      final first = Completer<http.Response>();
      var count = 0;
      final cloud = _cloud(
        (_) async => ++count == 1 ? first.future : _context('Newest'),
      );
      addTearDown(cloud.dispose);
      final old = cloud.getContext('session', _mac);
      await Future<void>.delayed(Duration.zero);
      expect(await cloud.getContext('session', _mac), 'Newest');
      first.complete(_context('Older'));
      expect(await old, isNull);
      expect(cloud.customContext, 'Newest');
    },
  );

  test('reads and duplicate writes cannot supersede a pending save', () async {
    final save = Completer<http.Response>();
    var reads = 0;
    var writes = 0;
    final cloud = _cloud((request) async {
      if (request.method == 'GET') {
        reads++;
        return _context('Existing');
      }
      writes++;
      expect(jsonDecode(request.body), {
        'mac': _mac,
        'context': 'Saved',
        'expectedRev': 0,
      });
      expect(request.headers['If-Match'], '"fixture-0"');
      return save.future;
    });
    addTearDown(cloud.dispose);
    await cloud.getContext('session', _mac);
    final pending = cloud.setContext('session', _mac, 'Saved', base: _base);
    await Future<void>.delayed(Duration.zero);
    expect(await cloud.getContext('session', _mac), isNull);
    expect(
      await cloud.setContext('session', _mac, 'Duplicate', base: _base),
      isFalse,
    );
    expect(reads, 1);
    expect(writes, 1);
    save.complete(_accepted());
    expect(await pending, isTrue);
    expect(cloud.customContext, 'Saved');
    expect(cloud.isLoading, isFalse);
  });

  test('account reset fences a pending read and its error', () async {
    final read = Completer<http.Response>();
    var requests = 0;
    final cloud = _cloud(
      (_) async => ++requests == 1 ? read.future : _context('New account'),
    );
    addTearDown(cloud.dispose);
    final old = cloud.getContext('old-session', _mac);
    await Future<void>.delayed(Duration.zero);
    cloud.reset();
    expect(await cloud.getContext('new-session', _mac), 'New account');
    read.complete(http.Response('{"error":"device_not_owned"}', 403));
    expect(await old, isNull);
    expect(cloud.customContext, 'New account');
    expect(cloud.contextError, isNull);
    expect(cloud.deviceRevoked, isFalse);
  });

  test('a pending save cannot populate a replacement account', () async {
    final write = Completer<http.Response>();
    final cloud = _cloud(
      (request) async => request.method == 'POST'
          ? write.future
          : _context('Replacement account'),
    );
    addTearDown(cloud.dispose);
    final old = cloud.setContext(
      'old-session',
      _mac,
      'Old account draft',
      base: _base,
    );
    await Future<void>.delayed(Duration.zero);
    cloud.reset();
    expect(await cloud.getContext('new-session', _mac), 'Replacement account');
    write.complete(_accepted());
    expect(await old, isFalse);
    expect(cloud.customContext, 'Replacement account');
    expect(cloud.contextError, isNull);
    expect(cloud.isLoading, isFalse);
  });

  test(
    'device switching drops the previous cache and fences an older read',
    () async {
      final read = Completer<http.Response>();
      var delayed = false;
      final cloud = _cloud((request) async {
        if (request.url.queryParameters['mac'] == _mac) {
          return delayed ? read.future : _context('Other calculator');
        }
        return http.Response('{"error":"unavailable"}', 503);
      });
      addTearDown(cloud.dispose);
      await cloud.getContext('session', _mac);
      delayed = true;
      final old = cloud.getContext('session', _mac);
      await Future<void>.delayed(Duration.zero);
      expect(await cloud.getContext('session', 'ca1ca1000002'), isNull);
      expect(cloud.customContext, isEmpty);
      read.complete(_context('Stale calculator'));
      expect(await old, isNull);
      expect(cloud.customContext, isEmpty);
    },
  );

  test(
    'failed saves preserve instructions and allow an explicit retry or clear',
    () async {
      var good = false;
      final bodies = <String>[];
      final cloud = _cloud((request) async {
        if (request.method == 'GET') return _context('Existing');
        bodies.add(request.body);
        return good
            ? _accepted()
            : http.Response('{"error":"unavailable"}', 503);
      });
      addTearDown(cloud.dispose);
      await cloud.getContext('session', _mac);
      expect(
        await cloud.setContext('session', _mac, 'New', base: _base),
        isFalse,
      );
      expect(cloud.customContext, 'Existing');
      expect(cloud.contextError, isNotNull);
      expect(bodies, hasLength(1));
      good = true;
      final checked = await cloud.readContextSnapshot('session', _mac);
      expect(
        await cloud.setContext('session', _mac, '', base: checked!),
        isTrue,
      );
      expect(cloud.customContext, isEmpty);
      expect(cloud.contextError, isNull);
      expect(jsonDecode(bodies.last)['context'], '');
    },
  );

  test(
    'the service rejects over-limit writes instead of claiming an untruncated save',
    () async {
      var requests = 0;
      final cloud = _cloud((_) async {
        requests++;
        return http.Response('{"ok":true}', 200);
      });
      addTearDown(cloud.dispose);
      expect(
        await cloud.setContext('session', _mac, 'x' * 2001, base: _base),
        isFalse,
      );
      expect(requests, 0);
      expect(cloud.contextError, contains('2,000'));
    },
  );
}
