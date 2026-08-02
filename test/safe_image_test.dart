import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/utils/safe_image.dart';

void main() {
  test('accepts the URL shape the upload endpoint hands back', () {
    const u = 'https://ai.calcai.cc/ai/image/view/0123456789abcdef';
    expect(safeImageUrl(u), u);
  });

  test('rejects other hosts', () {
    expect(safeImageUrl('https://evil.example/x.png'), isNull);
    // Prefix and suffix tricks on the expected host.
    expect(safeImageUrl('https://ai.calcai.cc.evil.example/x.png'), isNull);
    expect(safeImageUrl('https://evil.example/?ai.calcai.cc'), isNull);
    expect(safeImageUrl('https://notai.calcai.cc/x.png'), isNull);
  });

  test('rejects non-https schemes', () {
    expect(safeImageUrl('http://ai.calcai.cc/ai/image/view/a'), isNull);
    expect(safeImageUrl('file:///etc/passwd'), isNull);
    expect(safeImageUrl('data:image/png;base64,AAAA'), isNull);
  });

  test('rejects userinfo pointing elsewhere', () {
    // Uri parses the host as evil.example here, so this must not slip through.
    expect(safeImageUrl('https://ai.calcai.cc@evil.example/x.png'), isNull);
  });

  test('handles empty and malformed input', () {
    expect(safeImageUrl(null), isNull);
    expect(safeImageUrl(''), isNull);
    expect(safeImageUrl('not a url'), isNull);
    expect(safeImageUrl('::::'), isNull);
  });
}
