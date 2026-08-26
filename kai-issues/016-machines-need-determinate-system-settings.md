# Feature: machines need determinate-system settings

## Limitation on Kai master (`a7373bd`)

A machine selects an environment and target system, but Kaifile cannot configure the package manager installed in that machine. The Nix backend therefore emits default NixOS daemon settings even when software in the environment requires specific Nix capabilities.

## Needed capability

Let a determinate-system backend expose validated machine settings with secure defaults. For Nix this includes feature gates such as `nix-command` and `flakes`, substituters and trusted keys, store optimization, garbage collection, and trusted-user policy.

Settings must remain typed Kaifile data rather than raw `nix.conf` text. Security-sensitive changes such as trusted users or substituters should be explicit in plans and reject unsupported backend combinations.

## Aion impact

Kai runs inside the agent and uses the modern Nix CLI and flakes. Aion currently enables those features in its generated host module because the standard machine schema cannot express them.
