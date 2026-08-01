/// Turns the calculator's LaTeX answers into something readable in the app.
///
/// The calculator renders answers as images, so the worker asks the model for
/// LaTeX and logs that LaTeX verbatim (`type: 'render'` / `'render-image'`).
/// Shown raw in History that reads as `$$d=\sqrt{9+16}$$` — correct, but not
/// what anyone wants to skim on a phone.
///
/// This runs **entirely on the phone at display time**, over data that has
/// already been fetched. It is pure string work: no network call, no server
/// round trip, and nothing on the path between the calculator and the answer.
/// The wait on the calculator is exactly what it was.
///
/// The grammar is small and known — it's whatever `BASE_V2` in the worker's
/// prompt permits — so this handles that subset exactly and degrades safely on
/// anything else: an unknown `\command{body}` collapses to `body` rather than
/// leaking a backslash into the UI.
library;

/// Figure directives from the prompt's FIGURES list, mapped to a plain label.
///
/// The user reading History wants to know *that* there was a graph, not to
/// decode `\riemann{x^2}{0}{3}{6}`. The calculator drew the real thing.
const Map<String, String> _figureLabels = {
  'plot': 'Graph',
  'numline': 'Number line',
  'bar': 'Bar chart',
  'scatter': 'Scatter plot',
  'line': 'Line of fit',
  'hist': 'Histogram',
  'rtriangle': 'Triangle',
  'triangle': 'Triangle',
  'circle': 'Circle',
  'ellipse': 'Ellipse',
  'hyperbola': 'Hyperbola',
  'polar': 'Polar graph',
  'param': 'Parametric graph',
  'vector': 'Vector diagram',
  'unitcircle': 'Unit circle',
  'boxplot': 'Box plot',
  'slopefield': 'Slope field',
  'area': 'Area under curve',
  'riemann': 'Riemann sum',
};

/// Greek letters and operators worth showing as real characters.
const Map<String, String> _symbols = {
  r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ',
  r'\Delta': 'Δ', r'\theta': 'θ', r'\lambda': 'λ', r'\mu': 'μ',
  r'\pi': 'π', r'\sigma': 'σ', r'\Sigma': 'Σ', r'\phi': 'φ',
  r'\omega': 'ω', r'\Omega': 'Ω', r'\infty': '∞',
  r'\cdot': '·', r'\times': '×', r'\div': '÷', r'\pm': '±', r'\mp': '∓',
  r'\le': '≤', r'\leq': '≤', r'\ge': '≥', r'\geq': '≥', r'\ne': '≠',
  r'\neq': '≠', r'\approx': '≈', r'\equiv': '≡', r'\propto': '∝',
  r'\rightarrow': '→', r'\to': '→', r'\Rightarrow': '⇒',
  r'\leftarrow': '←', r'\int': '∫', r'\sum': '∑', r'\prod': '∏',
  r'\partial': '∂', r'\degree': '°', r'\circ': '°',
  r'\in': '∈', r'\subset': '⊂', r'\cup': '∪', r'\cap': '∩',
  r'\angle': '∠', r'\perp': '⊥', r'\parallel': '∥',
  r'\quad': ' ', r'\qquad': '  ', r'\,': ' ', r'\;': ' ', r'\!': '',
  // \left / \right are followed by a bare delimiter (not a group), so dropping
  // the command alone is right — the "(" that follows is kept.
  r'\left': '', r'\right': '', r'\displaystyle': '',
};

/// Commands that only style their argument. Their body is the content, so it
/// is kept and the wrapper dropped — \text{Roots: } must not leave braces
/// behind in the UI.
const Set<String> _passthroughCommands = {
  'text', 'textrm', 'textbf', 'textit', 'mathrm', 'mathbf', 'mathit',
  'mathsf', 'mathcal', 'operatorname', 'boxed',
};

const Map<String, String> _superscripts = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', 'n': 'ⁿ', 'i': 'ⁱ',
};

