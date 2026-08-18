# Implementation plan: minimal NixOS agent server

## Scope

Build only the path from a declarative Kaifile to a reusable Hetzner Cloud snapshot, then from that snapshot to one customer server with:

- Kai and pi installed;
- PPQ configured but no API key baked into the snapshot;
- a post-payment API-key enrollment command (payment is simulated);
- SSH/terminal interaction;
- a minimal phone-oriented HTTPS web app using pi's headless interface.

Do not implement accounts, real payments, multiple providers, teams, backups, arbitrary deployments, or custom domains.

## Current status: blocked at the Kai boundary

Kai 0.0.4 does not currently provide machine/image, service, or secret commands. Its workflow also cannot compose plugin commands. Nix can perform these operations, but hiding `nix build`, a NixOS flake, or `nixos-anywhere` in a shell task would violate the requirement to stop rather than bypass Kai.

The blockers and proposed fixes are recorded in:

- `kai-issues/001-nixos-machine-image-command.md`
- `kai-issues/002-workflows-cannot-compose-plugin-commands.md`
- `kai-issues/003-services-and-secret-slots.md`
- `kai-issues/004-help-requires-kaifile.md`

Implementation must not start past Phase 0 until Kai can represent the machine. The minimum acceptable fix is a proper typed project Kai plugin, compiled with `xkai`, which renders backend-only Nix into `.kai/`. A shell task containing handwritten Nix commands is not acceptable.

## Fixed MVP decisions

- **Cloud:** Hetzner Cloud.
- **Architecture:** `x86_64-linux` only.
- **Builder:** temporary Ubuntu Hetzner VM installed declaratively with `nixos-anywhere`, then converted to a labeled Hetzner snapshot.
- **Runtime VM:** one server created from that snapshot.
- **Agent:** `pi-coding-agent` from the pinned Nix package set.
- **Model gateway:** PPQ through pi `models.json`, using OpenAI-compatible chat completions.
- **Terminal:** SSH followed by `pi`, optionally inside tmux.
- **Phone:** server-rendered, responsive HTTPS web app backed by a Roc gateway. No frontend framework and no handwritten application JavaScript.
- **TLS/DNS:** one operator-owned base domain in Hetzner DNS; one generated subdomain per server; Caddy is a Nix-provided reverse-proxy dependency.
- **Secrets:** API key is enrolled over SSH after creation and stored outside the Nix store and snapshot with mode `0600`.
- **Provisioner logic:** Roc CLI using Hetzner's HTTP API directly. Do not depend on `hcloud` or a non-Roc provider SDK.

## Required operator inputs

Before the live phases:

- `HCLOUD_TOKEN`: Hetzner project API token with server, image, key, firewall, and DNS rights.
- `AI_CLOUD_ZONE`: an existing DNS zone controlled by the operator.
- `AI_CLOUD_BASE_DOMAIN`: delegated subdomain for generated server names.
- an operator SSH key used only while building the snapshot;
- a customer SSH public key for the created server;
- a funded PPQ API key entered only after server creation.

Never put these values in `Kaifile`, `kai.lock`, source files, generated Nix, snapshots, command arguments, test fixtures, or Git.

## Intended repository shape

```text
Kaifile
kai.lock
plugins/ai-cloud/{Plugin.roc,commands/Machine.roc,implementations/MachineNix.roc}
src/cloud-cli/{main,Cli,Hetzner,Snapshot,Server,State}.roc
src/gateway/{main,Routes,Session,Views}.roc
src/server-cli/{main,Key}.roc
machine/agent.roc-data
fixtures/{hetzner,pi}/
tests/{cloud-cli,gateway,live}.roc
kai-issues/
```

`machine/agent.roc-data` is pure project data consumed by the Kai plugin if the Kaifile body parser cannot cleanly represent all fields. No committed `flake.nix`, NixOS module, shell script, Terraform, or provider YAML is allowed. Generated backend files live only under `.kai/`.

## Phase 0 — make the operation expressible in Kai

1. Add a root `Kaifile` with one pinned Roc environment and named builds for `cloud-cli`, `gateway`, and `server-cli`.
2. List every executable dependency in that environment: Roc nightly through the Roc overlay, `openssh`, `nixos-anywhere`, and tools required by the Roc platforms.
3. Add a typed `machine agent` block containing:
   - target system and Hetzner server type;
   - package names (`pi-coding-agent`, Kai, git, tmux, Caddy);
   - artifact references for `gateway` and `server-cli`;
   - service declarations;
   - firewall ports;
   - PPQ secret-slot name and path;
   - PPQ base URL, provider name, and pinned default model ID.
4. Implement `AiCloudPlugin` in Roc using Kai's registry contract.
5. Add a `machine-build` command whose pure renderer validates the block and emits the NixOS/disko backend files under `.kai/machines/agent/`.
6. Add a `machine-snapshot` command that consumes already-built artifacts and invokes the Roc cloud CLI in snapshot mode.
7. Build the custom Kai executable with the pinned `xkai` command.
8. Add pure renderer tests proving malformed users, ports, paths, package names, missing artifacts, and secret values in config are rejected.
9. Verify no generated Nix or secret is tracked by Git.

