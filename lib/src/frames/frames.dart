import 'dart:convert';

import 'amount.dart';
import 'canonical.dart';

/// Current wire version. Frames with any other version are rejected.
const int protocolVersion = 1;

/// Maximum accepted size of one encoded frame (anti-DoS bound).
const int maxFrameBytes = 16 * 1024;

class FrameException implements Exception {
  FrameException(this.message);
  final String message;
  @override
  String toString() => 'FrameException: $message';
}

/// Base class of all wire frames. Every frame carries `type`, `v`, `session`.
sealed class Frame {
  const Frame({required this.session});

  /// Opaque session identifier chosen by the provider.
  final String session;

  String get type;

  Map<String, Object?> body();

  Map<String, Object?> toJson() => {
        'type': type,
        'v': protocolVersion,
        'session': session,
        ...body(),
      };

  String encode() {
    final s = canonicalJson(toJson());
    if (utf8.encode(s).length > maxFrameBytes) {
      throw FrameException('Frame exceeds $maxFrameBytes bytes');
    }
    return s;
  }

  static Frame decode(String raw) {
    if (utf8.encode(raw).length > maxFrameBytes) {
      throw FrameException('Frame exceeds $maxFrameBytes bytes');
    }
    final Object? j;
    try {
      j = jsonDecode(raw);
    } on FormatException catch (e) {
      throw FrameException('Malformed JSON: ${e.message}');
    }
    if (j is! Map<String, Object?>) {
      throw FrameException('Frame must be object');
    }
    final v = j['v'];
    if (v != protocolVersion) {
      throw FrameException('Unsupported protocol version: $v');
    }
    final type = _str(j, 'type');
    final session = _str(j, 'session');
    try {
      switch (type) {
        case 'service_offer':
          return ServiceOffer(
            session: session,
            serviceId: _str(j, 'serviceId'),
            providerPublicKey: _str(j, 'providerPublicKey'),
            pricePerUnit: Amount.parse(_str(j, 'pricePerUnit')),
            unit: _str(j, 'unit'),
            currency: _str(j, 'currency'),
            network: _str(j, 'network'),
            maxSessionUnits: _int(j, 'maxSessionUnits'),
            expiresAt: _int(j, 'expiresAt'),
          );
        case 'session_accept':
          return SessionAccept(
            session: session,
            channelRef: _str(j, 'channelRef'),
            maxSpend: Amount.parse(_str(j, 'maxSpend')),
            nonce: _str(j, 'nonce'),
          );
        case 'meter_sample':
          return MeterSample(
            session: session,
            seq: _int(j, 'seq'),
            cumulativeUnits: _int(j, 'cumulativeUnits'),
            sampleHash: _str(j, 'sampleHash'),
          );
        case 'voucher':
          return VoucherFrame(
            session: session,
            channelRef: _str(j, 'channelRef'),
            cumulativeAmount: Amount.parse(_str(j, 'cumulativeAmount')),
            commitment: _str(j, 'commitment'),
            signature: _str(j, 'signature'),
          );
        case 'session_close':
          return SessionClose(session: session, reason: _str(j, 'reason'));
        case 'error':
          return ErrorFrame(
            session: session,
            code: _str(j, 'code'),
            message: _str(j, 'message'),
          );
        default:
          throw FrameException('Unknown frame type: $type');
      }
    } on FormatException catch (e) {
      throw FrameException('Invalid field: ${e.message} ${e.source ?? ''}');
    }
  }
}

String _str(Map<String, Object?> j, String k) {
  final v = j[k];
  if (v is! String || v.isEmpty || v.length > 2048) {
    throw FrameException('Field "$k" must be a non-empty string');
  }
  return v;
}

int _int(Map<String, Object?> j, String k) {
  final v = j[k];
  if (v is! int || v < 0) {
    throw FrameException('Field "$k" must be a non-negative integer');
  }
  return v;
}

class ServiceOffer extends Frame {
  const ServiceOffer({
    required super.session,
    required this.serviceId,
    required this.providerPublicKey,
    required this.pricePerUnit,
    required this.unit,
    required this.currency,
    required this.network,
    required this.maxSessionUnits,
    required this.expiresAt,
  });

  final String serviceId;
  final String providerPublicKey;
  final Amount pricePerUnit;
  final String unit;
  final String currency;

  /// e.g. `testnet`. Frames for the wrong network must be refused.
  final String network;
  final int maxSessionUnits;

  /// Unix epoch seconds.
  final int expiresAt;

  @override
  String get type => 'service_offer';

  @override
  Map<String, Object?> body() => {
        'serviceId': serviceId,
        'providerPublicKey': providerPublicKey,
        'pricePerUnit': pricePerUnit.toString(),
        'unit': unit,
        'currency': currency,
        'network': network,
        'maxSessionUnits': maxSessionUnits,
        'expiresAt': expiresAt,
      };
}

class SessionAccept extends Frame {
  const SessionAccept({
    required super.session,
    required this.channelRef,
    required this.maxSpend,
    required this.nonce,
  });

  final String channelRef;
  final Amount maxSpend;
  final String nonce;

  @override
  String get type => 'session_accept';

  @override
  Map<String, Object?> body() => {
        'channelRef': channelRef,
        'maxSpend': maxSpend.toString(),
        'nonce': nonce,
      };
}

class MeterSample extends Frame {
  const MeterSample({
    required super.session,
    required this.seq,
    required this.cumulativeUnits,
    required this.sampleHash,
  });

  final int seq;
  final int cumulativeUnits;
  final String sampleHash;

  @override
  String get type => 'meter_sample';

  @override
  Map<String, Object?> body() => {
        'seq': seq,
        'cumulativeUnits': cumulativeUnits,
        'sampleHash': sampleHash,
      };
}

/// Carries an opaque credential produced by `sideband-channels`. This package
/// never inspects or verifies `commitment` / `signature`.
class VoucherFrame extends Frame {
  const VoucherFrame({
    required super.session,
    required this.channelRef,
    required this.cumulativeAmount,
    required this.commitment,
    required this.signature,
  });

  final String channelRef;
  final Amount cumulativeAmount;
  final String commitment;
  final String signature;

  @override
  String get type => 'voucher';

  @override
  Map<String, Object?> body() => {
        'channelRef': channelRef,
        'cumulativeAmount': cumulativeAmount.toString(),
        'commitment': commitment,
        'signature': signature,
      };
}

class SessionClose extends Frame {
  const SessionClose({required super.session, required this.reason});
  final String reason;

  @override
  String get type => 'session_close';

  @override
  Map<String, Object?> body() => {'reason': reason};
}

class ErrorFrame extends Frame {
  const ErrorFrame({
    required super.session,
    required this.code,
    required this.message,
  });
  final String code;
  final String message;

  @override
  String get type => 'error';

  @override
  Map<String, Object?> body() => {'code': code, 'message': message};
}
