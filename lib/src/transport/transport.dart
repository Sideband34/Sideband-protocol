import 'dart:async';

import '../frames/frames.dart';

/// Physical-transport contract (BLE, Wi-Fi Direct, LAN, loopback). Adapters
/// move opaque encoded frames; they never sign or interpret payments.
abstract interface class Transport {
  /// Incoming raw frame strings.
  Stream<String> get incoming;

  /// Sends one encoded frame. Completes when handed to the link layer.
  Future<void> send(String encodedFrame);

  Future<void> close();
}

/// Loopback pair for tests and examples.
class InMemoryTransport implements Transport {
  InMemoryTransport._(this._out, this._in);

  final StreamController<String> _out;
  final StreamController<String> _in;

  static (InMemoryTransport, InMemoryTransport) pair() {
    final a = StreamController<String>();
    final b = StreamController<String>();
    return (InMemoryTransport._(a, b), InMemoryTransport._(b, a));
  }

  @override
  Stream<String> get incoming => _in.stream;

  @override
  Future<void> send(String encodedFrame) async => _out.add(encodedFrame);

  @override
  Future<void> close() async {
    await _out.close();
  }
}

/// Wraps a [Transport] with typed frames, bounded send queue (backpressure) and
/// bounded retries with exponential backoff.
class FrameChannel {
  FrameChannel(
    this._t, {
    this.maxQueue = 64,
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 50),
  });

  final Transport _t;
  final int maxQueue;
  final int maxAttempts;
  final Duration baseDelay;
  int _pending = 0;

  /// Decoded frames. Undecodable input is surfaced as stream errors rather
  /// than silently dropped, so callers can penalise bad peers.
  Stream<Frame> get frames => _t.incoming.map(Frame.decode);

  Future<void> send(Frame f) async {
    if (_pending >= maxQueue) {
      throw StateError('Send queue full ($maxQueue); apply backpressure');
    }
    _pending++;
    try {
      final enc = f.encode();
      for (var attempt = 1;; attempt++) {
        try {
          await _t.send(enc);
          return;
        } catch (_) {
          if (attempt >= maxAttempts) rethrow;
          await Future<void>.delayed(baseDelay * (1 << (attempt - 1)));
        }
      }
    } finally {
      _pending--;
    }
  }
}
