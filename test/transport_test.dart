import 'dart:async';

import 'package:sideband_protocol/sideband_protocol.dart';
import 'package:test/test.dart';

class FlakyTransport implements Transport {
  FlakyTransport(this.failures);
  int failures;
  final sent = <String>[];
  @override
  Stream<String> get incoming => const Stream.empty();
  @override
  Future<void> send(String f) async {
    if (failures-- > 0) throw StateError('link down');
    sent.add(f);
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('loopback delivers decoded frames', () async {
    final (a, b) = InMemoryTransport.pair();
    final tx = FrameChannel(a);
    final rx = FrameChannel(b);
    final got = rx.frames.first;
    await tx.send(const SessionClose(session: 's', reason: 'bye'));
    final f = await got;
    expect(f, isA<SessionClose>());
  });
  test('retries then succeeds', () async {
    final t = FlakyTransport(2);
    await FrameChannel(t, baseDelay: Duration.zero)
        .send(const SessionClose(session: 's', reason: 'r'));
    expect(t.sent, hasLength(1));
  });
  test('gives up after maxAttempts', () async {
    final t = FlakyTransport(5);
    await expectLater(
      FrameChannel(t, baseDelay: Duration.zero)
          .send(const SessionClose(session: 's', reason: 'r')),
      throwsStateError,
    );
  });
  test('backpressure when queue full', () async {
    final gate = Completer<void>();
    final t = _Slow(gate.future);
    final ch = FrameChannel(t, maxQueue: 1);
    final first = ch.send(const SessionClose(session: 's', reason: 'r'));
    await expectLater(ch.send(const SessionClose(session: 's', reason: 'r')),
        throwsStateError);
    gate.complete();
    await first;
  });
  test('bad peer data surfaces as stream error', () async {
    final (a, b) = InMemoryTransport.pair();
    final rx = FrameChannel(b);
    final errors = <Object>[];
    final sub = rx.frames.listen((_) {}, onError: errors.add);
    await a.send('garbage');
    await Future<void>.delayed(Duration.zero);
    expect(errors.single, isA<FrameException>());
    await sub.cancel();
  });
  test('succeeds on the first try with zero delays', () async {
    final delays = <Duration>[];
    final t = _RecordingTransport(failures: 0);
    final ch = FrameChannel(t, delay: (d) async => delays.add(d));
    await ch.send(const SessionClose(session: 's', reason: 'r'));
    expect(t.attempts, 1);
    expect(t.sent, hasLength(1));
    expect(delays, isEmpty);
  });
  test('succeeds after two failures with documented backoff sequence',
      () async {
    final delays = <Duration>[];
    final t = _RecordingTransport(failures: 2);
    final ch = FrameChannel(t, delay: (d) async => delays.add(d));
    await ch.send(const SessionClose(session: 's', reason: 'r'));
    expect(t.attempts, 3);
    expect(t.sent, hasLength(1));
    expect(delays, const [
      Duration(milliseconds: 50),
      Duration(milliseconds: 100),
    ]);
  });
  test('rethrows original error after maxAttempts tries and frees queue slot',
      () async {
    final delays = <Duration>[];
    final err = ArgumentError('radio offline');
    final t = _RecordingTransport(failures: 10, error: err);
    final ch = FrameChannel(
      t,
      maxQueue: 1,
      maxAttempts: 4,
      delay: (d) async => delays.add(d),
    );
    await expectLater(
      ch.send(const SessionClose(session: 's', reason: 'r')),
      throwsA(same(err)),
    );
    expect(t.attempts, 4);
    expect(delays, const [
      Duration(milliseconds: 50),
      Duration(milliseconds: 100),
      Duration(milliseconds: 200),
    ]);
    t.failures = 0;
    await ch.send(const SessionClose(session: 's', reason: 'recovered'));
    expect(t.sent, hasLength(1));
  });
  test('exponential backoff grows up to maxDelay cap', () async {
    final delays = <Duration>[];
    final t = _RecordingTransport(failures: 4);
    final ch = FrameChannel(
      t,
      maxAttempts: 5,
      baseDelay: const Duration(milliseconds: 50),
      maxDelay: const Duration(milliseconds: 150),
      delay: (d) async => delays.add(d),
    );
    await ch.send(const SessionClose(session: 's', reason: 'r'));
    expect(t.attempts, 5);
    expect(delays, const [
      Duration(milliseconds: 50),
      Duration(milliseconds: 100),
      Duration(milliseconds: 150),
      Duration(milliseconds: 150),
    ]);
  });
  test('rejects maxAttempts below 1', () {
    final t = _RecordingTransport(failures: 0);
    expect(() => FrameChannel(t, maxAttempts: 0), throwsArgumentError);
  });
}

class _RecordingTransport implements Transport {
  _RecordingTransport({required this.failures, this.error});
  int failures;
  final Object? error;
  int attempts = 0;
  final sent = <String>[];

  @override
  Stream<String> get incoming => const Stream.empty();

  @override
  Future<void> send(String f) async {
    attempts++;
    if (failures-- > 0) throw error ?? StateError('link down');
    sent.add(f);
  }

  @override
  Future<void> close() async {}
}

class _Slow implements Transport {
  _Slow(this.gate);
  final Future<void> gate;
  @override
  Stream<String> get incoming => const Stream.empty();
  @override
  Future<void> send(String f) => gate;
  @override
  Future<void> close() async {}
}
