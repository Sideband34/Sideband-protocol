# ADR 0001 — Protocol v2: `session_accept.baseline`

Status: accepted.

## Context
Vouchers are cumulative per **channel** (the Soroban contract pays the provider
up to the highest signed amount for that channel), but `SessionMachine` and the
gateway budgeted per **session**: `maxSpend` was compared with the voucher's
channel-cumulative amount. A second session on the same channel would either be
mis-budgeted (the old commitments count against the new budget) or, worse,
the provider could treat earlier commitments as payment for new usage. The
gateway and mobile therefore refused to reuse a channel at all, which forces a
new on-chain deposit per session.

## Decision
Protocol v2 adds one field, `baseline` (canonical 7-decimal amount), to
`session_accept`: the channel's cumulative amount committed before this session.

- The payer may sign vouchers up to `baseline + maxSpend` in this session; each
  voucher must be strictly above the current highest, which starts at
  `baseline`. `SessionMachine.sessionSpend` = highest − baseline.
- The provider must refuse (`baseline_mismatch`) unless `baseline` equals its
  own highest accepted voucher for the channel: a lower baseline would let old
  commitments pay for new usage, a higher one would make the payer pay twice.
- Only one session per channel is active at a time (unchanged); sessions on a
  channel are sequential.
- Frames are encoded with the lowest version that can represent them. A
  `session_accept` with `baseline == 0` is still encoded as v1 and is
  byte-identical to before; a non-zero baseline is encoded as `"v":2`. All
  other frames remain v1. The decoder accepts v1 and v2 for every type; a v1
  `session_accept` must not carry `baseline` (it decodes as zero), and a v2 one
  must.

## Consequences
- v1-only peers reject v2 frames, which is the safe failure: they cannot
  honour a baseline.
- `SessionAccept` is no longer a `const` constructor (it defaults `baseline`).
- Gateway and mobile can run several sequential sessions on one funded channel
  and pay out with partial `settle` (Sideband-channels ADR 0002).
