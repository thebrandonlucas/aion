# Feature: machines need typed external flake packages and modules

## Limitation on Kai 0.0.5

Kai can lock an external `source`, but that source is exposed only to a `build` that selects it through `inputs`. Machine and environment `packages` resolve attributes from their Nixpkgs package set, optionally modified by flake overlays.

There is no typed way to consume either of these outputs from a source flake:

- `packages.${system}.paseo`
- `nixosModules.paseo`

Paseo publishes both, but does not publish an overlay. Treating its flake URL as an environment overlay therefore does not work. A nested `nix build path:.kai/inputs/paseo#paseo` inside a build, or a project plugin that imports the module directly, would hide the missing dependency and module boundary instead of expressing it through Kai.

Standard generated services do not solve this. They consume one local `kai.build/v1` executable and generate Kai's fixed systemd module. They cannot compose an upstream NixOS module whose options configure its package, user, persistent home, listen address, and relay behavior.

## Needed capability

Let a locked source expose typed package and NixOS-module artifacts, with explicit flake attributes and target-system validation. A machine should be able to request both without handwritten Nix or a custom command override. For example, the design needs equivalents of:

```text
source paseo {
  url: "github:getpaseo/paseo/<revision>"
}

external package paseo {
  source: "paseo"
  attribute: "packages.${system}.paseo"
}

external module paseo {
  source: "paseo"
  attribute: "nixosModules.paseo"
}

machine paseo {
  packages: ["paseo"]
  modules: ["paseo"]
}
```

The exact syntax can differ. Required behavior:

- lock the external source in `kai.lock`;
- select and build its package for the machine target;
- verify package and module output types before composing the machine;
- allow validated module configuration without arbitrary Nix in the Kaifile;
- include the source identity and selected attributes in machine metadata;
- fail during planning when a selected output or target is unavailable.

## Aion impact

The proposed Aion Paseo product must compose Paseo's pinned package and NixOS module into a DigitalOcean image. Per product direction, implementation stops here rather than adding an Aion-only Nix/plugin escape hatch. Once Kai has this boundary, Aion can add the product, provision Pi credentials, start Paseo's outbound relay connection, and return a pairing offer to the customer.
