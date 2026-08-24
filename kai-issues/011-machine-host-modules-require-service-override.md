# Feature: compose typed host modules without overriding `service`

## Limitation

Kai 0.0.5 can build a generic machine/image and compose generated service artifacts, but the standard `service` command only describes a long-running executable. Aion also needs host policy: DigitalOcean metadata support, SSH restrictions, firewall rules, users, files, and a boot-time key installer.

A custom plugin can produce the `kai.nixos.service/v1` artifact consumed by the standard image planner only by owning the `service` command. This replaces the standard service schema for the custom Kai binary and makes `kai help` list both service registrations.

## Reproduction

```kai
machine agent {
  environment: agent
  system: "x86_64-linux"
  users: ["aion"]
  services: ["aion"]
}
```

The image planner resolves `services: ["aion"]` by requesting `service nix aion`; it cannot request a differently named custom command that returns the same typed artifact.

## Suggested feature

Add a typed host-module/configuration artifact and let `machine`/`image` reference its producing command, or let service declarations select an owning command without replacing the standard `service` command. The composition boundary should remain backend-neutral and reject unsupported host policy explicitly.

## Project decision

Aion temporarily owns `service` in `plugins/aion/AionPlugin.roc`, emits only its DigitalOcean host module, and leaves machine/image construction to Kai's standard commands.
