# Feature: build artifacts need a declared runtime environment

## Status on Kai master (`a7373bd`)

A Roc build can name a Kai environment containing external runtime tools such as `awscli2`, OpenSSH, and `coreutils`, but the emitted artifact is a bare executable. Running `.kai/artifacts/aion` directly does not put those declared tools on `PATH`.

A task now provides a non-interactive execution boundary through its named environment. It solves fixed project operations, but it does not associate that runtime closure with the build artifact or forward invocation arguments:

```console
$ ./kai shell cli -- aws --version
Program exited with error: PlanningFailed({ ..., message: "shell accepts at most one config name", ... })
```

## Suggested feature

Let builds distinguish build-time and runtime packages, then emit an executable app/wrapper whose `PATH` contains only its declared runtime closure. Alternatively, support `kai shell <environment> -- <command> [args...]` with argument-safe process execution and exit-code propagation.

## Project decision

Aion's fixed operator workflows use Kai tasks. The task invokes a small Roc launcher inside the declared environment; direct artifact execution remains unsupported.
