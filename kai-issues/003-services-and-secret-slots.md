# Feature: operator-to-machine runtime secret provisioning

## Status on Kai master (`a7373bd`)

Kai now implements standard `service` and `secret` configuration. The Nix renderer composes a `kai.build/v1` artifact into a `kai.nixos.service/v1` module and maps each runtime secret from `/run/kai/secrets/<name>` through systemd `LoadCredential`.

Kai still has no command or typed artifact for delivering a secret value to a built or deployed machine:

```console
$ kai -f /tmp/Kaifile secret set ppq
Program exited with error: UnknownCommand
```

## Needed capability

Add an argument-safe operator-to-machine provisioning boundary that can set, rotate, inspect the presence of, and remove runtime secrets without putting values in the Kaifile, Nix store, image, process arguments, logs, or build artifacts. Deployment tools should consume a typed provisioning manifest instead of knowing backend-specific credential paths.

## Aion impact

Aion currently transfers the PPQ key over SSH into a mode-`0600` runtime file. The image and Kaifile contain only a key reference. This handoff remains Aion code until Kai can describe and execute runtime secret provisioning.
