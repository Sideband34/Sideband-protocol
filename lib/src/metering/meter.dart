import 'dart:convert';

import '../frames/amount.dart';

/// Monotonic usage meter. Pure state; no clocks, no I/O.
class UsageMeter {
  UsageMeter({required this.pricePerUnit, required this.maxUnits});

  final Amount pricePerUnit;
  final int maxUnits;
  int _units = 0;
  int _seq = 0;

  int get units => _units;
  int get seq => _seq;

  /// Amount owed for the units metered so far.
  Amount get owed => pricePerUnit.times(_units);

  /// Records [n] more units. Returns the new cumulative total.
  /// Throws if the session cap would be exceeded.
  int record(int n) {
    if (n <= 0) throw ArgumentError.value(n, 'n', 'must be positive');
    if (_units + n > maxUnits) {
      throw StateError('Session unit cap $maxUnits exceeded');
    }
    _units += n;
    _seq += 1;
    return _units;
  }
}

/// Hash-free, dependency-free sample commitment placeholder used by tests and
/// examples. Production deployments should supply a SHA-256 based function.
typedef SampleHasher = String Function(List<int> data);

String debugSampleHasher(List<int> data) =>
    base64Url.encode(data.length > 32 ? data.sublist(0, 32) : data);
