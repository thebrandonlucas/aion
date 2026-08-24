# Bug: workflow project config collides by block name

## Limitation

A standard workflow scans every standard command config shape before planning its steps. A custom `machine-build` command using a named `machine` block therefore collides with the standard `machine` command, even though the CLI command names differ:

```console
$ ./kai workflow prepare
Program exited with error: PlanningFailed({ backend: "nix", command: "workflow", ..., message: "unknown field 'region'", plugin: "std" })
```

The custom block contains DigitalOcean-specific fields while the standard `machine` shape expects `environment`, `system`, `users`, and `services`.

## Suggested feature

Build workflow project config descriptors from the commands actually requested by workflow steps, or otherwise scope config descriptors by owning command/plugin rather than only the config block header.

## Resolution

Generic workflow invocation landed in Kai 0.0.5. Aion also removed its custom machine command and now uses the standard `machine` block and `image` command, so the colliding project configuration no longer exists.
