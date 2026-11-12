# Changelog

All notable changes to Sideband-protocol. Pre-release; Testnet/synthetic only.

## [0.2.0] - Unreleased

### Added
- Protocol v2: `session_accept.baseline`, the channel cumulative already committed, so several
  sequential sessions can share one funded channel ([ADR 0001](docs/adr/0001-session-baseline.md)).
- `SessionMachine.receiveAccept(channelCumulative:)` refuses a mismatched baseline
  (`baseline_mismatch`); budgets are `baseline + maxSpend`; `sessionSpend` getter.
- `supportedProtocolVersions = {1, 2}`.
- Optional `delay` and `maxDelay` parameters on `FrameChannel` so tests and callers can inject fake-clock retry scheduling and cap exponential backoff.

### Changed
- Frames encode with the lowest version that can represent them: only a `session_accept` with a
  non-zero baseline is v2; all else stays byte-identical to v1.
- `SessionAccept` is no longer a `const` constructor.

## [0.1.0]
- v1 frames, canonical JSON, `Amount`, `SessionMachine`, `UsageMeter`, `Transport` /
  `FrameChannel`, in-memory loopback.
