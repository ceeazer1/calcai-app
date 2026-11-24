import 'dart:convert';

// Keep the order aligned with calculator/ti_text.h from signed firmware 1.4.8.
// The preview transforms a display copy; the saved note remains unchanged.
const _ti84Replacements = <String, String>{
  '\r\n': '\n',
  '\r': '\n',
  '‘': "'",
  '’': "'",
  '“': '"',
  '”': '"',
  '–': '-',
  '—': '-',
  '−': '-',
  '…': '...',
  '`': "'",
  '×': '*',
  '÷': '/',
  '⋅': '*',
  '·': '*',
  '≠': '!=',
  '≤': '<=',
  '≥': '>=',
  '≈': '~=',
  '∞': 'inf',
  '→': '->',
  '←': '<-',
  '↔': '<->',
  '√': 'sqrt',
  'π': 'pi',
  '°': ' deg',
  '±': '+/-',
  '¼': '1/4',
  '½': '1/2',
  '¾': '3/4',
  'α': 'alpha',
  'β': 'beta',
  'γ': 'gamma',
  'δ': 'delta',
  'θ': 'theta',
  'μ': 'mu',
  'Σ': 'Sigma',
  '∑': 'sum',
  '∫': 'int',
  '∈': ' in ',
  '∩': ' intersect ',
  '∪': ' union ',
  '⁰': '^0',
  '¹': '^1',
  '²': '^2',
  '³': '^3',
  '⁴': '^4',
  '⁵': '^5',
  '⁶': '^6',
  '⁷': '^7',
  '⁸': '^8',
  '⁹': '^9',
  '⁻': '^-',
  '⁺': '^+',
  '•': '- ',
  '●': '- ',
  '\t': '  ',
};

/// Matches the firmware's ordered Unicode replacement and ASCII byte filter.
String sanitizeForTi84(String text) {
  var value = text;
  for (final entry in _ti84Replacements.entries) {
    value = value.replaceAll(entry.key, entry.value);
  }
  while (value.contains('  ')) {
    value = value.replaceAll('  ', ' ');
  }
  for (final marker in ['```', '~~~', '\u200B', '\u200C', '\u200D', '\uFEFF']) {
    value = value.replaceAll(marker, '');
  }

  final out = StringBuffer();
  // Arduino String iterates UTF-8 bytes. An unmapped multi-byte character
  // therefore produces one '?' per byte, not one per Unicode code point.
  for (final byte in utf8.encode(value)) {
    if (byte == 10) {
      out.write('\n');
    } else if (byte >= 32) {
      out.writeCharCode(byte > 126 ? 63 : byte);
    }
  }
  return out.toString();
}

int _matchingBrace(String value, int open) {
  if (open < 0 || open >= value.length || value[open] != '{') return -1;
  var depth = 0;
  for (var i = open; i < value.length; i++) {
    if (value[i] == '{') depth++;
    if (value[i] == '}' && --depth == 0) return i;
  }
  return -1;
}

String _replaceBraced(
  String value,
  String marker,
  String prefix,
  String suffix,
) {
  var index = value.indexOf(marker);
  while (index >= 0) {
    final open = index + marker.length - 1;
    final close = _matchingBrace(value, open);
    if (close < 0) {
      index = value.indexOf(marker, index + marker.length);
      continue;
    }
    final inner = value.substring(open + 1, close);
    value =
        '${value.substring(0, index)}$prefix$inner$suffix'
        '${value.substring(close + 1)}';
    index = value.indexOf(marker);
  }
  return value;
}

String _replaceFractions(String value, String marker) {
  var index = value.indexOf(marker);
  while (index >= 0) {
    final after = index + marker.length;
    final numeratorClose = _matchingBrace(value, after);
    final denominatorOpen = numeratorClose + 1;
    final denominatorClose = numeratorClose < 0
        ? -1
        : _matchingBrace(value, denominatorOpen);
    if (numeratorClose < 0 || denominatorClose < 0) {
      index = value.indexOf(marker, after);
      continue;
    }
    final numerator = value.substring(after + 1, numeratorClose);
    final denominator = value.substring(denominatorOpen + 1, denominatorClose);
    value =
        '${value.substring(0, index)}($numerator)/($denominator)'
        '${value.substring(denominatorClose + 1)}';
    index = value.indexOf(marker);
  }
  return value;
}

/// Matches only the simple LaTeX forms supported by the firmware text path.
/// This is not the calculator's separate image-based answer renderer.
String normalizeLatexForTi84(String text) {
  var value = text;
  const commands = <String, String>{
    r'\times': '×',
    r'\cdot': '·',
    r'\div': '÷',
    r'\pi': 'pi',
    r'\leq': '≤',
    r'\le': '≤',
    r'\geq': '≥',
    r'\ge': '≥',
    r'\neq': '≠',
    r'\pm': '±',
    r'\infty': '∞',
  };
  for (final entry in commands.entries) {
    value = value.replaceAll(entry.key, entry.value);
  }
  value = _replaceBraced(value, r'\sqrt{', 'sqrt(', ')');
  value = _replaceBraced(value, 'sqrt{', 'sqrt(', ')');
  value = _replaceBraced(value, '^{', '^', '');
  value = _replaceFractions(value, r'\frac');
  return _replaceFractions(value, 'frac');
}

/// The calculator normalizes simple math before sanitizing and wrapping it.
String prepareForTi84(String text) =>
    sanitizeForTi84(normalizeLatexForTi84(text));
