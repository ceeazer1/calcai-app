import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/widgets/ti84_screen.dart';

/// These assert parity with `paginateForTI()` / `sendPage()` in
/// `ti-84 plus/esp32/esp32.ino`. If the firmware's wrapping changes, these
/// should fail — the preview is only useful while it matches the device.
void main() {
  test('never exceeds 16 columns', () {
    final lines = wrapForTi84(
      'QUADRATIC FORMULA X EQUALS NEGATIVE B PLUS OR MINUS ROOT',
    );
    for (final l in lines) {
      expect(l.length, lessThanOrEqualTo(16), reason: 'line too wide: "$l"');
    }
  });

  test('hard-wraps mid-word like the firmware (no word wrap)', () {
    // Firmware fills 16 chars then flushes, regardless of spaces.
    expect(wrapForTi84('AREA IS BASE TIMES HEIGHT'),
        ['AREA IS BASE TIM', 'ES HEIGHT']);
  });

  test('splits long words at exactly 16', () {
    expect(wrapForTi84('SUPERCALIFRAGILISTIC'), ['SUPERCALIFRAGILI', 'STIC']);
  });

  test('preserves explicit newlines', () {
    expect(wrapForTi84('A\nB'), ['A', 'B']);
  });

  test('does not change case (firmware sanitize leaves case alone)', () {
    expect(wrapForTi84('lower Case'), ['lower Case']);
  });

  test('pages at 7 lines, matching sendPage linesPerPage', () {
    expect(paginateForTi84(List.filled(7, 'X').join('\n')).length, 1);
    final two = paginateForTi84(List.filled(8, 'X').join('\n'));
    expect(two.length, 2);
    expect(two[0].length, 7);
    expect(two[1].length, 1);
  });
}