**Stop gate:** If the plugin API cannot express this without direct user-facing Nix or cannot consume named artifacts safely, stop, add a new `kai-issues/*.md` reproduction and proposed API change, and report it. Do not add a shell workaround.

**Exit criteria:** `./kai machine-build agent` is a Kai command, validates one Kaifile, and produces only backend output under `.kai/`.

## Phase 1 — build the Roc artifacts through Kai

1. Implement `cloud-cli` with commands:
   - `snapshot build`;
   - `server create`;
   - `server status`;
   - `server destroy`.
2. Implement the Hetzner client with basic-cli HTTPS effects, explicit timeouts, status-code handling, bounded response bodies, and redacted errors.
3. Implement `gateway` with basic-webserver.
4. Implement `server-cli` with `key set`, `key status`, `key clear`, and one-time `bootstrap-link` commands.
5. Build each artifact only through `./kai build <name>`.
6. Add a `check()` test caller for each user-facing boundary:
   - CLI argv to parsed command/result;
   - Hetzner fixture request to typed response/error;
   - gateway HTTP request to response;
   - pi JSONL fixture to visible session state;
   - secret state to redacted status.
7. Add a `ci` workflow containing only supported Kai task/build steps. Keep machine commands separate until Kai supports generic workflow composition.

**Stop gate:** If a Roc platform capability is missing but Nix or a shell tool could provide it, record the Kai/platform limitation before adding that dependency or effect.

**Exit criteria:** Kai builds three immutable artifacts, tests use no live provider or paid model, and logs contain no fixture secrets.

## Phase 2 — define the snapshot in the Kaifile

The machine renderer lowers the `machine agent` data to NixOS with:

1. GPT-partitioned disk configuration suitable for the selected Hetzner VM.
2. A locked NixOS system and pinned Kai package input.
3. `agent` as the only customer login user.
4. SSH public-key authentication only; password and root login disabled.
5. `pi`, Kai, git, tmux, Caddy, `gateway`, and `server-cli` installed; cloud-init accepts only the requested SSH key and non-secret runtime FQDN.
6. Pi global configuration under the agent home:
   - provider `ppq`;
   - OpenAI-compatible API;
   - PPQ base URL;
   - API key resolved at request time from the runtime credential file;
   - pinned default model;
   - session directory under persistent agent-owned state;
   - update checks and install telemetry disabled for snapshot repeatability.
7. Gateway and worker systemd services running as `agent`, with write access only to their state directories.
8. Caddy reading the first-boot FQDN, listening on 80/443, and proxying only to the gateway on loopback.
9. Firewall allowing 22, 80, and 443 only.
10. A first-boot unit that regenerates machine identity and SSH host keys, then creates a one-time web bootstrap token.
11. `/etc/ai-cloud/build.json` containing no secrets, only:
    - Kaifile digest;
    - `kai.lock` digest;
    - source Git revision;
    - artifact digests;
    - build timestamp and architecture.

The PPQ credential file must not exist in the built machine or snapshot.

**Exit criteria:** evaluation/build succeeds through `./kai machine-build agent`; inspection proves the closure contains no API key and provenance matches the current Kaifile/lock.

## Phase 3 — create and validate the Hetzner snapshot

`./kai machine-snapshot agent` performs these idempotent steps through the Roc CLI:

1. Validate required environment variables without printing values.
2. Build or locate the three named Kai artifacts and verify digests.
3. Create a temporary, uniquely labeled Hetzner SSH key and firewall.
4. Create a temporary Ubuntu builder VM.
5. Wait for SSH with a bounded retry policy.
6. Run the Kai-generated `nixos-anywhere` installation against the generated machine backend.
7. Reboot and wait for the NixOS health command.
8. Verify remotely:
   - NixOS architecture;
   - `kai version`;
   - `pi --version`;
   - gateway/Caddy service state;
   - absent PPQ credential;
   - `/etc/ai-cloud/build.json` digests.
9. Shut down the builder cleanly.
10. Create a Hetzner snapshot labeled with project, source revision, Kaifile digest, architecture, and schema version.
11. Poll until the snapshot is available.
12. Write non-secret local state under `.kai/state/agent-snapshot.json`.
13. Delete the builder VM, temporary key, and temporary firewall on both success and failure; retain the snapshot only after all checks pass.

**Failure rule:** print the retained resource IDs needed for manual cleanup, never credentials.

**Exit criteria:** a repeatable labeled snapshot exists and its ID/provenance is recorded as backend state.

## Phase 4 — create the customer server from the snapshot

The customer-facing command is:

```console
$ ./.kai/artifacts/cloud-cli server create --ssh-key ~/.ssh/id_ed25519.pub
```

It must:

