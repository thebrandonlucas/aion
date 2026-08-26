# Plan: minimal Aion vertical slice

## Goal

Prove one complete path:

```text
Kaifile -> Kai-built DigitalOcean NixOS image -> `aion create demo`
-> SSH shell -> working remote pi prompt -> destroy
```

This is an operator-run proof, not a public service.

## Fixed scope

- DigitalOcean, one region, one `x86_64-linux` Droplet size.
- One hard-coded `machine agent` configuration.
- Image contains Kai, pi, git, the Aion server helper, and a non-root `aion` user.
- Local CLI commands:
  - `aion image import <https-url>`
  - `aion create <name>`
  - `aion <name> shell`
  - `aion <name> shell pi`
  - `aion destroy <name>`
- `create` uses `~/.ssh/id_ed25519.pub`, `DIGITALOCEAN_TOKEN`, and a short-lived `AION_MODEL_API_KEY`.
- Pi uses one pinned PPQ-compatible provider/model configuration.
- Local non-secret machine state lives under `.aion/`.

Defer signup, payment, Aion model metering, the web app, services, subdomains, user Kaifiles, multiple machines per account, multiple providers, backups, and production hardening.

## Constraints

- All authored code is Roc. The normal Zig Roc bootstrap is the only exception.
- Every dependency and build is declared in `Kaifile` and run through Kai.
- Generated Nix is Kai backend output under `.kai/`; do not check in Nix, shell scripts, Terraform, or provider configuration.
- Use DigitalOcean's HTTPS API directly from Roc; do not use `doctl` or a provider SDK.
- Use OpenSSH as a Kai dependency for terminal handoff and remote initialization.
- Do not add tests. Validate with the single live acceptance run below.
- Record each Kai limitation in `kai-issues/`; never hide a direct Nix command in a task.

## 1. Establish the Kai boundary

1. Add a root `Kaifile` with pinned environments and builds for the local `aion` CLI and remote `aion-init` helper.
2. Define the host with Kai's standard typed `machine agent` block and build it with the standard `image` command.
3. Keep a small Roc Kai plugin only for the Aion-specific NixOS service module and the Roc package build preparation that stock Kai cannot yet express.
4. Build the project Kai binary with `xkai`, following `../kai-blueprint`.

**Stop gate:** if Kai cannot compose the Aion service into its standard image without checked-in Nix or a shell-task escape hatch, document the missing capability and stop.

## 2. Build the one agent image

The generated NixOS image must:

- boot on DigitalOcean with cloud-init SSH-key injection;
- create only the non-root `aion` login and disable password/root SSH;
- expose only SSH;
- install the Kai and pi versions pinned by the Kaifile;
- install `aion-init`;
- contain no per-user Pi configuration or credential;
- accept writable Pi configuration and the model key through runtime provisioning.

Run `./kai workflow prepare`. The standard `image agent` plan composes the Aion service and recursively builds `aion-init`; the workflow also builds the local `aion` CLI.

## 3. Implement the Roc CLI slice

Implement only the API and process operations needed by the five commands:

1. `image import` submits the Kai-built compressed image URL to DigitalOcean, polls until ready, and records its image ID. Hosting/uploading the image is an operator prerequisite for this slice.
2. `create` validates the name and inputs, registers/deduplicates the SSH key, creates a Droplet from that image, polls for an address, and saves non-secret state.
3. After SSH is ready, `create` stages `AION_MODEL_API_KEY` plus the fixed MVP Pi model/settings JSON in a private local directory and transfers them over SSH. `aion-init` installs writable mode-`0600` user files; the key never appears in image data, JSON, API payloads, arguments, logs, or local state.
4. `shell` replaces the local process with interactive SSH.
5. `shell pi` replaces it with TTY-enabled SSH running pi from the provisioned user settings.
6. `destroy` deletes the Droplet and local state, and reports enough IDs to clean up manually if deletion fails.

Errors must include the failed operation and provider status without printing tokens, keys, or response bodies that may contain them.

## 4. Run one live acceptance proof

This run is explicit and billable:

1. Build both Roc artifacts and the image through the project Kai binary.
2. Put the compressed image at a temporary HTTPS URL and import it with `aion image import`.
3. Run `aion create demo`.
4. Through `aion demo shell`, confirm NixOS, Kai, pi, the non-root user, SSH restrictions, and model-key file permissions.
5. Run `aion demo shell pi`, submit one prompt, and receive a model response.
6. Disconnect and reconnect once.
7. Run `aion destroy demo` and confirm through the API that the Droplet is gone.
8. Remove the temporary hosted image and short-lived model key. Retain or delete the imported DigitalOcean image explicitly.

## Completion criteria

The slice is complete when the exact path in **Goal** succeeds without handwritten deployment code outside Roc, without bypassing Kai, and without placing a secret in the image or repository.

## Work chunks

Keep each commit below `+300/-300`, preferably near 50 lines:

1. Kaifile, standard Kai image, and Aion service configuration.
2. Remote initialization helper and image configuration.
3. DigitalOcean image import and polling.
4. Droplet create/state/destroy.
5. SSH, key enrollment, and pi handoff.
6. Concise operator instructions and live proof notes.
