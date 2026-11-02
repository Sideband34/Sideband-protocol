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
