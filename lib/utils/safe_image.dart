/// Host that serves calculator photos.
///
/// Upload requests hand back `https://ai.calcai.cc/ai/image/view/<key>`, so
/// that is the only origin a history entry's image should ever point at.
const String kImageHost = 'ai.calcai.cc';

/// Returns [raw] if it is a photo URL we are willing to load, else null.
///
/// History entries come back from the API, and the app renders their
/// `imageUrl` directly. Without this an entry could point the app at any
/// server — leaking the user's IP and app-version to a third party on render,
/// or loading hostile bytes into the image decoder. Restricting to HTTPS on
/// our own host means a tampered record renders nothing instead.
String? safeImageUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme != 'https') return null;
  if (uri.host != kImageHost) return null;
  return raw;
}
