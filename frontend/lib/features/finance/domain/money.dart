/// Money, and the only way money enters this app.
///
/// 🔴 **Nothing here ever touches `double`.** Dart's `double` is binary
/// floating point: `0.1 + 0.2` is `0.30000000000000004`, and a sum of a
/// hundred invoice lines drifts by rupees. In a fee module that is not a
/// rounding nit — a receipt that disagrees with the ledger by one rupee
/// destroys the accountant's trust in the whole product.
///
/// So [Money] holds an integer count of **paisa**, and the only entry point
/// is [Money.parse], which reads a DECIMAL STRING with its own digit
/// scanner. There is deliberately no `Money.fromDouble`, no `toDouble`, and
/// no `num` anywhere in this file — the absence is the safety property, and
/// `finance_money_test.dart` asserts it against the file's own source text.
library;

/// An exact amount in Pakistani rupees, stored as integer paisa.
class Money implements Comparable<Money> {
  const Money.fromPaisa(this.paisa);

  /// The whole amount in paisa. 1 rupee = 100 paisa.
  final int paisa;

  static const Money zero = Money.fromPaisa(0);

  /// Reads a decimal string such as `"5500.00"`, `"0.01"` or `"-12.5"`.
  ///
  /// Returns null for anything that is not a plain decimal number, and for
  /// more than two decimal places. Refusing a third decimal is deliberate:
  /// the backend silently rounds `1.005` to `1.01`, and accepting the input
  /// would mean the app showed a number the server did not store.
  static Money? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    var i = 0;
    var negative = false;
    if (text[0] == '-' || text[0] == '+') {
      negative = text[0] == '-';
      i = 1;
    }

    var rupees = 0;
    var digits = 0;
    while (i < text.length && _isDigit(text[i])) {
      rupees = rupees * 10 + (text.codeUnitAt(i) - _zero);
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
        if (places == 2) return null; // a third decimal is not representable
        fraction = fraction * 10 + (text.codeUnitAt(i) - _zero);
        places++;
        i++;
      }
      if (i != text.length) return null;
      if (places == 1) fraction *= 10;
    }

    final total = rupees * 100 + fraction;
    return Money.fromPaisa(negative ? -total : total);
  }

  /// As [tryParse], but throws for a value that should never be malformed —
  /// a field the backend is contracted to send.
  static Money parse(String raw) {
    final value = tryParse(raw);
    if (value == null) {
      throw FormatException('Not a money value', raw);
    }
    return value;
  }

  /// Reads a money field out of an already-decoded JSON map.
  ///
  /// The value must already be a STRING — `FinanceJson.decode` quotes money
  /// keys in the raw response text before decoding, precisely so no money
  /// value is ever handed to `jsonDecode`'s number parser. A `num` arriving
  /// here means a money key was missed; that throws rather than silently
  /// going through a double.
  static Money fromJson(Object? value, {Money? fallback}) {
    if (value == null) {
      if (fallback != null) return fallback;
      throw const FormatException('A money field was missing');
    }
    if (value is String) return parse(value);
    throw FormatException(
      'A money field arrived as ${value.runtimeType} rather than a string — '
      'its key is missing from FinanceJson.moneyKeys, so it was decoded as a '
      'floating-point number.',
      '$value',
    );
  }

  Money operator +(Money other) => Money.fromPaisa(paisa + other.paisa);
  Money operator -(Money other) => Money.fromPaisa(paisa - other.paisa);

  bool get isZero => paisa == 0;
  bool get isPositive => paisa > 0;

  /// `12500.00` — the plain decimal form, for sending back to the backend.
  String toBackendString() {
    final sign = paisa < 0 ? '-' : '';
    final abs = paisa.abs();
    final rupees = abs ~/ 100;
    final fraction = abs % 100;
    return '$sign$rupees.${fraction.toString().padLeft(2, '0')}';
  }

  /// `PKR 12,500.00` — what every screen shows.
  ///
  /// Always two decimals and always thousand-separated, so a column of
  /// amounts aligns digit for digit. The type scale already renders figures
  /// tabular; this supplies the shape.
  String format() {
    final sign = paisa < 0 ? '-' : '';
    final abs = paisa.abs();
    final rupees = (abs ~/ 100).toString();
    final fraction = (abs % 100).toString().padLeft(2, '0');

    final grouped = StringBuffer();
    for (var i = 0; i < rupees.length; i++) {
      if (i > 0 && (rupees.length - i) % 3 == 0) grouped.write(',');
      grouped.write(rupees[i]);
    }
    return 'PKR $sign$grouped.$fraction';
  }

  @override
  int compareTo(Money other) => paisa.compareTo(other.paisa);

  @override
  bool operator ==(Object other) => other is Money && other.paisa == paisa;

  @override
  int get hashCode => paisa.hashCode;

  @override
  String toString() => format();

  static const int _zero = 0x30;
  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= _zero && code <= _zero + 9;
  }
}

/// Decodes a finance response so that money never reaches `jsonDecode`'s
/// number parser.
///
/// The fee API sends money as bare JSON numbers (`"total_amount":5500.00`).
/// `jsonDecode` turns those into `double` before any of our code runs, and by
/// then the exact decimal is already gone. There is no reviver that sees the
/// raw literal.
///
/// So the raw response TEXT is rewritten first: every known money key has its
/// numeric literal wrapped in quotes, and the decoder then yields a String
/// that [Money.parse] reads exactly. The repository asks dio for
/// `ResponseType.plain` so this runs on the untouched body.
abstract final class FinanceJson {
  /// Every key whose value is an amount. A key missing from this set is not
  /// a silent double: [Money.fromJson] throws when it sees a number, so the
  /// omission surfaces as a loud failure rather than a drifting total.
  static const Set<String> moneyKeys = {
    'amount',
    'subtotal',
    'total',
    'total_amount',
    'paid_amount',
    'tax_amount',
    'taxAmount',
    'discount_amount',
    'outstanding',
    'invoiced',
    'collected',
    'totalInvoiced',
    'totalCollected',
    'tax_rate',
    'effective_tax_rate',
  };

  static final RegExp _pattern = RegExp(
    '"(${moneyKeys.join('|')})"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)',
  );

  /// Quotes the money literals in [rawJson].
  ///
  /// Known limitation, stated rather than hidden: this works on the text, so
  /// a STRING value that itself contained `"amount": 12.5` would also be
  /// rewritten. No field in this API carries free-form JSON, and `reference`
  /// — the one free-text field — is only ever read, never re-parsed.
  static String quoteMoney(String rawJson) =>
      rawJson.replaceAllMapped(_pattern, (m) => '"${m[1]}":"${m[2]}"');
}
