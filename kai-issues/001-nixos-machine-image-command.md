# Feature: first-class NixOS machine image builds

## Limitation

Kai 0.0.4 can create package environments, run tasks, and build ordinary file/directory artifacts. It cannot describe a NixOS host, lower services/users/firewalls into a NixOS module, or produce a machine image/snapshot input.

This project needs one Kaifile to define the packages and runtime configuration installed in a NixOS cloud snapshot. Nix can build this through `nixosSystem`, image builders, and `nixos-anywhere`, but invoking those directly from a task would bypass the required Kai abstraction.

## Reproduction

```console
$ nix run github:thebrandonlucas/kai -- -f /tmp/Kaifile machine agent
Program exited with error: UnknownCommand
```

## Suggested feature

Add a typed `machine` or `image` command/artifact to the standard plugin:

```kai
machine agent {
  environment: server
  system: "x86_64-linux"
  users: ["agent"]
  services: ["gateway"]
}
```

The Nix backend should render a NixOS module/flake, build a named machine artifact, record its target architecture and closure, and expose it to deployment/snapshot plugins without requiring user-authored Nix. Unsupported host capabilities should fail explicitly.

## Project decision

Do not hide a direct `nix build` or `nixos-anywhere` command in a shell task. Implementation is blocked until this is added to Kai or implemented as a proper project Kai plugin with the same typed boundary.
