# Feature: builds need declared Roc package source inputs

## Limitation

Kai 0.0.5 copies project source into a sandboxed Nix build and runs the configured build command without network access. A normal Roc application whose platform is a release URL therefore cannot build:

```console
$ ./kai build aion-init
...
Failed to download and extract this package:
https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst
Error: DownloadFailed.
```

Nix can fetch the archive by URL and hash before entering the sandbox, but Kai has no field for non-package source inputs. Allowing network access during the build would make it impure.

## Suggested feature

Allow builds or environments to declare fetched source inputs:

```kai
source basic-cli {
  url: "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst"
  hash: "sha256-04xUSXYJU4IHIf9/kjbfTghdgokYBFvZDfuTLWUg7kc="
}
```

Kai should fetch and verify these before the sandboxed build, expose a stable local path to the build, and include them in lock/provenance data. This is needed for ordinary Roc package/platform dependencies, not only this project.

## Project decision

Until Kai supports source inputs, the project plugin owns its Roc `build` command and renders a Nix `fetchurl` using the pinned release URL and hash. This preserves a typed Kai boundary and sandboxed build; it does not enable networked builds or place handwritten Nix in the repository.
