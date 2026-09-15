# Feature: machine images need extensible target profiles

## Limitation on canonical SOPS Kai (`b6b1178`)

The standard `image` command always renders one generic QEMU QCOW2 configuration. A cloud image may require a supported NixOS guest module, boot mode, metadata agent, disk settings, networking behavior, or output variant. Kaifile cannot select those requirements.

Aion reproduced the missing boundary against the canonical SOPS branch with:

```kai
machine agent {
  environment: agent
  system: "x86_64-linux"
  profile: digital-ocean
}
```

`kai machine agent` rejects this before planning:

```text
error: unknown field 'profile'
  --> Kaifile:121:3
```

Without a target profile, standard Kai cannot produce the DigitalOcean image or ensure that DigitalOcean metadata SSH configuration survives later machine activation.

## Needed capability

Add typed, extensible image target profiles. A profile should declare guest capabilities and backend lowering separately from the machine's application configuration, for example a cloud QCOW2 target versus a local QEMU target.

Profiles may be supplied by Kai packages/plugins, but projects must select them in Kaifile without shadowing `image` or emitting handwritten Nix. Profile artifacts need target-system and image-format metadata so deployment tools can reject incompatible images.

## Aion impact

Aion needs DigitalOcean's NixOS guest configuration and BIOS-compatible QCOW2 output. Its plugin currently injects those settings into the service module even though they are image-target policy.
