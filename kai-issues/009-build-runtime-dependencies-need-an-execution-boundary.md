# Feature: build artifacts need a declared runtime environment

## Limitation

A Roc build can name a Kai environment containing external runtime tools such as `awscli2`, OpenSSH, and `coreutils`, but the emitted artifact is a bare executable. Running `.kai/artifacts/aion` directly does not put those declared tools on `PATH`. The tools are available only after entering `kai shell cli` interactively.

Kai also rejects a one-command shell invocation, so the operator cannot use Kai as a direct execution boundary:

```console
$ ./kai shell cli -- aws --version
Program exited with error: PlanningFailed({ ..., message: "shell accepts at most one config name", ... })
```

## Suggested feature

Let builds distinguish build-time and runtime packages, then emit an executable app/wrapper whose `PATH` contains only its declared runtime closure. Alternatively, support `kai shell <environment> -- <command> [args...]` with argument-safe process execution and exit-code propagation.

## Project decision

`awscli2` remains declared in the `cli` environment, and operator documentation requires entering `./kai shell cli` before running Aion. Do not hide the dependency in a direct Nix command or shell task.
