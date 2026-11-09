import 'package:sideband_protocol/sideband_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Amount', () {
    test('parses and prints canonically', () {
      expect(Amount.parse('0.0010').toString(), '0.001');
      expect(Amount.parse('12').toString(), '12');
      expect(Amount.parse('0.0000001').stroops, BigInt.one);
    });
    test('rejects bad input', () {
      for (final s in [
        '-1',
        '1e3',
        ' 1',
        '1.',
        '.5',
        '0.00000001',
        '',
        'abc'
      ]) {
        expect(() => Amount.parse(s), throwsFormatException, reason: s);
      }
    });
    test('tryParse returns Amount for valid input and null for invalid', () {
      expect(Amount.tryParse('0.0010000'), Amount.parse('0.0010000'));
      expect(Amount.tryParse('12'), Amount.parse('12'));
      expect(Amount.tryParse('0.0000001')?.stroops, BigInt.one);

      for (final s in [
        '',
        '-1',
        '0.00000001',
        '1e3',
        'abc',
        ' 1',
        '1.',
        '.5',
      ]) {
        expect(Amount.tryParse(s), isNull, reason: 'Expected null for $s');
      }
    });
    test('arithmetic is exact', () {
      final p = Amount.parse('0.0001');
      expect(p.times(10), Amount.parse('0.001'));
      expect(Amount.parse('1') - Amount.parse('0.9999999'),
          Amount.parse('0.0000001'));
      expect(() => Amount.parse('1') - Amount.parse('2'), throwsRangeError);
    });
  });
}
