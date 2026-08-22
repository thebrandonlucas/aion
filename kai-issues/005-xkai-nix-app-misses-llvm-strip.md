# Bug: packaged `xkai` cannot find `llvm-strip`

## Observed

Kai 0.0.5's `xkai` app compiles a valid custom plugin, then fails while stripping the generated binary:

```console
$ nix run github:thebrandonlucas/kai#xkai -- build plugins/aion/MachinePlugin.roc
0 errors and 0 warnings found ... while successfully building
Program exited with error: FailedToGetExitCode({ ... program: OsStr.utf8("llvm-strip") ... err: NotFound })
```

The flake's `xkai` wrapper declares `llvmPackages.bintools` as a runtime input, but `llvm-strip` is not available to the running app on this NixOS host.

## Expected

The published `xkai` app should include the exact strip executable used by `Builder.roc`, so the documented `xkai build` command succeeds without an ambient development shell.

## Local bootstrap

This project runs `xkai` from a Kai environment which explicitly includes `llvmPackages.bintools`. This does not bypass the machine/image Kai boundary; it only supplies the missing runtime dependency to the standard plugin-builder bootstrap.
