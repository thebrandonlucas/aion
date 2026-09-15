# Feature: machines need external flake packages

## Limitation on Kai master (`d4a7fdd`)

Kai locks `source` blocks as non-flake inputs and exposes them to selected builds. Machine environment packages instead resolve only from the configured Nixpkgs package set and its overlays.

Paseo publishes `packages.${system}.paseo` but no overlay, so the homelab machine cannot install its CLI and daemon package through an ordinary environment.

## Needed capability

Let a locked flake source expose one named package output that an environment can install. For example, the design needs an equivalent of:

```text
source paseo {
  url: "github:getpaseo/paseo/<revision>"
}

external package paseo {
  source: paseo
  attribute: "packages.${system}.paseo"
}

environment dev {
  packages: ["pi-coding-agent", "paseo"]
}
```

The exact syntax can differ. Kai only needs to:

- lock the flake source in the Kaifile lock;
- select the package for the machine's target system;
- install it in the machine environment; and
- fail clearly when the source, attribute, or target package is unavailable.

External modules, overlays, and arbitrary Nix expressions are separate capabilities.
