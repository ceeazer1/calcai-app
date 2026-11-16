import 'dart:io';

import 'package:calcai_app/utils/photo_export_files.dart';
import 'package:flutter_test/flutter_test.dart';

class _BrokenListingDirectory extends Fake implements Directory {
  _BrokenListingDirectory(this.path);
  @override
  final String path;
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream.error(FileSystemException('fixture listing failure', path));
}

Future<void> _setDirectoryModified(Directory directory, DateTime value) async {
  // File.setLastModified rejects directories on macOS (errno21). POSIX touch
  // supports real directory timestamps; arguments target only isolated fixtures.
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  final timestamp = '${utc.year}${pad(utc.month)}${pad(utc.day)}'
      '${pad(utc.hour)}${pad(utc.minute)}.${pad(utc.second)}';
  final result = await Process.run('touch', ['-m', '-t', timestamp, directory.path],
      environment: {'TZ': 'UTC'});
  expect(result.exitCode, 0, reason: 'Could not set isolated directory timestamp: ${result.stderr}');
  expect((await directory.stat()).modified.difference(value).inSeconds.abs(), lessThan(2));
}

void main() {
  late Directory root;
  final now = DateTime.now();
  final old = now.subtract(const Duration(hours: 25));

  Future<Directory> entry(
    String name, {
    bool stale = true,
    String fileName = 'photo.png',
  }) async {
    final directory = await Directory('${root.path}/$name').create();
    final file = await File(
      '${directory.path}/$fileName',
    ).writeAsString('synthetic private photo');
    if (stale) {
      await file.setLastModified(old);
      await _setDirectoryModified(directory, old);
    }
    return directory;
  }

  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('photo-cleanup-fixture-'),
  );
  tearDown(() async => await root.delete(recursive: true));

  test(
    'only stale owned plain photos and empty directories are removed',
    () async {
      final stale = await entry('calcai-photo-stale');
      final fresh = await entry('calcai-photo-fresh', stale: false);
      final empty = await Directory('${root.path}/calcai-photo-empty').create();
      await _setDirectoryModified(empty, old);
      await removeStalePhotoExports(root, now: now);
      expect(await stale.exists(), isFalse);
      expect(await empty.exists(), isFalse);
      expect(
        await File('${fresh.path}/photo.png').readAsString(),
        'synthetic private photo',
      );
    },
  );

  test('both the directory and photo must be older than 24 hours', () async {
    final freshFile = await entry('calcai-photo-fresh-file');
    await File('${freshFile.path}/photo.png').setLastModified(now);
    await _setDirectoryModified(freshFile, old);
    final freshDirectory = await entry('calcai-photo-fresh-directory');
    await _setDirectoryModified(freshDirectory, now);
    await removeStalePhotoExports(root, now: now);
    expect(await File('${freshFile.path}/photo.png').exists(), isTrue);
    expect(await File('${freshDirectory.path}/photo.png').exists(), isTrue);
  });

  test(
    'active operation is preserved even when aged, then eligible after release',
    () async {
      final active = await createPhotoExportDirectory(root);
      final photo = await File(
        '${active.path}/photo.png',
      ).writeAsString('active share');
      await photo.setLastModified(old);
      await _setDirectoryModified(active, old);
      await removeStalePhotoExports(root, now: now);
      expect(await photo.readAsString(), 'active share');
      releasePhotoExportDirectory(active);
      await removeStalePhotoExports(root, now: now);
      expect(await active.exists(), isFalse);
    },
  );

  test(
    'unrelated names, extra children, nested folders and unknown files stay untouched',
    () async {
      final unrelated = await entry('other-photos');
      final extra = await entry('calcai-photo-extra');
      await File('${extra.path}/keep.txt').writeAsString('unrelated');
      await _setDirectoryModified(extra, old);
      final nested = await entry('calcai-photo-nested');
      await Directory('${nested.path}/child').create();
      await _setDirectoryModified(nested, old);
      final unknown = await entry(
        'calcai-photo-unknown',
        fileName: 'other.png',
      );
      await removeStalePhotoExports(root, now: now);
      for (final directory in [unrelated, extra, nested, unknown]) {
        expect(await directory.exists(), isTrue);
      }
      expect(await File('${extra.path}/keep.txt').readAsString(), 'unrelated');
    },
  );

  test(
    'directory links, photo links and a linked base are never followed',
    () async {
      final external = await Directory.systemTemp.createTemp(
        'photo-cleanup-outside-',
      );
      addTearDown(() => external.delete(recursive: true));
      final target = await File(
        '${external.path}/photo.png',
      ).writeAsString('outside fixture');
      await target.setLastModified(old);
      await _setDirectoryModified(external, old);
      final directoryLink = await Link(
        '${root.path}/calcai-photo-directory-link',
      ).create(external.path);
      final fileDirectory = await Directory(
        '${root.path}/calcai-photo-file-link',
      ).create();
      await Link('${fileDirectory.path}/photo.png').create(target.path);
      await _setDirectoryModified(fileDirectory, old);
      final baseLink = await Link(
        '${root.path}/base-link',
      ).create(external.path);
      await removeStalePhotoExports(root, now: now);
      await removeStalePhotoExports(Directory(baseLink.path), now: now);
      expect(await directoryLink.exists(), isTrue);
      expect(await Link('${fileDirectory.path}/photo.png').exists(), isTrue);
      expect(await target.readAsString(), 'outside fixture');
    },
  );

  test(
    'listing errors and a missing base do not escape or delete anything',
    () async {
      final stale = await entry('calcai-photo-stale');
      await removeStalePhotoExports(
        _BrokenListingDirectory(root.path),
        now: now,
      );
      await removeStalePhotoExports(
        Directory('${root.path}/missing'),
        now: now,
      );
      expect(
        await File('${stale.path}/photo.png').readAsString(),
        'synthetic private photo',
      );
    },
  );
}
