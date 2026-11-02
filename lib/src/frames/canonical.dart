import 'dart:convert';

/// Canonical JSON encoding used for frame hashing / transcripts.
///
/// Rules: object keys sorted by UTF-16 code unit, no insignificant whitespace,
/// only null/bool/int/String/List/Map allowed (no doubles: amounts are strings).
/// NOTE: this encoding is for transcript hashes and frame identity only. It is
/// NOT the signed-bytes format for payment vouchers; that is defined by
/// `sideband-channels` using the upstream Stellar canonical format.
String canonicalJson(Object? value) {
  final b = StringBuffer();
  _write(b, value);
  return b.toString();
}

List<int> canonicalBytes(Object? value) => utf8.encode(canonicalJson(value));

void _write(StringBuffer b, Object? v) {
  if (v == null) {
    b.write('null');
  } else if (v is bool) {
    b.write(v ? 'true' : 'false');
  } else if (v is int) {
    b.write(v.toString());
  } else if (v is String) {
    b.write(jsonEncode(v));
  } else if (v is List) {
    b.write('[');
    for (var i = 0; i < v.length; i++) {
      if (i > 0) b.write(',');
      _write(b, v[i]);
    }
    b.write(']');
  } else if (v is Map) {
    final keys = v.keys.map((k) {
      if (k is! String) throw ArgumentError('Non-string key: $k');
      return k;
    }).toList()
      ..sort();
    b.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) b.write(',');
      b.write(jsonEncode(keys[i]));
      b.write(':');
      _write(b, v[keys[i]]);
    }
    b.write('}');
  } else {
    throw ArgumentError('Unsupported type in canonical JSON: ${v.runtimeType}');
  }
}
