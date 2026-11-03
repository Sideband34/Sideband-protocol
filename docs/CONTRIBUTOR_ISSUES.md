# Contributor issues — Sideband-protocol

Scoped work for **Sideband-protocol**, taken from the gaps listed in the README status table. These are
candidates, not yet all opened on GitHub; a maintainer opens an issue (labels: `good first issue`,
`bug`, `documentation`, `stellar`, `blocked`) once its dependencies are ready. Each item names its
interface touchpoints, acceptance tests and non-goals. Size: S (< 1 day), M (1–3 days), L (> 3 days).

Rules: Testnet/synthetic only; no real keys or funds; tests for failure paths; one repository
boundary per issue. Cross-repo work is listed at the end and needs a linked PR in each repo.

## Open work

- [ ] **Frame schema snapshots.** Export JSON Schema for every v1/v2 frame into `schema/`; CI fails
  on unreviewed changes. *Acceptance:* gateway and mobile fixtures validate against it. *Size:* S.
  `good first issue`.
- [ ] **Fuzz the frame decoder.** Property tests for oversized, truncated and malformed frames.
  *Acceptance:* no exception escapes `decode` other than `FrameException`. *Size:* S.
- [ ] **Transport switch mid-session.** Negotiate over BLE, then move the session to a LAN socket
  with the same session id. *Acceptance:* loopback test that switches transports without losing or
  duplicating frames. *Size:* M.
- [ ] **Session resume frame.** The payer resumes today over the gateway HTTP API (journal +
  re-attach). Define a transport-level `session_resume` frame (v3) with stale/replayed resume
  rules. *Acceptance:* state-machine tests for resume, stale resume and replayed resume. *Size:* M.

## Cross-repository

- [ ] **Integration lockfile.** A file in each repo pinning the tested sibling tags/SHAs, checked in
  CI. *Acceptance:* CI fails when a pinned sibling fixture differs. *Size:* M.
- [ ] **Testnet end-to-end demo.** Fund → offline session (two sessions on one channel) → settle on
  Testnet with recorded transaction hashes, driven from a clean checkout. *Blocked on:* running
  `scripts/deploy-testnet.sh` in Sideband-channels, gateway Soroban wiring. *Size:* L.
- [ ] **Physical-device compatibility harness.** Two-phone BLE run of the mobile `BleTransport`
  with a published matrix. *Acceptance:* a frame exchange of 10+ vouchers recorded per device
  pair; no row marked supported without a run. *Size:* L.
