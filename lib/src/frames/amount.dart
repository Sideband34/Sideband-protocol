/// Fixed-point decimal amount with 7 fractional digits (Stellar stroop
/// precision). Stored as an integer so comparisons never touch floating point.
class Amount implements Comparable<Amount> {
  Amount._(this.stroops);

  static const int scale = 7;
  static final BigInt _unit = BigInt.from(10000000);

  /// Amount in 1e-7 units.
  final BigInt stroops;

  static final Amount zero = Amount._(BigInt.zero);

  /// Parses a non-negative decimal string such as `0.0010` or `12`.
  /// Rejects signs, exponents, whitespace and more than 7 fractional digits.
  factory Amount.parse(String s) {
    final m = RegExp(r'^(\d{1,18})(?:\.(\d{1,7}))?$').firstMatch(s);
    if (m == null) {
      throw FormatException('Invalid amount', s);
    }
    final whole = BigInt.parse(m.group(1)!);
    final frac = (m.group(2) ?? '').padRight(scale, '0');
    return Amount._(whole * _unit + BigInt.parse(frac));
  }

  /// Parses a non-negative decimal string, or returns `null` if [s] is invalid.
  ///
  /// Uses the same syntax rules as [Amount.parse], rejecting signs, exponents,
  /// whitespace, and more than 7 fractional digits.
  static Amount? tryParse(String s) {
    try {
      return Amount.parse(s);
    } on FormatException {
      return null;
    }
  }

  factory Amount.fromStroops(BigInt v) {
    if (v.isNegative) throw RangeError('Amount cannot be negative');
    return Amount._(v);
  }

  Amount operator +(Amount o) => Amount._(stroops + o.stroops);

  Amount operator -(Amount o) {
    final r = stroops - o.stroops;
    if (r.isNegative) throw RangeError('Amount underflow');
    return Amount._(r);
  }

  /// Multiplies by a whole number of units (e.g. price per unit * units).
  Amount times(int n) {
    if (n < 0) throw RangeError('Negative multiplier');
    return Amount._(stroops * BigInt.from(n));
  }

  bool operator >(Amount o) => stroops > o.stroops;
  bool operator >=(Amount o) => stroops >= o.stroops;
  bool operator <(Amount o) => stroops < o.stroops;
  bool operator <=(Amount o) => stroops <= o.stroops;

  @override
  int compareTo(Amount other) => stroops.compareTo(other.stroops);

  @override
  bool operator ==(Object other) => other is Amount && other.stroops == stroops;

  @override
  int get hashCode => stroops.hashCode;

  /// Canonical string: no trailing zeros beyond what is needed; always at
  /// least one integer digit.
  @override
  String toString() {
    final whole = stroops ~/ _unit;
    final frac = (stroops % _unit).toString().padLeft(scale, '0');
    final trimmed = frac.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
  }
}
