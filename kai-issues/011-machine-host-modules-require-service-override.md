# Feature: machines need typed host extensions

## Status on Kai master (`a7373bd`)

Standard machines can declare packages, normal users, native NixOS services, and generated executable services. Generated services expose only `artifact`, `secrets`, and `restart`; machine planning requests the literal `service` command and accepts only `kai.nixos.service/v1`.

A machine cannot compose typed host policy for guest/image compatibility, SSH policy, firewall rules, managed files, user properties, or ordered boot actions. A custom producer can emit the service artifact only by shadowing the standard `service` command.

## Needed capability

Add a backend-neutral host-extension artifact and let a machine reference multiple producers explicitly, for example through an `extensions` field. The Nix backend may lower validated extensions to NixOS modules, but Kaifiles and projects should not contain handwritten Nix.

Extensions need typed dependency requests so they can consume build artifacts and compose without command shadowing. Unsupported capabilities must fail during planning rather than being ignored.

## Aion impact

Aion currently shadows `service` to install its bootstrap helper and express cloud guest, SSH, firewall, file, and boot policy. This is the primary blocker to deleting `AionPlugin.roc`.
