# Bug: shared kai.lock loses nodes when flakes have different inputs

## Bug

The plugin's `lock_actions` write two lock files from one `nix flake lock` run:
the shared project `kai.lock` and the generated flake's own `flake.lock`, both
derived from the generated flake's inputs only. Generated flakes in this
project have different inputs:

- `.kai/roc-build/flake.nix` inputs: `nixpkgs`, `roc-overlay`
- `.kai/services/aion/flake.nix` inputs: `nixpkgs`, `kai`
- `.kai/images/agent/flake.nix` inputs: `nixpkgs` and project overlays

Running `./kai build aion` rewrites `kai.lock` for the Roc build. During
`./kai image agent`, the service plan adds `kai`, then the standard image plan
drops it again. The generated flake-local locks remain usable, but the checked-in
shared lock represents only the last planned flake.

## Reproduction

1. Run `./kai image agent`.
2. Compare `.kai/services/aion/flake.lock`, which contains `kai`, with `kai.lock`, which does not.
3. Run `./kai build aion` and inspect the shared lock again.

## Suggested fix

Keep one lock file per generated flake (flake-local `flake.lock` only), or make
the shared lock a merge that never drops nodes and never updates pins already
present in the reference lock (`--reference-lock-file` should win over the
registry for unchanged inputs).
