# Feature: builds need ordered preparation for declared source inputs

## Status on Kai master (`a7373bd`)

Kai now supports named `source` blocks and per-build `inputs`. Selected sources are locked and exposed in the sandbox at `.kai/inputs/<name>`, so fetching Roc packages before an offline build is solved.

The remaining limitation is preparation. `build.run` is one argv and cannot express ordered, argument-safe actions. A Roc app using `basic-cli` and `roc-http` must unbundle both inputs, rewrite nested package URLs to local paths, then invoke `roc build`. A wrapper script could do this, but this repository permits authored tooling only in Roc and does not hide build orchestration in shell tasks.

## Needed capability

Support ordered build actions or a first-class Roc build implementation. Each action must preserve argv boundaries, access declared inputs by stable paths, stop on failure, and remain visible in the generated plan. For Roc, Kai should map declared package URLs to fetched source inputs before compilation.

## Aion impact

`AionPlugin.roc` still owns `build` only to render these preparation steps. Once stock Kai can express them, both Aion binaries can use the standard build command.
