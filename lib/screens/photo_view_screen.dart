import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/resilient_http_client.dart';
import '../theme/app_colors.dart';
import '../utils/log.dart';
import '../utils/resilient_image.dart';

/// Full-screen viewer for a calculator photo, with save and share.
///
/// The bytes are fetched once and reused for both actions, so tapping save
/// after share (or vice versa) does not download the photo twice.
class PhotoViewScreen extends StatefulWidget {
  const PhotoViewScreen({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  State<PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends State<PhotoViewScreen> {
  bool _busy = false;
  List<int>? _bytes;

  /// Same DoH-resolving client the rest of the app uses — the OS resolver is
  /// blocked on some networks, which is what broke photos in the first place.
  final _client = createResilientClient();

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  /// Downloads the photo once and caches it for the session.
  Future<List<int>?> _load() async {
    if (_bytes != null) return _bytes;
    try {
      final r = await _client.get(Uri.parse(widget.imageUrl));
      if (r.statusCode != 200) {
        _toast('Could not download the photo (${r.statusCode})');
        return null;
      }
      _bytes = r.bodyBytes;
      return _bytes;
    } catch (e) {
      logDebug('CalcAI photo: download failed — $e');
      _toast('Could not download the photo');
      return null;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
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
  Future<String?> _toTempFile(List<int> bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final name = 'calcai-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      logDebug('CalcAI photo: temp write failed — $e');
      return null;
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _load();
      if (bytes == null) return;
      final path = await _toTempFile(bytes);
      if (path == null) {
        _toast('Could not save the photo');
        return;
      }
      // Gal asks for photo-library access itself and throws GalException when
      // the user declines, so the message can say what to do about it.
      await Gal.putImage(path, album: 'CalcAI');
      _toast('Saved to your photos');
    } on GalException catch (e) {
      logDebug('CalcAI photo: save failed — ${e.type}');
      _toast(e.type == GalExceptionType.accessDenied
          ? 'Allow photo access in Settings to save'
          : 'Could not save the photo');
    } catch (e) {
      logDebug('CalcAI photo: save failed — $e');
      _toast('Could not save the photo');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _load();
      if (bytes == null) return;
      final path = await _toTempFile(bytes);
      if (path == null) {
        _toast('Could not share the photo');
        return;
      }
      await Share.shareXFiles([XFile(path, mimeType: 'image/jpeg')]);
    } catch (e) {
      logDebug('CalcAI photo: share failed — $e');
      _toast('Could not share the photo');
    } finally {
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
                    strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              tooltip: 'Save to photos',
              onPressed: _save,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
              tooltip: 'Share',
              onPressed: _share,
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      // Pinch to zoom and drag to pan, the way a photo viewer should behave.
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image(
            image: ResilientNetworkImage(widget.imageUrl),
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.electricBlue),
              );
            },
            errorBuilder: (_, __, ___) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.image_not_supported_rounded,
                      color: Colors.white38, size: 40),
                  const SizedBox(height: 10),
                  Text(
                    'This photo is no longer available',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: Colors.white38),
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
