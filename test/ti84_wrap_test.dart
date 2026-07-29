import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/widgets/ti84_screen.dart';

void main() {
  test('never exceeds 16 columns', () {
    final lines = wrapForTi84(
      'QUADRATIC FORMULA X EQUALS NEGATIVE B PLUS OR MINUS ROOT',
    );
    for (final l in lines) {
      expect(l.length, lessThanOrEqualTo(16), reason: 'line too wide: "$l"');
    }
  });

  test('breaks on spaces, not mid-word', () {
    expect(wrapForTi84('AREA IS BASE TIMES HEIGHT'),
        ['AREA IS BASE', 'TIMES HEIGHT']);
  });

  test('hard-splits words longer than a row', () {
    expect(wrapForTi84('SUPERCALIFRAGILISTIC'), ['SUPERCALIFRAGILI', 'STIC']);
  });

  test('preserves explicit newlines', () {
    expect(wrapForTi84('A\nB'), ['A', 'B']);
  });
}
