/// Exact decimals for marks, percentages and grade points.
///
/// The backend sends these as JSON numbers with two decimals — `85.50`,
/// `3.70`, `100.00` — exactly as it sends money. `jsonDecode` turns those
/// into `double` before any of our code runs, and a mark that renders as
/// `17.999999` on a report card is the same class of defect as a rupee of
/// drift in a ledger: the number looks authoritative and is wrong.
///
/// So marks get the same treatment as money: an integer count of
/// hundredths, parsed from the decimal STRING with this file's own scanner.
/// There is deliberately no `double` anywhere in this file, and
/// `academics_test.dart` asserts that against its own source.
///
/// ## Why this is not `Money`
///
/// [Money] is the same idea with a different unit and a different job: it
/// formats as `PKR 12,500.00` and always shows two decimals, because an
/// amount with a trailing `.00` is what an accountant expects. A mark of 85
/// should read `85`, not `PKR 85.00`, and 62.5% should read `62.5%`.
///
/// The two types are kept apart rather than shared because neither feature
/// should depend on the other, and `lib/core/` is limited to
/// `{theme, network, db, router, widgets}` by the project's folder rule —
/// none of which a decimal type belongs in. Flagged in HANDOFF.md as a
/// candidate for extraction if a third feature ever needs it.
library;

/// A number with at most two decimal places, stored as integer hundredths.
class Marks implements Comparable<Marks> {
  const Marks.fromHundredths(this.hundredths);

  /// The value in hundredths. 85.5 is 8550.
  final int hundredths;

  static const Marks zero = Marks.fromHundredths(0);

  /// Reads a decimal string such as `"85.50"`, `"62.5"` or `"100"`.
  ///
  /// Returns null for anything that is not a plain decimal, and for more
  /// than two decimal places — the backend stores two, and accepting a
  /// third would mean showing a number it did not keep.
  static Marks? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    var i = 0;
    var negative = false;
    if (text[0] == '-' || text[0] == '+') {
      negative = text[0] == '-';
      i = 1;
    }

    var whole = 0;
    var digits = 0;
    while (i < text.length && _isDigit(text[i])) {
      whole = whole * 10 + (text.codeUnitAt(i) - _zero);
      digits++;
      i++;
    }
    if (digits == 0) return null;

    var fraction = 0;
    if (i < text.length) {
      if (text[i] != '.') return null;
      i++;
      var places = 0;
      while (i < text.length && _isDigit(text[i])) {
        if (places == 2) return null;
        fraction = fraction * 10 + (text.codeUnitAt(i) - _zero);
        places++;
        i++;
      }
      if (i != text.length) return null;
      if (places == 1) fraction *= 10;
    }

    final total = whole * 100 + fraction;
    return Marks.fromHundredths(negative ? -total : total);
  }

  static Marks parse(String raw) {
    final value = tryParse(raw);
    if (value == null) throw FormatException('Not a mark', raw);
    return value;
  }

  /// Reads a field that `AcademicJson.quoteNumbers` has already turned into
  /// a string. A `num` arriving here means the key is missing from
  /// `AcademicJson.numericKeys`, so it went through a double — that throws
  /// rather than silently becoming a mark.
  static Marks fromJson(Object? value, {Marks? fallback}) {
    if (value == null) {
      if (fallback != null) return fallback;
      throw const FormatException('A numeric field was missing');
    }
    if (value is String) return parse(value);
    throw FormatException(
      'A mark arrived as ${value.runtimeType} rather than a string — its key '
      'is missing from AcademicJson.numericKeys, so it was decoded as a '
      'floating-point number.',
      '$value',
    );
  }

  Marks operator +(Marks other) =>
      Marks.fromHundredths(hundredths + other.hundredths);

  bool get isZero => hundredths == 0;

  /// `85.5` — the plain decimal, for sending back to the backend.
  String toBackendString() {
    final sign = hundredths < 0 ? '-' : '';
    final abs = hundredths.abs();
    return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  /// `85`, `85.5`, `85.25` — trailing zeros dropped, because a mark out of
  /// 100 reads as a whole number and `85.00` is noise on a report card.
  String format() {
    final sign = hundredths < 0 ? '-' : '';
    final abs = hundredths.abs();
    final whole = abs ~/ 100;
    final fraction = abs % 100;
    if (fraction == 0) return '$sign$whole';
    if (fraction % 10 == 0) return '$sign$whole.${fraction ~/ 10}';
    return '$sign$whole.${fraction.toString().padLeft(2, '0')}';
  }

  /// `62.5%`
  String formatPercent() => '${format()}%';

  @override
  int compareTo(Marks other) => hundredths.compareTo(other.hundredths);

  @override
  bool operator ==(Object other) =>
      other is Marks && other.hundredths == hundredths;

  @override
  int get hashCode => hundredths.hashCode;

  @override
  String toString() => format();

  static const int _zero = 0x30;
  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= _zero && code <= _zero + 9;
  }
}

/// Decodes an academic response so marks never reach `jsonDecode`'s number
/// parser. Same mechanism as `FinanceJson`, for the same reason.
abstract final class AcademicJson {
  /// Every key whose value is a two-decimal number.
  static const Set<String> numericKeys = {
    'marks_obtained',
    'max_marks',
    'passing_marks',
    'total_marks',
    'total_max',
    'percentage',
    'grade_point',
    'weightage',
  };

  static final RegExp _pattern = RegExp(
    '"(${numericKeys.join('|')})"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)',
  );

  static String quoteNumbers(String rawJson) =>
      rawJson.replaceAllMapped(_pattern, (m) => '"${m[1]}":"${m[2]}"');
}
