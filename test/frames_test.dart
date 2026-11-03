import 'package:sideband_protocol/sideband_protocol.dart';
import 'package:test/test.dart';

ServiceOffer offer() => ServiceOffer(
      session: 's1',
      serviceId: 'caption-demo',
      providerPublicKey: 'GPROVIDER',
      pricePerUnit: Amount.parse('0.0001'),
      unit: 'second',
      currency: 'TEST_ASSET',
      network: 'testnet',
      maxSessionUnits: 200,
      expiresAt: 2000,
    );

void main() {
  test('canonical JSON sorts keys and has no whitespace', () {
    expect(
        canonicalJson({
          'b': 1,
          'a': [true, null, 'x']
        }),
        '{"a":[true,null,"x"],"b":1}');
  });
  test('canonical JSON rejects doubles', () {
    expect(() => canonicalJson({'a': 1.5}), throwsArgumentError);
  });
  test('golden service_offer encoding is stable', () {
    expect(
      offer().encode(),
      '{"currency":"TEST_ASSET","expiresAt":2000,"maxSessionUnits":200,'
      '"network":"testnet","pricePerUnit":"0.0001","providerPublicKey":"GPROVIDER",'
      '"serviceId":"caption-demo","session":"s1","type":"service_offer","unit":"second","v":1}',
    );
  });
  test('round trip all frame types', () {
    final frames = <Frame>[
      offer(),
      SessionAccept(
          session: 's1',
          channelRef: 'C1',
          maxSpend: Amount.parse('0.02'),
          nonce: 'n1'),
      const MeterSample(
          session: 's1', seq: 1, cumulativeUnits: 10, sampleHash: 'h'),
      VoucherFrame(
          session: 's1',
          channelRef: 'C1',
          cumulativeAmount: Amount.parse('0.001'),
          commitment: 'c',
          signature: 'sig'),
      const SessionClose(session: 's1', reason: 'done'),
      const ErrorFrame(session: 's1', code: 'x', message: 'y'),
    ];
    for (final f in frames) {
      expect(Frame.decode(f.encode()).encode(), f.encode());
    }
  });
  test('rejects wrong version, unknown type, bad fields, oversize', () {
    expect(
        () => Frame.decode(
            '{"type":"error","v":3,"session":"s","code":"x","message":"y"}'),
        throwsA(isA<FrameException>().having(
            (e) => e.message, 'message', contains('Unsupported protocol'))));
    expect(
        () => Frame.decode(
            '{"type":"error","v":"2","session":"s","code":"x","message":"y"}'),
        throwsA(isA<FrameException>()));
    expect(() => Frame.decode('{"type":"zzz","v":1,"session":"s"}'),
        throwsA(isA<FrameException>()));
    expect(() => Frame.decode('not json'), throwsA(isA<FrameException>()));
    expect(() => Frame.decode('[]'), throwsA(isA<FrameException>()));
    expect(
      () => Frame.decode(
          '{"type":"meter_sample","v":1,"session":"s","seq":-1,"cumulativeUnits":1,"sampleHash":"h"}'),
      throwsA(isA<FrameException>()),
    );
    expect(
      () => Frame.decode(
          '{"type":"voucher","v":1,"session":"s","channelRef":"c","cumulativeAmount":"1e3","commitment":"c","signature":"s"}'),
      throwsA(isA<FrameException>()),
    );
    expect(() => Frame.decode('x' * (maxFrameBytes + 1)),
        throwsA(isA<FrameException>()));
  });

  group('v2 session_accept baseline', () {
    SessionAccept acc(String baseline) => SessionAccept(
        session: 's1',
        channelRef: 'C1',
        maxSpend: Amount.parse('0.02'),
        nonce: 'n1',
        baseline: Amount.parse(baseline));

    test('zero baseline stays byte-identical to v1', () {
      expect(
        acc('0').encode(),
        '{"channelRef":"C1","maxSpend":"0.02","nonce":"n1",'
        '"session":"s1","type":"session_accept","v":1}',
      );
    });
    test('non-zero baseline encodes as v2 with a canonical amount', () {
      final enc = acc('0.015').encode();
      expect(
        enc,
        '{"baseline":"0.015","channelRef":"C1","maxSpend":"0.02","nonce":"n1",'
        '"session":"s1","type":"session_accept","v":2}',
      );
      final back = Frame.decode(enc) as SessionAccept;
      expect(back.baseline, Amount.parse('0.015'));
      expect(back.version, 2);
    });
    test('v1 decodes with a zero baseline; v1 + baseline is rejected', () {
      final v1 = Frame.decode(
              '{"type":"session_accept","v":1,"session":"s","channelRef":"C","maxSpend":"1","nonce":"n"}')
          as SessionAccept;
      expect(v1.baseline, Amount.zero);
      expect(
          () => Frame.decode(
              '{"type":"session_accept","v":1,"session":"s","channelRef":"C","maxSpend":"1","nonce":"n","baseline":"1"}'),
          throwsA(isA<FrameException>()));
    });
    test('v2 session_accept requires a valid baseline', () {
      for (final b in ['', '"-1"', '"1e3"', '"x"']) {
        final field = b.isEmpty ? '' : ',"baseline":$b';
        expect(
            () => Frame.decode(
                '{"type":"session_accept","v":2,"session":"s","channelRef":"C","maxSpend":"1","nonce":"n"$field}'),
            throwsA(isA<FrameException>()),
            reason: 'baseline $b');
      }
    });
    test('other frame types decode under v2 unchanged', () {
      final f = Frame.decode(
          '{"type":"session_close","v":2,"session":"s","reason":"done"}');
      expect(f, isA<SessionClose>());
      expect(f.encode(), contains('"v":1'));
    });
  });
}
