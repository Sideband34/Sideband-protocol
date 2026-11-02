import '../frames/amount.dart';
import '../frames/frames.dart';

enum SessionPhase { idle, offered, active, closed }

class SessionViolation implements Exception {
  SessionViolation(this.code, this.message);

  /// Stable machine-readable code, also sent in [ErrorFrame].
  final String code;
  final String message;

  @override
  String toString() => 'SessionViolation($code): $message';
}

/// Payer-side policy applied to a received [ServiceOffer].
class PayerPolicy {
  const PayerPolicy({
    required this.expectedNetwork,
    required this.expectedCurrency,
    required this.maxPricePerUnit,
    required this.trustedProviderKeys,
  });

  final String expectedNetwork;
  final String expectedCurrency;
  final Amount maxPricePerUnit;

  /// Provider keys previously authenticated out of band (e.g. via manifest).
  final Set<String> trustedProviderKeys;
}

/// State machine for one payer<->provider session, from the provider's side
/// of validation (it receives accept + vouchers + sends offer/samples), and
/// payer validation of the offer. Time is injected for testability.
class SessionMachine {
  SessionMachine({
    required this.sessionId,
    required this.now,
  });

  final String sessionId;

  /// Returns unix epoch seconds.
  final int Function() now;

  SessionPhase _phase = SessionPhase.idle;
  ServiceOffer? _offer;
  SessionAccept? _accept;
  Amount _highest = Amount.zero;
  VoucherFrame? _highestVoucher;
  final Set<String> _seenNonces = {};
  int _lastSampleSeq = 0;
  int _lastSampleUnits = 0;

  SessionPhase get phase => _phase;
  ServiceOffer? get offer => _offer;
  SessionAccept? get accept => _accept;
  Amount get highestCumulative => _highest;
  VoucherFrame? get highestVoucher => _highestVoucher;

  void _sessionMatch(Frame f) {
    if (f.session != sessionId) {
      throw SessionViolation('wrong_session', 'Frame for another session');
    }
  }

  /// Provider records the offer it sent.
  void sendOffer(ServiceOffer o) {
    _require(SessionPhase.idle, 'send offer');
    _sessionMatch(o);
    _offer = o;
    _phase = SessionPhase.offered;
  }

  /// Payer validates a received offer against [policy], then records it.
  void receiveOffer(ServiceOffer o, PayerPolicy policy) {
    _require(SessionPhase.idle, 'receive offer');
    _sessionMatch(o);
    if (o.network != policy.expectedNetwork) {
      throw SessionViolation('wrong_network', 'Offer network ${o.network}');
    }
    if (o.currency != policy.expectedCurrency) {
      throw SessionViolation('wrong_currency', 'Offer currency ${o.currency}');
    }
    if (!policy.trustedProviderKeys.contains(o.providerPublicKey)) {
      throw SessionViolation('untrusted_provider', 'Unknown provider key');
    }
    if (o.pricePerUnit > policy.maxPricePerUnit) {
      throw SessionViolation('price_too_high', 'Price exceeds payer cap');
    }
    if (o.expiresAt <= now()) {
      throw SessionViolation('stale_offer', 'Offer expired');
    }
    _offer = o;
    _phase = SessionPhase.offered;
  }

  /// Provider receives the payer's accept. [knownChannelRefs] is the provider's
  /// cached set of funded channels bound to it (from online deposit proof).
  void receiveAccept(SessionAccept a, {required Set<String> knownChannelRefs}) {
    _require(SessionPhase.offered, 'accept');
    _sessionMatch(a);
    final o = _offer!;
    if (o.expiresAt <= now()) {
      throw SessionViolation('stale_offer', 'Offer expired');
    }
    if (!knownChannelRefs.contains(a.channelRef)) {
      // No pre-funded channel: refuse to begin a paid session.
      throw SessionViolation('no_funded_channel', 'Channel not funded/bound');
    }
    if (!_seenNonces.add(a.nonce)) {
      throw SessionViolation('replayed_nonce', 'Nonce already used');
    }
    final cap = o.pricePerUnit.times(o.maxSessionUnits);
    if (a.maxSpend > cap) {
      throw SessionViolation('spend_exceeds_offer', 'maxSpend above offer cap');
    }
    _accept = a;
    _phase = SessionPhase.active;
  }

  /// Payer-side: checks that the offer matches what the payer accepted.
  void sendAccept(SessionAccept a) {
    _require(SessionPhase.offered, 'send accept');
    _sessionMatch(a);
    final o = _offer!;
    if (a.maxSpend > o.pricePerUnit.times(o.maxSessionUnits)) {
      throw SessionViolation('spend_exceeds_offer', 'maxSpend above offer cap');
    }
    _accept = a;
    _phase = SessionPhase.active;
  }

  /// Validates a meter sample: strictly increasing seq, non-decreasing units,
  /// within the offered unit cap.
  void receiveSample(MeterSample s) {
    _require(SessionPhase.active, 'meter sample');
    _sessionMatch(s);
    if (s.seq <= _lastSampleSeq) {
      throw SessionViolation('stale_sample', 'Sample seq not increasing');
    }
    if (s.cumulativeUnits < _lastSampleUnits) {
      throw SessionViolation('meter_regression', 'Units decreased');
    }
    if (s.cumulativeUnits > _offer!.maxSessionUnits) {
      throw SessionViolation('unit_cap', 'Units exceed offered cap');
    }
    _lastSampleSeq = s.seq;
    _lastSampleUnits = s.cumulativeUnits;
  }

  /// Provider-side structural voucher checks. Cryptographic verification of
  /// `signature` is NOT done here; the caller must verify with
  /// `sideband-channels` BEFORE calling [commitVoucher].
  ///
  /// Enforces: matching channel, cap, strictly monotonic cumulative amount.
  /// Returns true if the voucher became the new highest.
  bool commitVoucher(VoucherFrame v) {
    _require(SessionPhase.active, 'voucher');
    _sessionMatch(v);
    if (v.channelRef != _accept!.channelRef) {
      throw SessionViolation('wrong_channel', 'Voucher for another channel');
    }
    if (v.cumulativeAmount > _accept!.maxSpend) {
      throw SessionViolation('over_budget', 'Voucher exceeds maxSpend');
    }
    if (v.cumulativeAmount <= _highest) {
      throw SessionViolation('non_monotonic', 'Voucher not above highest');
    }
    _highest = v.cumulativeAmount;
    _highestVoucher = v;
    return true;
  }

  void close() {
    if (_phase == SessionPhase.closed) return;
    _phase = SessionPhase.closed;
  }

  void _require(SessionPhase p, String action) {
    if (_phase != p) {
      throw SessionViolation(
        'bad_state',
        'Cannot $action in phase ${_phase.name} (need ${p.name})',
      );
    }
  }
}
