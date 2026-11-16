import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;

import '../services/resilient_http_client.dart';
import '../theme/app_colors.dart';
import '../utils/log.dart';
import '../utils/resilient_image.dart';
import '../utils/private_photo.dart';
import '../utils/photo_export_files.dart';

/// Full-screen viewer for a calculator photo, with save and share.
///
/// The bytes are fetched once and reused for both actions, so tapping save
/// after share (or vice versa) does not download the photo twice.
class PhotoViewScreen extends StatefulWidget {
  const PhotoViewScreen({
    super.key,
    required this.imageUrl,
    this.client,
    this.imageProvider,
    this.temporaryDirectoryProvider,
  });

  final String imageUrl;
  final http.Client? client;
  final ImageProvider? imageProvider;
  final Future<Directory> Function()? temporaryDirectoryProvider;

  @override
  State<PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends State<PhotoViewScreen> {
  bool _busy = false;
  bool _invalidated = false;
  Uint8List? _bytes;
  late final AuthService _auth;
  late final String? _sessionToken;
  late final String? _sessionMac;

  /// Uses the same private native transport and deadlines as the cloud APIs.
  late final http.Client _client;

  bool get _scopeMatches =>
      _sessionToken != null &&
      _sessionMac != null &&
      _auth.token == _sessionToken &&
      _auth.primaryMac == _sessionMac;

  bool get _isCurrent => mounted && !_invalidated && _scopeMatches;

  @override
  void initState() {
    super.initState();
    _client =
        widget.client ??
        createResilientClient(maxResponseBytes: maxPrivatePhotoBytes);
    _auth = context.read<AuthService>();
    _sessionToken = _auth.token;
    _sessionMac = _auth.primaryMac;
    _auth.addListener(_handleSessionChange);
  }

  void _handleSessionChange() {
    if (!_invalidated && !_scopeMatches && mounted) {
      setState(() {
        // Returning to the original account/calculator must not revive a
        // viewer or an export that was opened under an earlier scope.
        _invalidated = true;
        _bytes = null;
      });
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_handleSessionChange);
    _bytes = null;
    _client.close();
    super.dispose();
  }

  /// Downloads the photo once and caches it for the session.
  Future<List<int>?> _load() async {
    if (!_isCurrent) return null;
    if (_bytes != null) return _bytes;
    try {
      final encoded = await downloadPrivatePhoto(
        _client,
        widget.imageUrl,
        _sessionToken,
      );
      if (!_isCurrent) return null;
      final prepared = await privatePhotoAsPng(
        encoded,
        isCurrent: () => _isCurrent,
      );
      if (!_isCurrent) return null;
      _bytes = prepared;
      return _bytes;
    } on PhotoDownloadException catch (error) {
      if (_isCurrent) {
        _toast('Could not download the photo (${error.statusCode})');
      }
      return null;
    } catch (e) {
      if (_isCurrent) {
        logDebug('CalcAI photo: download failed');
        _toast('Could not prepare this photo. Try again.');
      }
      return null;
    }
  }

  void _toast(String msg) {
    if (!_isCurrent) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter()),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Writes the photo to a temp file — both Gal and the share sheet want a
  /// path, not bytes in memory.
  Future<File?> _toTempFile(List<int> bytes) async {
    File? file;
    Directory? operationDirectory;
    try {
      final dir =
          await (widget.temporaryDirectoryProvider?.call() ??
              getTemporaryDirectory());
      if (!_isCurrent) return null;
      operationDirectory = await createPhotoExportDirectory(dir);
      if (!_isCurrent) {
        await _removeTempFile(null, operationDirectory);
        return null;
      }
      file = File('${operationDirectory.path}/photo.png');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      await _removeTempFile(file, operationDirectory);
      logDebug('CalcAI photo: temp write failed');
      return null;
    }
  }

  Future<void> _removeTempFile(File? file, [Directory? directory]) async {
    final parent = directory ?? file?.parent;
    try {
      if (file != null && await file.exists()) await file.delete();
      // Only this action's uniquely created directory, and never recursively.
      if (parent != null && await parent.exists()) await parent.delete();
    } on FileSystemException {
      logDebug('CalcAI photo: temporary photo cleanup failed');
    } finally {
      if (parent != null) {
        releasePhotoExportDirectory(parent);
      }
    }
  }

  Future<void> _save() async {
    if (_busy || !_isCurrent) return;
    File? file;
    setState(() => _busy = true);
    try {
      final bytes = await _load();
      if (bytes == null || !_isCurrent) return;
      file = await _toTempFile(bytes);
      if (file == null) {
        _toast('Could not save the photo');
        return;
      }
      if (!_isCurrent) return;
      // No custom album: Gal requests add-only access instead of read/write.
      // Permission errors still use the existing denial feedback below.
      await Gal.putImage(file.path);
      _toast('Saved to your photos');
    } on GalException catch (e) {
      logDebug('CalcAI photo: save failed — ${e.type}');
      _toast(
        e.type == GalExceptionType.accessDenied
            ? 'Allow photo access in Settings to save'
            : 'Could not save the photo',
      );
    } catch (e) {
      logDebug('CalcAI photo: save failed — $e');
      _toast('Could not save the photo');
    } finally {
      await _removeTempFile(file);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy || !_isCurrent) return;
    File? file;
    setState(() => _busy = true);
    try {
      final bytes = await _load();
      if (bytes == null || !_isCurrent) return;
      file = await _toTempFile(bytes);
      if (file == null) {
        _toast('Could not share the photo');
        return;
      }
      if (!mounted || !_isCurrent) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      logDebug('CalcAI photo: share failed — $e');
      _toast('Could not share the photo');
    } finally {
      await _removeTempFile(file);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              tooltip: 'Save to photos',
              onPressed: _isCurrent ? _save : null,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
              tooltip: 'Share',
              onPressed: _isCurrent ? _share : null,
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      // Pinch to zoom and drag to pan, the way a photo viewer should behave.
      body: Center(
        child: !_isCurrent
            ? const Text(
                'Your account or calculator changed. Reopen this photo.',
                style: TextStyle(color: Colors.white70),
              )
            : InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image(
                  image:
                      widget.imageProvider ??
                      ResilientNetworkImage(
                        widget.imageUrl,
                        token: _sessionToken,
                      ),
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.electricBlue,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.image_not_supported_rounded,
                          color: Colors.white38,
                          size: 40,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'This photo is no longer available',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
