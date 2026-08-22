# Aion

Ad-hoc NixOS agent machines on DigitalOcean, defined in a `Kaifile` and operated by a Roc CLI. See `plan.md` for the MVP scope and `kai-issues/` for Kai limitations found while building this.

## Operator setup

```sh
nix run github:thebrandonlucas/kai -- -f Kaifile.bootstrap run bootstrap-kai
./kai build aion-init
./kai build aion
./kai machine-build agent
```

`machine-build` produces `.kai/artifacts/agent-image/aion-agent.qcow2.gz`.

## Provision one machine

```sh
# Host the image at a temporary public HTTPS URL, then:
export DIGITALOCEAN_TOKEN=...      # never echoed or logged
export AION_MODEL_API_KEY=...      # short-lived PPQ key
./.kai/artifacts/aion image import https://example.invalid/aion-agent.qcow2.gz
./.kai/artifacts/aion create demo
./.kai/artifacts/aion demo shell        # interactive SSH
./.kai/artifacts/aion demo shell pi     # pi with the pinned PPQ model
./.kai/artifacts/aion destroy demo
```

`create` registers `~/.ssh/id_ed25519.pub`, boots a `s-2vcpu-4gb` Droplet in `nyc3` from the imported image, and enrolls the model key over SSH (mode `0600`, never in argv, API payloads, logs, the image, or git).

State lives under `.aion/`. Cleanup after `destroy`: the imported image and the `aion-<name>` SSH key are retained and printed for manual deletion.
