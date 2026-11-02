// ignore_for_file: avoid_print
import 'package:sideband_protocol/sideband_protocol.dart';

/// Synthetic provider/payer session over an in-memory link. No real funds,
/// no signing: the voucher fields are placeholders for sideband-channels output.
Future<void> main() async {
  final (p, q) = InMemoryTransport.pair();
  final provider = FrameChannel(p);
  final payer = FrameChannel(q);
  final m = SessionMachine(sessionId: 'demo', now: () => 1000);
  m.sendOffer(ServiceOffer(
    session: 'demo',
    serviceId: 'caption-demo',
    providerPublicKey: 'GPROVIDER',
    pricePerUnit: Amount.parse('0.0001'),
    unit: 'second',
    currency: 'TEST_ASSET',
    network: 'testnet',
    maxSessionUnits: 100,
    expiresAt: 2000,
  ));
  payer.frames.listen((f) => print('payer got ${f.type}'));
  await provider.send(m.offer!);
  await Future<void>.delayed(Duration.zero);
}
