import 'package:sideband_protocol/sideband_protocol.dart';
import 'package:test/test.dart';

final policy = PayerPolicy(
  expectedNetwork: 'testnet',
  expectedCurrency: 'TEST_ASSET',
  maxPricePerUnit: Amount.parse('0.001'),
  trustedProviderKeys: {'GPROVIDER'},
);

ServiceOffer offer(
        {String network = 'testnet',
        int exp = 2000,
        String key = 'GPROVIDER',
        String price = '0.0001'}) =>
    ServiceOffer(
      session: 's1',
      serviceId: 'caption-demo',
      providerPublicKey: key,
      pricePerUnit: Amount.parse(price),
      unit: 'second',
      currency: 'TEST_ASSET',
      network: network,
      maxSessionUnits: 200,
      expiresAt: exp,
    );

SessionAccept accept(
        {String ch = 'C1',
        String max = '0.02',
        String nonce = 'n1',
        String baseline = '0'}) =>
    SessionAccept(
        session: 's1',
        channelRef: ch,
        maxSpend: Amount.parse(max),
        nonce: nonce,
        baseline: Amount.parse(baseline));

VoucherFrame voucher(String amt, {String ch = 'C1', String session = 's1'}) =>
    VoucherFrame(
        session: session,
        channelRef: ch,
        cumulativeAmount: Amount.parse(amt),
        commitment: 'c',
        signature: 's');

void expectCode(void Function() f, String code) => expect(
      f,
      throwsA(isA<SessionViolation>().having((e) => e.code, 'code', code)),
    );

SessionMachine providerActive() {
  final m = SessionMachine(sessionId: 's1', now: () => 1000)
    ..sendOffer(offer());
  m.receiveAccept(accept(), knownChannelRefs: {'C1'});
  return m;
}

