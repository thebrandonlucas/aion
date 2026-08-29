# Aion

Ad-hoc NixOS agent machines on DigitalOcean, defined in a `Kaifile` and operated by a Roc CLI. See `plan.md` for the MVP scope and `kai-issues/` for Kai limitations found while building this.

## Operator setup

1. Create a custom-scoped DigitalOcean API token. The exact scope union required by this CLI is `actions:read`, `droplet:create`, `droplet:delete`, `droplet:read`, `image:create`, `image:delete`, `image:read`, `regions:read`, `sizes:read`, `snapshot:read`, `ssh_key:create`, `ssh_key:read`, `tag:create`, `tag:read`, and `vpc:read`. This includes DigitalOcean's dependency scopes for create/delete, plus `tag:create` for each unique operation tag and `tag:read` for filtered reconciliation. See [Scopes for API Tokens](https://docs.digitalocean.com/reference/api/scopes/), [`droplet:create`](https://docs.digitalocean.com/reference/api/scopes/droplet/create), [`image:create`](https://docs.digitalocean.com/reference/api/scopes/image/create), and [`tag:create`](https://docs.digitalocean.com/reference/api/scopes/tag/create).
2. Create one private, Standard DigitalOcean Space in `nyc3`, with versioning disabled and no public bucket policy or listing.
3. Create a limited Spaces key with Read/Write/Delete access only to that Space. This is separate from the API token.
4. With separate bucket-administrator credentials, configure an enabled lifecycle rule that expires the `aion-imports/` prefix after one day and aborts incomplete multipart uploads after one day. Verify the rule with DigitalOcean's [lifecycle instructions](https://docs.digitalocean.com/products/spaces/how-to/configure-lifecycle-rules/). The rule is a fallback for interrupted or uncertain cleanup, not the normal deletion path.
5. Bootstrap the project Kai binary once, then use only Kai commands for operator workflows. Tasks enter their declared runtime environments and a Roc launcher reads the ignored `.env` file:

```sh
nix run github:thebrandonlucas/kai -- -f Kaifile.bootstrap run bootstrap-kai
./kai workflow prepare
```

The project plugin adds only Aion's Roc package build and NixOS service configuration. Kai's standard `image` command composes that service into the machine and produces `.kai/artifacts/images/agent/result/agent.qcow2`.

To enter a dependency-complete shell with the latest Aion CLI built from the working tree and `.env` loaded, run:

```sh
./kai workflow aion-shell
aion <command>
```

The interactive shell receives every value in `.env`; exit it when finished.

`workflow prepare` is the non-billable preparation command. It builds the CLI, environment launcher, initializer, and agent image; it does not contact DigitalOcean, Spaces, Everpaid, or model APIs.

## Test the full pipeline

```sh
# Build the project Kai binary once.
nix run github:thebrandonlucas/kai -- -f Kaifile.bootstrap run bootstrap-kai

# Build the CLI and image, import it, then confirm availability.
./kai workflow import-image

# Create the demo Droplet and provision Pi configuration.
./kai run create-demo

# Verify SSH, run Pi, then reconnect.
./kai run shell-demo
./kai run shell-pi-demo
./kai run shell-demo

# Delete the billable Droplet and imported custom image.
./kai run destroy-demo
./kai run delete-image
```

The commands prompt before importing an image, creating a Droplet, or deleting an image. The older `image import <https-url>` flow remains available for an operator-hosted URL.

`create` registers `~/.ssh/id_ed25519.pub`, boots the fixed `s-2vcpu-4gb` size in fixed region `nyc3`, then provisions the model key and user-owned Pi configuration over SSH. Model choices are runtime state, not part of the shared image. Check current DigitalOcean Droplet, custom-image, and Spaces pricing before operating.

## Product catalog

Product metadata lives under `products/<name>/product.json`. It contains display and pricing data plus the path and machine name for an ordinary Kai project; it does not add product syntax to the project's `Kaifile`.

List products or create a machine from one inside the Aion shell:

```sh
./kai workflow aion-shell
aion products
aion create demo gump
```

The bundled `gump` entry resolves `../gump/Kaifile`. Creation asks that project's Kai binary to build `machine gump`, so the image contains a Gump binary built from the current adjacent Gump source.

If creation was interrupted after DigitalOcean accepted the Droplet, a later create prints its ID, status, public IP, and exact recovery command. `aion recover <name> <droplet-id>` validates the provider name, active state, Aion operation tag, operator SSH key, and SSH access before restoring local machine state and finishing Gump authorization. Use `aion resources` for the complete provider inventory.

## Create or deploy Gump from its Kaifile

Gump owns a deploy-enabled project Kai, a reproducible `gump` build, and `machine gump`. Bootstrap its ignored project binary from the current Kai deploy worktree once and create a separate restricted SSH identity:

```sh
cd ../gump
nix run path:../kai-deploy -- -f Kaifile.bootstrap run bootstrap-kai
ssh-keygen -t ed25519 -f ~/.ssh/gump_aion -C gump-aion
```

To build Gump's DigitalOcean image, import it, create `demo`, and authorize the restricted key:

```sh
./kai workflow create-aion
```

This is billable and preserves Aion's image-import and Droplet-create confirmations. It uses `../aion/.env` through Aion's Roc credential launcher. The MVP retains one imported-image slot; delete an existing imported image explicitly before creating from a different project machine.

To build and deploy the current Gump artifact to an existing saved `demo` machine, atomically activate it through Kai, then authorize the same restricted key:

```sh
./kai workflow deploy-aion
```

