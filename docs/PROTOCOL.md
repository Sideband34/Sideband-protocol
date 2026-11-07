# Sideband session protocol

This is the wire and session contract implemented by this package. It describes what a payer and a provider send to each other during one metered session. It
does **not** define how vouchers are signed or settled: that belongs to [Sideband-channels](https://github.com/Sideband34/Sideband-channels), and frames only carry
the resulting credentials as opaque strings.

Offline use does not mean money moves without the internet. The payer funds a Stellar channel while online. During the session the two devices exchange signed
cumulative commitments over a local link. The provider settles on-chain later.

## Versions and limits

| Item | Value |
|---|---|
| Current wire version | `2` |
| Accepted versions | `1`, `2` |
| Maximum encoded frame | 16 KiB (`maxFrameBytes`); larger frames are rejected on encode and decode |
| Maximum string field length | 2048 characters; strings must be non-empty |
| Integers | Non-negative JSON integers only |
| Amounts | Decimal strings with exactly 7 fractional digits (stroops), parsed with integer arithmetic. There are no floats anywhere |

A frame is encoded with the **lowest** version that can represent it. Only a `session_accept` with a non-zero `baseline` is version 2. Every other frame is
byte-identical to version 1. See [ADR 0001](./adr/0001-session-baseline.md).

## Canonical encoding

Frames are serialized as canonical JSON: object keys sorted by UTF-16 code unit, no insignificant whitespace, and only `null`, booleans, integers, strings, lists
and maps. This encoding gives a stable frame identity and transcript hash. It is **not** the byte format that vouchers are signed over.

## Frames

Every frame carries `type`, `v` and `session` (an opaque identifier chosen by the provider).

| Type | Direction | Fields |
|---|---|---|
| `service_offer` | provider to payer | `serviceId`, `providerPublicKey`, `pricePerUnit`, `unit`, `currency`, `network`, `maxSessionUnits`, `expiresAt` (Unix seconds) |
| `session_accept` | payer to provider | `channelRef`, `maxSpend`, `nonce`, and in v2 `baseline` |
| `meter_sample` | provider to payer | `seq`, `cumulativeUnits`, `sampleHash` |
| `voucher` | payer to provider | `channelRef`, `cumulativeAmount`, `commitment`, `signature` |
| `session_close` | either | `reason` |
| `error` | either | `code`, `message` |

Example (values are illustrative):

```json
{"currency":"XLM","expiresAt":1793900000,"maxSessionUnits":1000,"network":"testnet","pricePerUnit":"0.0010000","providerPublicKey":"G...","serviceId":"demo-text-words","session":"s-1","type":"service_offer","unit":"word","v":1}
{"baseline":"0.0020000","channelRef":"C...","maxSpend":"0.0200000","nonce":"n-7","session":"s-2","type":"session_accept","v":2}
```

`baseline` is the channel's cumulative voucher amount at the start of the session. Vouchers stay cumulative per channel, so a second session on the same channel may sign
up to `baseline + maxSpend`. A v1 `session_accept` must not carry `baseline`, and the channel must then be fresh.

## Session state machine

`SessionMachine` validates one session. Phases: `idle`, `offered`, `active`, `closed`. Time is injected, so tests are deterministic.

| Step | Who | Checks |
|---|---|---|
| `sendOffer` | provider | Phase is `idle`; the frame belongs to this session |
| `receiveOffer` | payer | Network, currency, trusted provider key, price at or below the payer cap, and that the offer has not expired |
| `receiveAccept` | provider | The offer is live; the channel is in the provider's set of funded channels; `baseline` equals the provider's recorded channel cumulative exactly; the `nonce` was never used; `maxSpend` is at most `pricePerUnit * maxSessionUnits` |
| `receiveSample` | payer | `seq` strictly increases; units never decrease; units stay within the offered cap |
| `commitVoucher` | provider | Same channel; amount at most `baseline + maxSpend`; amount strictly above the highest seen so far |
| `close` | either | Moves to `closed`; repeating it is harmless |

`commitVoucher` performs structural checks only. The caller must verify the signature with Sideband-channels **before** calling it.

### Violation codes

A rejected step throws `SessionViolation` with a stable code, which is also what goes into an `error` frame.

| Code | Meaning |
|---|---|
| `bad_state` | The action is not allowed in the current phase |
| `wrong_session` | The frame belongs to another session |
| `wrong_network`, `wrong_currency` | The offer does not match the payer's policy |
| `untrusted_provider` | The provider key is not in the payer's trusted set |
| `price_too_high` | The price is above the payer's cap |
| `stale_offer` | The offer has expired |
| `no_funded_channel` | The channel is unknown or not funded for this provider; a paid session must not begin |
| `baseline_mismatch` | The payer's baseline differs from the provider's channel cumulative |
| `replayed_nonce` | The accept nonce was already used |
| `spend_exceeds_offer` | `maxSpend` is above what the offer allows |
| `stale_sample`, `meter_regression`, `unit_cap` | The meter sample is old, went backwards, or exceeds the cap |
| `wrong_channel` | The voucher is for a different channel |
| `over_budget` | The voucher exceeds `baseline + maxSpend` |
| `non_monotonic` | The voucher is not above the highest one seen |

## Metering and transport

- `UsageMeter` is a pure, monotonic unit counter with a session cap. It records units and throws when the cap would be exceeded. The sample-hash helper shipped
  with it is a dependency-free placeholder for tests and examples; production use should supply a SHA-256 based function.
- `Transport` is an interface for a byte link. `InMemoryTransport` is a loopback for tests. The BLE and local-network adapters live in Sideband-mobile.
- `FrameChannel` wraps a transport with bounded retries (three attempts by default) and exponential backoff.

## What this package does not do

- No signing, no signature verification, no ledger access.
- No transport-level session resume frame yet; the payer resumes through the gateway API today.
- No hardware testing of BLE: the adapters are unit-tested with fakes.

## Try it

```bash
dart pub get
dart test
dart run example/loopback.dart   # a payer and a provider over the in-memory loopback
```