1. Load the latest compatible snapshot state.
2. Validate the public key locally.
3. Create a customer firewall and register/deduplicate the public key.
4. Create one server from the snapshot with provenance labels and non-secret first-boot data containing its generated FQDN.
5. Wait for first-boot health over SSH.
6. Create that FQDN in Hetzner DNS and restart Caddy after DNS resolves.
7. Wait for DNS and HTTPS readiness.
8. Fetch the one-time bootstrap link over SSH, display it once, and invalidate retrieval after use.
9. Print server ID, hostname, SSH command, PWA URL, key-enrollment command, and destroy command.
10. Save non-secret instance state under `.kai/state/servers/<id>.json`.

No PPQ key is accepted by `server create`; this models the payment-before-secret boundary.

**Exit criteria:** creation uses only the snapshot—not an in-place rebuild—and the remote provenance equals the snapshot record.

## Phase 5 — enroll the PPQ API key after simulated payment

For the MVP, “payment complete” is a manual SSH step:

```console
$ ssh agent@<hostname> ai-cloud-server key set
```

1. `server-cli` reads the key from a no-echo terminal prompt or stdin, never argv.
2. Write atomically to the declared runtime credential path with mode `0600`.
3. Validate only by making a minimal authenticated PPQ models request.
4. On failure, remove the new value or restore the previous valid value.
5. Restart/notify the worker without rebooting.
6. `key status` reports only configured/not-configured and validation time.

**Stop gate:** If basic-cli cannot securely read a secret or set required permissions, stop and report the missing Kai/Roc capability. Do not use command arguments, cloud-init user-data, or a world-readable environment file.

**Exit criteria:** both interactive pi and the gateway can use PPQ, while the snapshot and provider metadata remain key-free.

## Phase 6 — terminal and phone interaction

### Terminal

1. Customer runs `ssh agent@<hostname>`.
2. `pi --provider ppq --model <pinned-model>` works in any project directory.
3. Document `tmux new -As agent` for a persistent interactive terminal session.
4. Confirm disconnect/reconnect does not delete pi's saved sessions.

### Minimal phone web app

1. Serve responsive server-rendered HTML with tiny inline CSS.
2. Serve a web manifest over HTTPS; do not create AI-generated icon/media assets.
3. Exchange the one-time bootstrap token for a Secure, HttpOnly, SameSite cookie, then remove the token from the URL.
4. Expose only:
   - current session/status;
   - prompt form;
   - abort/new-session actions;
   - recent assistant text and tool status;
   - manual logout.
5. Use a dedicated PWA pi session. Queue prompts to a Roc worker which invokes pi's JSON/print mode and persists JSONL; render progress through short server-side refreshes. Do not expose pi RPC stdin/stdout directly to the network.
6. Serialize prompts per session and reject duplicate form submissions with request IDs.
7. Keep all mutable session data under `/var/lib/ai-cloud`, outside the Nix store.

A service worker/offline mode is explicitly out of scope because it requires browser JavaScript; the MVP is an HTTPS, manifest-backed, home-screen-friendly web app with server-rendered interaction.

**Exit criteria:** a phone browser can authenticate, submit a prompt, leave, return, and read the result; SSH pi remains independently usable.

## Phase 7 — one live acceptance test

Run only after explicit confirmation because it creates billable resources and consumes PPQ credit.

1. Build all artifacts through Kai.
2. Build one snapshot through the custom Kai machine command.
3. Create one server through the Roc CLI command.
4. Assert remote Kaifile/lock/artifact provenance.
5. Enroll a short-lived or low-balance PPQ key.
6. Submit one data-driven prompt through the PWA and verify the visible answer.
7. Submit one prompt through SSH pi and verify the answer.
8. Reconnect to both interfaces and verify persisted sessions.
9. Clear the key.
10. Destroy the server, DNS record, key, and firewall.
11. Keep or delete the snapshot only as explicitly requested.
12. Confirm via provider API that no unexpected labeled resources remain.

## Commit sequence

Keep every commit below the repository's `+300/-300` hard limit, preferably near 50 lines:

1. Kai machine plugin skeleton and tests.
2. Kaifile environments/builds and lock.
3. Hetzner request/response types and fixtures.
4. Snapshot CLI lifecycle.
5. Server create/status/destroy lifecycle.
6. Gateway routes/views.
7. Server key enrollment.
8. Machine renderer: base NixOS/users/SSH.
9. Machine renderer: pi/PPQ/service configuration.
10. Snapshot and server smoke checks.
11. PWA session flow.
12. Live acceptance test and concise operator documentation.

Use plain descriptive commit messages, `--no-gpg-sign`, and no co-author lines.

## Definition of done

All three requested outcomes are demonstrated:

1. `cloud-cli server create --ssh-key ...` is a Roc command that creates a server from the Kai-built NixOS Hetzner snapshot.
2. Snapshot and server provenance prove the server came from the checked-in Kaifile and pinned `kai.lock`; no handwritten Nix is a project input.
3. The customer can use pi over SSH/terminal and submit/read work from the minimal phone HTTPS web app after enrolling a PPQ API key.

No implementation beyond Phase 0 should proceed while the machine/image Kai limitation remains unresolved.
