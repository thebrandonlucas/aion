# Bug: `--help` fails when no Kaifile exists

## Observed

In this repository, which did not yet contain a Kaifile, the published Kai 0.0.4 command failed:

```console
$ nix run github:thebrandonlucas/kai -- --help
Program exited with error: PathErr(NotFound)
```

`kai version` succeeds. Help should be available before project initialization and should not read `Kaifile`.

## Suggested fix

Handle global `-h`/`--help` before resolving or reading the default Kaifile. Add a CLI boundary test that runs from an empty temporary directory and expects status 0 plus usage text.
