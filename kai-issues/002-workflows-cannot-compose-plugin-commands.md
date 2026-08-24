# Feature: workflows should compose registered plugin commands

## Limitation

Kai's registry can add custom commands, but the standard workflow parser accepts only `run <name>` and `build <name>`. A snapshot workflow therefore cannot sequence standard artifact builds followed by a custom `machine` or `snapshot` command.

## Reproduction

```console
$ nix run github:thebrandonlucas/kai -- -f /tmp/Kaifile workflow demo
Program exited with error: PlanningFailed({ ..., message: "workflow step 1 is invalid: 'machine agent'; expected 'run <name>' or 'build <name>'", ... })
```

## Suggested feature

Parse each workflow step as a registered command plus arguments and delegate validation to the registry planner. Preserve sequential action order and cycle detection. For example:

```kai
workflow snapshot {
  steps: [
    "build cloud-cli",
    "build gateway",
    "machine build agent",
    "snapshot publish agent"
  ]
}
```

Structured step objects would be safer long term than shell-like strings. Unknown commands and unsupported backend combinations should produce planning diagnostics before effects begin.

## Resolution

Resolved in Kai 0.0.5. Aion's `workflow prepare` now composes `build aion` with the standard `image agent` command, whose dependency plan invokes the project service and `aion-init` build.
