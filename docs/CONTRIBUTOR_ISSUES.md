# Contributor issues — Sideband-protocol

Scoped work for **Sideband-protocol**, taken from the gaps listed in the README status table. These are
candidates, not yet all opened on GitHub; a maintainer opens an issue (labels: `good first issue`,
`bug`, `documentation`, `stellar`, `blocked`) once its dependencies are ready. Each item names its
interface touchpoints, acceptance tests and non-goals. Size: S (< 1 day), M (1–3 days), L (> 3 days).

Rules: Testnet/synthetic only; no real keys or funds; tests for failure paths; one repository
boundary per issue. Cross-repo work is listed at the end and needs a linked PR in each repo.

## Open work

- [ ] **Android BLE transport adapter** (`lib/src/transport`). Implement `Transport` over BLE GATT
  (advertise offer, negotiate, chunk frames under MTU, backpressure). *Acceptance:* passes the
  existing transport contract tests via a fake BLE layer; documented permissions. *Non-goals:*
  payment signing in transport code. *Size:* L.
- [ ] **Local Wi-Fi upgrade path.** Negotiate over BLE, then move the session to a local socket
  with the same session id. *Acceptance:* loopback test that switches transports mid-session
  without losing or duplicating frames. *Size:* M.
- [ ] **Frame schema snapshots.** Export JSON Schema for every v1 frame and check it into
  `schema/`; CI fails on unreviewed changes. *Acceptance:* gateway and mobile fixtures validate
  against it. *Size:* S. `good first issue`.
- [ ] **Fuzz the frame decoder.** Property tests for oversized, truncated and malformed frames.
  *Acceptance:* no exception escapes `decode` other than the documented error type. *Size:* S.
- [ ] **Session resume after disconnect.** Resume with the highest committed voucher and meter
  sample instead of starting over. *Acceptance:* state-machine tests for resume, stale resume and
  replayed resume. *Size:* M.

## Cross-repository

- [ ] **Integration lockfile.** A file in each repo pinning the tested sibling tags/SHAs, checked in
  CI. *Acceptance:* CI fails when a pinned sibling fixture differs. *Size:* M.
- [ ] **Testnet end-to-end demo.** Fund → offline session → settle on Testnet with recorded
  transaction hashes, driven from a clean checkout. *Blocked on:* channels Testnet deploy, gateway
  Soroban wiring. *Size:* L.
- [ ] **Physical-device compatibility harness.** Two-phone BLE/Wi-Fi run with a published matrix.
  *Blocked on:* protocol transport adapters. *Size:* L.
