# Feature: services and runtime secret slots

## Limitation

Kai 0.0.4 has no implemented `service` or `secret` commands. Both are design notes only. This project needs to install a Roc gateway as a boot service and provision a PPQ API key after the simulated payment without placing its value in the Kaifile, Nix store, snapshot, process arguments, or logs.

## Reproduction

```console
$ nix run github:thebrandonlucas/kai -- -f /tmp/Kaifile service apply gateway
Program exited with error: UnknownCommand
$ nix run github:thebrandonlucas/kai -- -f /tmp/Kaifile secret set ppq
Program exited with error: UnknownCommand
```

## Suggested feature

Implement the service model proposed in `docs/plans/features/service.md`, initially lowering to NixOS/systemd. Add secret **references** and runtime credential paths, not secret values:

```kai
secret ppq-key { provision: runtime }
service gateway {
  artifact: gateway
  secrets: ["ppq-key"]
  restart: on-failure
}
```

The Nix backend should use systemd credentials or a root/user-owned runtime file outside the Nix store. Kai should support interactive or stdin provisioning, rotation, presence checks, and redaction.

## Project decision

The snapshot may declare an empty PPQ credential slot, but must never contain the credential. Until Kai supports services/secrets, a project machine plugin must lower these declarations explicitly; no plaintext environment file in source or provider user-data is acceptable.

## Status after the DigitalOcean pivot

Unblocked for the MVP: the `aion` CLI provisions the model key itself over SSH (mode `0600` runtime file, `!cat` resolution in pi's `models.json`), outside Kai. Nothing in the Kaifile or image references a secret value. This issue becomes load-bearing again when the hosted service needs Kai to declare machine secret slots (e.g. `secret ppq-key { provision: runtime }`) or systemd `service` blocks in the `machine` block — at that point the SSH handoff should be replaced by the typed Kai feature.