void main() {
  group('payer validation of offer', () {
    SessionMachine m() => SessionMachine(sessionId: 's1', now: () => 1000);
    test('accepts good offer', () {
      final x = m()..receiveOffer(offer(), policy);
      expect(x.phase, SessionPhase.offered);
    });
    test(
        'wrong network',
        () => expectCode(
            () => m().receiveOffer(offer(network: 'public'), policy),
            'wrong_network'));
    test(
        'stale offer',
        () => expectCode(
            () => m().receiveOffer(offer(exp: 1000), policy), 'stale_offer'));
    test(
        'untrusted provider',
        () => expectCode(() => m().receiveOffer(offer(key: 'GEVIL'), policy),
            'untrusted_provider'));
    test(
        'price too high',
        () => expectCode(() => m().receiveOffer(offer(price: '0.01'), policy),
            'price_too_high'));
  });

  group('provider side', () {
    test('refuses paid session without funded channel', () {
      final m = SessionMachine(sessionId: 's1', now: () => 1000)
        ..sendOffer(offer());
      expectCode(() => m.receiveAccept(accept(), knownChannelRefs: {}),
          'no_funded_channel');
    });
    test('rejects replayed nonce across accepts', () {
      final m = providerActive();
      expect(m.phase, SessionPhase.active);
      expectCode(() => m.receiveAccept(accept(), knownChannelRefs: {'C1'}),
          'bad_state');
    });
    test('maxSpend above offer cap rejected', () {
      final m = SessionMachine(sessionId: 's1', now: () => 1000)
        ..sendOffer(offer());
      expectCode(
          () => m.receiveAccept(accept(max: '1'), knownChannelRefs: {'C1'}),
          'spend_exceeds_offer');
    });
    test('expired offer rejected at accept', () {
      var t = 1000;
      final m = SessionMachine(sessionId: 's1', now: () => t)
        ..sendOffer(offer());
      t = 2001;
      expectCode(() => m.receiveAccept(accept(), knownChannelRefs: {'C1'}),
          'stale_offer');
    });
    test('vouchers must strictly increase; replay and rollback rejected', () {
      final m = providerActive();
      m.commitVoucher(voucher('0.001'));
      m.commitVoucher(voucher('0.002'));
      expectCode(() => m.commitVoucher(voucher('0.002')), 'non_monotonic');
      expectCode(() => m.commitVoucher(voucher('0.0015')), 'non_monotonic');
      expect(m.highestCumulative, Amount.parse('0.002'));
    });
    test('voucher wrong channel / over budget / wrong session', () {
      final m = providerActive();
      expectCode(
          () => m.commitVoucher(voucher('0.001', ch: 'C2')), 'wrong_channel');
      expectCode(() => m.commitVoucher(voucher('0.021')), 'over_budget');
      expectCode(() => m.commitVoucher(voucher('0.001', session: 'zzz')),
          'wrong_session');
    });
    test('10+ units with increasing vouchers then close', () {
      final m = providerActive();
      for (var i = 1; i <= 12; i++) {
        m.receiveSample(MeterSample(
            session: 's1', seq: i, cumulativeUnits: i, sampleHash: 'h$i'));
        m.commitVoucher(voucher((i * 0.0001).toStringAsFixed(4)));
      }
      m.close();
      expect(m.phase, SessionPhase.closed);
      expect(m.highestCumulative, Amount.parse('0.0012'));
      expectCode(() => m.commitVoucher(voucher('0.003')), 'bad_state');
    });
    test('meter samples: stale seq, regression, cap', () {
      final m = providerActive();
      m.receiveSample(const MeterSample(
          session: 's1', seq: 1, cumulativeUnits: 5, sampleHash: 'h'));
      expectCode(
          () => m.receiveSample(const MeterSample(
              session: 's1', seq: 1, cumulativeUnits: 6, sampleHash: 'h')),
          'stale_sample');
      expectCode(
          () => m.receiveSample(const MeterSample(
              session: 's1', seq: 2, cumulativeUnits: 4, sampleHash: 'h')),
          'meter_regression');
      expectCode(
          () => m.receiveSample(const MeterSample(
              session: 's1', seq: 3, cumulativeUnits: 201, sampleHash: 'h')),
          'unit_cap');
    });
  });

  test('UsageMeter enforces cap and computes owed', () {
    final meter = UsageMeter(pricePerUnit: Amount.parse('0.0001'), maxUnits: 3);
    meter.record(2);
    expect(meter.owed, Amount.parse('0.0002'));
    expect(() => meter.record(2), throwsStateError);
    expect(() => meter.record(0), throwsArgumentError);
  });

  group('multiple sessions per channel (v2 baseline)', () {
    SessionMachine second({String baseline = '0.015', String? known}) {
      final m = SessionMachine(sessionId: 's1', now: () => 1000)
        ..sendOffer(offer());
      m.receiveAccept(accept(baseline: baseline, nonce: 'n2'),
          knownChannelRefs: {'C1'},
          channelCumulative: Amount.parse(known ?? baseline));
      return m;
    }

    test('budget is measured from the baseline', () {
      final m = second();
      expect(m.highestCumulative, Amount.parse('0.015'));
      expect(m.sessionSpend, Amount.zero);
      m.commitVoucher(voucher('0.02'));
      expect(m.sessionSpend, Amount.parse('0.005'));
      m.commitVoucher(voucher('0.035')); // 0.015 + 0.02 = cap, inclusive
      expect(m.sessionSpend, Amount.parse('0.02'));
      expectCode(() => m.commitVoucher(voucher('0.0350001')), 'over_budget');
    });
    test('vouchers at or below the baseline are not new value', () {
      final m = second();
      expectCode(() => m.commitVoucher(voucher('0.015')), 'non_monotonic');
      expectCode(() => m.commitVoucher(voucher('0.01')), 'non_monotonic');
    });
    test('provider refuses a baseline that differs from its records', () {
      for (final claimed in ['0.01', '0.02']) {
        expectCode(() => second(baseline: claimed, known: '0.015'),
            'baseline_mismatch');
      }
      // A v1-style zero baseline on a used channel is also a mismatch.
      expectCode(
          () => second(baseline: '0', known: '0.015'), 'baseline_mismatch');
    });
    test('fresh channel: zero baseline with no provider history', () {
      final m = SessionMachine(sessionId: 's1', now: () => 1000)
        ..sendOffer(offer());
      m.receiveAccept(accept(), knownChannelRefs: {'C1'});
      expect(m.sessionSpend, Amount.zero);
      expectCode(
          () => SessionMachine(sessionId: 's1', now: () => 1000)
            ..sendOffer(offer())
            ..receiveAccept(accept(baseline: '0.01'), knownChannelRefs: {'C1'}),
          'baseline_mismatch');
    });
    test('payer side starts its highest at the baseline too', () {
      final m = SessionMachine(sessionId: 's1', now: () => 1000)
        ..receiveOffer(offer(), policy)
        ..sendAccept(accept(baseline: '0.5'));
      expect(m.highestCumulative, Amount.parse('0.5'));
      expect(m.sessionSpend, Amount.zero);
    });
  });
}
