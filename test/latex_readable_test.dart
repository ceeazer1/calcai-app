import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/utils/latex_readable.dart';

void main() {
  group('math becomes readable', () {
    test('strips the math delimiters', () {
      expect(latexToReadable(r'$$V=113.1$$'), 'V=113.1');
    });

    test('square roots', () {
      expect(latexToReadable(r'$$d=\sqrt{25}$$'), 'd=√25');
      expect(latexToReadable(r'$$d=\sqrt{9+16}$$'), 'd=√(9+16)');
      expect(latexToReadable(r'$$\sqrt[3]{8}$$'), '∛8');
    });

    test('fractions parenthesise compound parts only', () {
      expect(latexToReadable(r'$$\frac{1}{2}$$'), '1/2');
      expect(latexToReadable(r'$$\frac{x+1}{2}$$'), '(x+1)/2');
    });

    test('nested fraction inside a root', () {
      expect(latexToReadable(r'$$\sqrt{\frac{1}{4}}$$'), '√(1/4)');
    });

    test('superscripts and subscripts', () {
      expect(latexToReadable(r'$$x^2+y^2=r^2$$'), 'x²+y²=r²');
      expect(latexToReadable(r'$$a_1+a_2$$'), 'a₁+a₂');
    });

    test('exponents use real glyphs when every character maps', () {
      expect(latexToReadable(r'$$x^{n+1}$$'), 'xⁿ⁺¹');
    });

    test('a partly-mappable exponent falls back to parens, not mixed glyphs', () {
      // 'a' has no superscript glyph, so x^(2a) beats a half-raised "x²a".
      expect(latexToReadable(r'$$x^{2a}$$'), 'x^(2a)');
    });

    test('greek and operators', () {
      expect(latexToReadable(r'$$A=\pi r^2$$'), 'A=π r²');
      expect(latexToReadable(r'$$3 \times 4 \le 12$$'), '3 × 4 ≤ 12');
    });

    test('problem numbers', () {
      expect(latexToReadable('\\qlabel{4}\n\$\$x=2\$\$'), '4.\nx=2');
    });
  });

  group('figures are named, not transcribed', () {
    test('a bare plot becomes a label', () {
      expect(latexToReadable(r'\plot{x^2}'), '[Graph]');
    });

    test('every argument is consumed', () {
      expect(latexToReadable(r'\plot{x^2}{-3}{3}'), '[Graph]');
      expect(latexToReadable(r'\riemann{x^2}{0}{3}{6}'), '[Riemann sum]');
    });

    test('each directive gets its own label', () {
      expect(latexToReadable(r'\numline{x>2}'), '[Number line]');
      expect(latexToReadable(r'\boxplot{2,5,6,7}'), '[Box plot]');
      expect(latexToReadable(r'\unitcircle{45}'), '[Unit circle]');
    });

    test('the prompt caption above a figure is kept on one line', () {
      expect(
        latexToReadable('Parabola opening upward\n\\plot{x^2}'),
        'Parabola opening upward [Graph]',
      );
    });
  });

  group('degrades safely', () {
    test('unknown command keeps its body', () {
      expect(latexToReadable(r'$$\boxed{42}$$'), '42');
    });

    test('unknown bare command is dropped, not leaked', () {
      final out = latexToReadable(r'$$x \foo y$$');
      expect(out.contains(r'\'), isFalse);
      expect(out, 'x  y');
    });

    test('unbalanced braces do not throw or hang', () {
      expect(() => latexToReadable(r'$$\frac{1}{$$'), returnsNormally);
      expect(() => latexToReadable(r'$$\sqrt{$$'), returnsNormally);
    });

    test('a styling command keeps its body and leaves no braces', () {
      expect(latexToReadable(r'$$\text{Roots: } x=\pm 2$$'), 'Roots:  x=± 2');
    });

    test('no bare grouping braces ever reach the UI', () {
      final out = latexToReadable(r'$$\text{a}{b}\mathrm{c}$$');
      expect(out.contains('{'), isFalse);
      expect(out.contains('}'), isFalse);
    });

    test('empty input', () {
      expect(latexToReadable(''), '');
    });

    test('plain prose passes through untouched', () {
      expect(latexToReadable('The ball lands after 3 seconds.'),
          'The ball lands after 3 seconds.');
    });

    test('no backslashes survive a realistic multi-line answer', () {
      const raw = r'''\qlabel{1}
$$d=\sqrt{(x_2-x_1)^2+(y_2-y_1)^2}$$
$$d=\sqrt{9+16}$$
$$d=5$$
Parabola opening upward
\plot{x^2}{-3}{3}''';
      final out = latexToReadable(raw);
      expect(out.contains(r'\'), isFalse);
      expect(out.contains(r'$'), isFalse);
      expect(out, contains('d=5'));
      expect(out, contains('[Graph]'));
      expect(out.split('\n').first, '1.');
    });
  });

  test('repeated calls are stable (memoisation is not lossy)', () {
    const raw = r'$$\frac{x+1}{2}$$';
    expect(latexToReadable(raw), latexToReadable(raw));
  });
}
