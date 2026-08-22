# Bug: shared kai.lock loses nodes when flakes have different inputs

## Bug

The plugin's `lock_actions` write two lock files from one `nix flake lock` run:
the shared project `kai.lock` and the generated flake's own `flake.lock`, both
derived from the generated flake's inputs only. Two generated flakes in this
project have different inputs:

- `.kai/roc-build/flake.nix` inputs: `nixpkgs`, `roc-overlay`
- `.kai/machines/agent/flake.nix` inputs: `nixpkgs`, `kai`

Running `./kai build aion` (roc-build flake) rewrote `kai.lock` and dropped the
`kai` node that `.kai/machines/agent` needs; it also bumped the pinned
`nixpkgs` revision instead of preserving the previously locked one. Running
`machine-build` afterwards rewrites `kai.lock` again to add `kai` back, so the
two commands flip-flop the checked-in lockfile and neither state serves both
flakes.

## Reproduction

1. `./kai machine-build agent` (writes kai.lock with a `kai` node).
2. `./kai build aion` (rewrites kai.lock; `kai` node gone, `nixpkgs` rev changed).
3. `git diff kai.lock` shows the node loss and unintended input updates.

## Suggested fix

Keep one lock file per generated flake (flake-local `flake.lock` only), or make
the shared lock a merge that never drops nodes and never updates pins already
present in the reference lock (`--reference-lock-file` should win over the
registry for unchanged inputs).
