# Releasing and consuming Sideband-protocol

Sideband-protocol is a Dart library. There is nothing to deploy: it is released as a git tag and consumed as a git dependency.

## Consuming it

```yaml
dependencies:
  sideband_protocol:
    git:
      url: https://github.com/Sideband34/Sideband-protocol.git
      ref: v0.1.0   # or main
```

Sideband-mobile depends on it this way. Sideband-gateway mirrors the frame field names and limits and pins them with a synthetic session transcript fixture.

## Checks that gate every change

CI runs on every push and pull request (`.github/workflows/ci.yml`, job `test`):

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

The `docs` job (`.github/workflows/docs.yml`) checks that the required project documents exist and that relative markdown links resolve.

## Environment boundary

Testnet and synthetic data only. There is no staging or production environment for this package, and no secrets are used anywhere in it.

## Releases

Tags are lowercase `vX.Y.Z`. Each release lists the sibling versions it was tested with. Frame or voucher format changes need a version bump, updated fixtures and a linked change in every consumer. See [ADR 0001](./adr/0001-session-baseline.md) for the protocol v2 baseline.