const Map<String, String> _subscripts = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
};

/// Reads a `{...}` group starting at [open] (which must index the `{`).
/// Returns the body and the index just past the matching `}`, honouring
/// nesting so `\frac{\sqrt{2}}{3}` splits correctly.
({String body, int end})? _group(String s, int open) {
  if (open >= s.length || s[open] != '{') return null;
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '{') depth++;
    if (s[i] == '}') {
      depth--;
      if (depth == 0) return (body: s.substring(open + 1, i), end: i + 1);
    }
  }
  return null; // Unbalanced — caller falls back to literal text.
}

/// Collects the [count] consecutive `{...}` groups that follow [i].
({List<String> args, int end}) _groups(String s, int i, int count) {
  final args = <String>[];
  var p = i;
  for (var n = 0; n < count; n++) {
    while (p < s.length && s[p] == ' ') {
      p++;
    }
    final g = _group(s, p);
    if (g == null) break;
    args.add(g.body);
    p = g.end;
  }
  return (args: args, end: p);
}

/// True if [line] is nothing but a figure directive, so the caption line the
/// prompt puts directly above it isn't duplicated by our own label.
bool _isFigureOnly(String line) {
  final t = line.trim();
  if (!t.startsWith(r'\')) return false;
  final m = RegExp(r'^\\([a-zA-Z]+)').firstMatch(t);
  return m != null && _figureLabels.containsKey(m.group(1));
}

/// Converts one line of LaTeX math to readable plain text.
String _convert(String input) {
  final out = StringBuffer();
  var i = 0;

  while (i < input.length) {
    final c = input[i];

    // $$ ... $$ / $ ... $ delimiters carry no meaning once we're plain text.
    if (c == r'$') {
      i++;
      if (i < input.length && input[i] == r'$') i++;
      continue;
    }

    if (c != r'\') {
      // Superscript / subscript: x^2 -> x², a_1 -> a₁.
      if ((c == '^' || c == '_') && i + 1 < input.length) {
        final table = c == '^' ? _superscripts : _subscripts;
        final g = _group(input, i + 1);
        final body = g != null ? g.body : input[i + 1];
        final next = g != null ? g.end : i + 2;
        // Only use real superscript glyphs when every character maps; a
        // partial mapping (x^{n+1}) is less legible than plain x^(n+1).
        if (body.isNotEmpty && body.split('').every(table.containsKey)) {
          out.write(body.split('').map((ch) => table[ch]).join());
        } else {
          out.write(body.length == 1 ? '$c$body' : '$c($body)');
        }
        i = next;
        continue;
      }
      // Braces are LaTeX grouping, never content — never show them.
      if (c == '{' || c == '}') {
        i++;
        continue;
      }
      out.write(c);
      i++;
      continue;
    }

    // A command: \name possibly followed by {groups}.
    final m = RegExp(r'^\\([a-zA-Z]+)').firstMatch(input.substring(i));
    if (m == null) {
      // Escaped punctuation like \{ or \% — emit the character itself.
      if (i + 1 < input.length) {
        out.write(input[i + 1]);
        i += 2;
      } else {
        i++;
      }
      continue;
    }

    final name = m.group(1)!;
    var p = i + m.group(0)!.length;

    if (_passthroughCommands.contains(name)) {
      final g = _group(input, p);
      if (g != null) {
        out.write(_convert(g.body));
        i = g.end;
        continue;
      }
    }

    // Problem number: \qlabel{4} -> "4."
    if (name == 'qlabel') {
      final g = _groups(input, p, 1);
      if (g.args.isNotEmpty) {
        out.write('${g.args[0]}.');
        i = g.end;
        continue;
      }
    }

    // A figure the calculator drew — name it, don't transcribe it.
    if (_figureLabels.containsKey(name)) {
      // Consume every trailing group so no argument text leaks out.
      var q = p;
      while (true) {
        final g = _group(input, q);
        if (g == null) break;
        q = g.end;
      }
      out.write('[${_figureLabels[name]}]');
      i = q;
      continue;
    }

    if (name == 'frac' || name == 'dfrac' || name == 'tfrac') {
      final g = _groups(input, p, 2);
      if (g.args.length == 2) {
        final num = _convert(g.args[0]);
        final den = _convert(g.args[1]);
        // Parenthesise compound parts so a/b+c never reads ambiguously.
        final n = _needsParens(num) ? '($num)' : num;
        final d = _needsParens(den) ? '($den)' : den;
        out.write('$n/$d');
        i = g.end;
        continue;
      }
    }

    if (name == 'sqrt') {
      // Optional index: \sqrt[3]{8} -> ∛8
      var radical = '√';
      if (p < input.length && input[p] == '[') {
        final close = input.indexOf(']', p);
        if (close > 0) {
          final idx = input.substring(p + 1, close).trim();
          if (idx == '3') radical = '∛';
          if (idx == '4') radical = '∜';
          p = close + 1;
        }
      }
      final g = _groups(input, p, 1);
      if (g.args.isNotEmpty) {
        final body = _convert(g.args[0]);
        out.write(_needsParens(body) ? '$radical($body)' : '$radical$body');
        i = g.end;
        continue;
      }
    }

    // Function names read fine as themselves.
    const functions = {
      'sin', 'cos', 'tan', 'csc', 'sec', 'cot', 'arcsin', 'arccos', 'arctan',
      'log', 'ln', 'exp', 'lim', 'max', 'min', 'det', 'gcd', 'mod',
    };
    if (functions.contains(name)) {
      out.write(name);
      i = p;
      continue;
    }

    final sym = _symbols[r'\' + name];
    if (sym != null) {
      out.write(sym);
      i = p;
      // \text{...} and \left/\right keep their body, so fall through to let
      // the group be processed as ordinary text.
      continue;
    }

    // Unknown command: keep the meaning, drop the notation. \boxed{42} -> 42.
    final g = _group(input, p);
    if (g != null) {
      out.write(_convert(g.body));
      i = g.end;
      continue;
    }

    // Bare unknown command with no argument — drop it silently.
    i = p;
  }

  return out.toString();
}

/// Whether [s] needs wrapping before being joined with / or √.
bool _needsParens(String s) {
  final t = s.trim();
  if (t.length <= 1) return false;
  return t.contains(RegExp(r'[+\-*/ ]'));
}

final Map<String, String> _cache = {};

/// Renders a logged LaTeX answer as readable text.
///
/// Cheap enough to call from a list builder; results are memoised because
/// History rebuilds the same handful of entries as the user scrolls.
String latexToReadable(String raw) {
  if (raw.isEmpty) return '';
  final hit = _cache[raw];
  if (hit != null) return hit;

  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final out = <String>[];

  for (var n = 0; n < lines.length; n++) {
    final line = lines[n];
    if (line.trim().isEmpty) {
      if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
      continue;
    }

    // The prompt puts a 2-4 word caption directly before each figure. That
    // caption already says "Parabola opening upward", so our own [Graph]
    // label right after it would just be noise — keep the caption, drop the
    // label, and show them as one line.
    if (n + 1 < lines.length && _isFigureOnly(lines[n + 1]) &&
        !line.trim().startsWith(r'\') && !line.contains(r'$')) {
      final label = _convert(lines[n + 1]).trim();
      out.add('${line.trim()} $label'.trim());
      n++; // consume the directive line
      continue;
    }

    final converted = _convert(line).trim();
    if (converted.isNotEmpty) out.add(converted);
  }

  // Collapse runs of blank lines and trim the ends.
  final text = out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

  // Keep the cache from growing without bound over a long session.
  if (_cache.length > 200) _cache.clear();
  _cache[raw] = text;
  return text;
}
