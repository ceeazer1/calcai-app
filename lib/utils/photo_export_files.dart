import 'dart:io';

const _photoDirectoryPrefix = 'calcai-photo-';
const _orphanAge = Duration(hours: 24);
final _activePhotoDirectories = <String>{};

String _directoryKey(Directory directory) =>
    directory.absolute.uri.normalizePath().toFilePath();

Future<Directory> createPhotoExportDirectory(Directory base) async {
  await removeStalePhotoExports(base);
  final directory = await base.createTemp(_photoDirectoryPrefix);
  _activePhotoDirectories.add(_directoryKey(directory));
  return directory;
}

/// Release only after the native operation and its ordinary cleanup finish.
void releasePhotoExportDirectory(Directory directory) {
  _activePhotoDirectories.remove(_directoryKey(directory));
}

/// Best-effort cleanup at export entry, not a scheduled or sign-out purge.
/// Never recurse, follow links, or remove an active/fresh/unknown file.
Future<void> removeStalePhotoExports(Directory base, {DateTime? now}) async {
  final cutoff = (now ?? DateTime.now()).subtract(_orphanAge);
  try {
    if (await FileSystemEntity.type(base.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    await for (final entry in base.list(followLinks: false)) {
      final name = entry.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (!name.startsWith(_photoDirectoryPrefix) ||
          name.length == _photoDirectoryPrefix.length) {
        continue;
      }
      try {
        if (await FileSystemEntity.type(entry.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        final directory = Directory(entry.path);
        final key = _directoryKey(directory);
        if (_activePhotoDirectories.contains(key) ||
            !(await directory.stat()).modified.isBefore(cutoff)) {
          continue;
        }
        final contents = await directory.list(followLinks: false).toList();
        if (contents.length > 1) {
          continue;
        }
        File? photo;
        if (contents.isNotEmpty) {
          final candidate = contents.single;
          if (candidate.path !=
                  '${directory.path}${Platform.pathSeparator}photo.png' ||
              await FileSystemEntity.type(candidate.path, followLinks: false) !=
                  FileSystemEntityType.file ||
              !(await candidate.stat()).modified.isBefore(cutoff)) {
            continue;
          }
          photo = File(candidate.path);
        }
        // Recheck immediately before deletion; another export may be active.
        if (_activePhotoDirectories.contains(key) ||
            await FileSystemEntity.type(directory.path, followLinks: false) !=
                FileSystemEntityType.directory ||
            !(await directory.stat()).modified.isBefore(cutoff)) {
          continue;
        }
        if (photo != null) {
          if (await FileSystemEntity.type(photo.path, followLinks: false) !=
                  FileSystemEntityType.file ||
              !(await photo.stat()).modified.isBefore(cutoff)) {
            continue;
          }
          await photo.delete();
        }
        await directory.delete(); // Only succeeds when empty; never recursive.
      } on FileSystemException {
        // A racing deletion or inaccessible entry must not block a new export.
      }
    }
  } on FileSystemException {
    // Cache cleanup is opportunistic; permission/listing errors stay contained.
  }
}