Set `AION_ROOT` if Aion is not at `../aion`, and `AION_MACHINE` to select a saved machine other than `demo`. Gump remains reachable over SSH port 22 with its separate key:

```sh
ssh -i ~/.ssh/gump_aion -o IdentitiesOnly=yes aion@<machine-ip> repos
```

## Test Everpaid checkout

The localhost-only payment page creates a fixed 10-sat Everpaid Lightning invoice, polls the payment record from the Roc backend, and runs the guarded Aion create flow only after Everpaid reports `settled`. Keep the page open because its polling drives reconciliation and provisioning. This price is for integration testing and does not cover the DigitalOcean cost.

From the repository root, import an image if needed, then start the server. `payment-demo` builds its artifacts and runs a non-billable readiness preflight before listening:

```sh
./kai workflow import-image
./kai workflow payment-demo
```

Open <http://127.0.0.1:8000>. The page never receives `EVERPAID_API_KEY`; it calls the local Roc server, which uses the bearer key against `https://everpaid.app/api/v1`.

The server and CLI share non-secret `.aion/` state relative to their current directory. Before issuing an invoice, the server reads `.aion/image.json`, checks local and DigitalOcean capacity, and atomically reserves the demo's single payment slot. A missing image file causes payment preflight to reject the request without creating an invoice. The server rechecks payment ID, machine reference, amount, and settlement immediately before provisioning.

Everpaid order state and the global reservation are retained under `.aion/payments/`. Before deleting an expired order to reuse the demo, confirm its invoice did not settle. A failed or interrupted provisioning attempt intentionally requires manual inspection of `.aion/create.pending/`, DigitalOcean, and its payment markers before retrying; never clear a `provisioning` or `failed` marker blindly. A settled invoice removes the interactive create confirmation, so paying it can immediately start DigitalOcean billing.

## Cost and secret safety

- URL image import requires typing `import image`; local import requires `import local image`; create requires `create <name>`. Neither billable POST runs on other input. Image deletion requires typing `delete image <id>`. Image and Droplet deletion remove local state only when DigitalOcean returns `204`. A `404` is not confirmation because it may indicate a token for the wrong account; local state is retained.
- Each billable image-import or Droplet-create operation sends at most one POST. Aion does not send or assume an undocumented general idempotency header. Before that POST it persists and prints a unique `aion-image-*` or `aion-droplet-*` operation tag; successful resource state retains the same tag. Post-POST diagnostics are best-effort and state updates are attempted before output, so a closed output stream cannot skip reconciliation, persistence, or cleanup.
- Only a `4xx` create/import response is a definitive rejection. A transport failure, `5xx` or other unexpected response, or accepted-response decode failure is uncertain and reconciled at most six times. Images use `GET /v2/images?tag_name=<operation-tag>&private=true&per_page=200`; Droplets use `GET /v2/droplets?tag_name=<operation-tag>&per_page=200`. The POST is never repeated. Any reconciled Droplet IDs are recorded, printed best-effort, and automatically deleted; failed reconciliation or deletion retains the operation tag, known IDs, and recovery instructions in the pending directory.
- Before enrolling an SSH key or creating a Droplet, `create` queries `GET /v2/droplets?tag_name=aion&per_page=200` and refuses if any tagged Aion Droplet exists. This enforces the MVP maximum of one remote Aion VM after local state loss. `.aion/create.pending/` is also one atomic global local create guard, not a per-name guard.
- Image readiness is polled at most 60 times and Droplet activation 40 times; API requests time out after 30 seconds. If an import outlasts the polling window, `run image-status` promotes a subsequently available pending image into local image state while retaining source-object recovery details for lifecycle cleanup. SSH readiness has 30 attempts capped at 20 seconds each, and each enrollment command is capped at 30 seconds.
- Local import uploads a uniquely named `aion-imports/` object with `public-read` ACL into the otherwise private Space. An uncertain upload is retained. After the image POST, the object is deleted immediately only for a definitive `4xx` rejection; unresolved/uncertain outcomes retain it. An accepted object is deleted normally only after image availability is confirmed. `.aion/image.pending/` retains non-secret operation status, the operation tag, Space/key details, and any known image ID when recovery is needed. `image delete` falls back to a pending image ID only when `.aion/image.json` is absent; a corrupt saved image file stops deletion. Pending state remains after image deletion for source-object recovery. Inspect the recorded resources, let the lifecycle rule clean a stale object if needed, and remove the guard only after both providers are resolved.
- Any activation, SSH, key-enrollment, provisioning-state write, or machine-state save failure before create completes triggers one best-effort DELETE. If deletion is not confirmed, the error prints the Droplet ID and operation tag and retains the global guard for manual cleanup.
- Machine names are validated as 1-63-character lowercase ASCII DNS labels before create, shell, or destroy uses them. `destroy` retains local state and prints the Droplet ID and operation tag when deletion is not confirmed. Imported images and `aion-<name>` SSH keys remain after successful destroy and are reported for cleanup.
- Use only a public HTTPS image URL with no embedded credentials. The ignored `.env` uses one `KEY=value` entry per line. The Roc task launcher passes only each operation's required DigitalOcean, model, Everpaid, or Spaces credentials and removes unrelated inherited credentials, including `AWS_SESSION_TOKEN`. Values are never command arguments, logs, `.aion/` state, images, or API payloads. Agent configuration and model-key transfer use a private OS temporary directory, install mode-`0600` user files, and delete local staging best-effort.

Non-secret state lives under `.aion/`.
