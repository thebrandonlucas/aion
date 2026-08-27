# Feature: machine images need extensible target profiles

## Limitation on Kai master (`a7373bd`)

The standard `image` command always renders one generic QEMU QCOW2 configuration. A cloud image may require a supported NixOS guest module, boot mode, metadata agent, disk settings, networking behavior, or output variant. Kaifile cannot select those requirements.

## Needed capability

Add typed, extensible image target profiles. A profile should declare guest capabilities and backend lowering separately from the machine's application configuration, for example a cloud QCOW2 target versus a local QEMU target.

Profiles may be supplied by Kai packages/plugins, but projects must select them in Kaifile without shadowing `image` or emitting handwritten Nix. Profile artifacts need target-system and image-format metadata so deployment tools can reject incompatible images.

## Aion impact

Aion needs DigitalOcean's NixOS guest configuration and BIOS-compatible QCOW2 output. Its plugin currently injects those settings into the service module even though they are image-target policy.
