# Research: Everpaid-gated machine creation

## Question

How should a minimal local Aion page take an Everpaid payment before creating a machine without exposing `EVERPAID_API_KEY` in browser JavaScript?

## Findings

### Hosted payment requests

- `POST /api/v1/payment-requests` returns an Everpaid-hosted URL.
- The returned page ID is not a payment ID, and the API has no endpoint for reading payment-request settlement.
- Settlement therefore requires a public signed webhook. That is a poor fit for a local-only test page because it requires a tunnel and HMAC-SHA256 verification.

### Raw Lightning invoices

- `POST /api/v1/invoices` returns a payment ID and BOLT11 invoice. Its client `reference` is account-unique and makes retries idempotent.
- `GET /api/v1/payments/{id}` reports `pending`, `settled`, `expired`, or `failed`.
- A local Roc backend can retain the API key, create the invoice, and poll settlement. Minimal browser JavaScript only calls the local backend.
- The backend must persist the payment-to-machine mapping before provisioning. It must also lock provisioning so concurrent browser polls cannot create twice.

## Recommendation

Use a fixed, server-controlled SAT price and the raw-invoice API for this test harness. Serve one inline HTML/CSS/JS page from a Roc `basic-webserver` binary. After Everpaid reports `settled`, invoke Aion's existing guarded create path without its interactive billing prompt, and expose `pending`, `provisioning`, `active`, or `failed` to the page.

This is intentionally a single-operator demo, not an account system. A production service should use authenticated users, signed webhooks plus API reconciliation, durable transactional storage, and a background provisioning worker.

## Sources

- Everpaid OpenAPI document: https://everpaid.app/openapi.json
- Everpaid API reference: https://everpaid.app/docs
- Aion create safeguards: `src/aion.roc`

---

# Research: per-user VM infrastructure for Aion

## Question

What is the best way to give each Aion user an ad-hoc, persistent NixOS machine that runs pi/Kai unattended, accepts only the user's SSH key, supports a phone web UI and user subdomains, and can be provisioned by a Roc control plane?

Research checked 2026-08-21. Prices, limits, and provider terms change; query provider APIs and confirm commercial use before launch.

## Decision criteria

In priority order:

1. A real per-user isolation boundary and ordinary SSH/full Linux behavior.
2. A reproducible NixOS image produced from the Kaifile, with no secret in the image.
3. Persistent agent processes, projects, and Nix store across disconnects.
4. Simple HTTP APIs for create/delete, keys, firewall, DNS, image, and health state.
5. Predictable active and idle economics.
6. Low operational burden while demand is unproven.

A useful initial machine needs about 2 vCPU, 4 GiB RAM, and 40–80 GiB disk. This is a proposed benchmark profile, not yet a measured minimum.

## Findings

### Option 1: one public-cloud VM per user — best product shape

Each workspace is one provider-managed VM launched from a versioned image. The Aion control plane owns billing and lifecycle; the guest has one non-root user and the customer's SSH keys.

**Pros**

- Matches the product promise: persistent cloud computer, full NixOS/systemd, SSH, tmux, Caddy, arbitrary dev tools, and public services.
- A provider hypervisor is the tenant boundary. This is much safer and simpler than placing strangers in containers on an Aion host.
- Resource accounting, hardware failure, networking, and host patching stay with the provider.
- All shortlisted providers expose HTTP APIs that a Roc program can call without a provider SDK.

**Cons**

- The VM is normally billed for its entire lifetime, including while powered off.
- Aion remains responsible for customer abuse, compromised guests, cost overruns, support, deletion, and backups.
- Provider quotas and regional capacity can block instant creation.

#### DigitalOcean — best technical fit for the first reproducible-image spike

- NixOS has a first-class `digitalOceanImage` build variant. DigitalOcean accepts raw/qcow2 custom images, requires cloud-init-compatible images, and requires an SSH key when creating a Droplet from one.[1][2]
- Custom images can be created through the API from a URL and then used to create Droplets. This permits a direct `Kaifile -> NixOS image -> provider image` path rather than mutating a builder VM.[2]
- The API covers Droplets, images, SSH keys, firewalls, and DNS. Current custom API-token scopes can be limited by resource and action, reducing control-plane credential blast radius.[3]
- Current basic pricing lists 2 vCPU/4 GiB/80 GiB at $24/month. Powered-off Droplets still bill; destroy them to stop compute billing. Custom-image storage is $0.06/GB-month.[4]

**Assessment:** strongest match for deterministic Kai/Nix image provenance and least-surprising bootstrap. Higher compute cost than Hetzner is acceptable during a tiny pilot. The image must be temporarily hosted at a provider-readable URL for import.

#### Hetzner Cloud — best low-cost persistent VM candidate, but image bootstrap needs proof

- The API covers servers, snapshots, keys, firewalls, private networks, DNS, labels, and metadata. Servers can be cloned from snapshots.[5]
- Nixos-anywhere explicitly documents installing NixOS on Hetzner over SSH, so producing a working NixOS server is well understood.[6]
- Billing is hourly with a monthly cap, but continues until deletion even when powered off. Archival therefore means a consistent snapshot followed by deletion. Attached Volumes are not included in server snapshots.[7]
- The important caveat: Hetzner says cloud-init reconfiguration is supported for snapshots made from its official images, and snapshots of systems installed through rescue or other methods “will not be fit for reconfiguration via cloud-init.” That directly affects the current plan's `nixos-anywhere -> snapshot -> inject customer key` path.[8]
- API tokens are only project-scoped read or read/write, not endpoint-scoped. A leaked write token can modify or delete every resource in that project.[9]
- Resource limits are manually reviewed and location creation can be temporarily restricted.[10]

**Assessment:** likely lowest active cost and still a good MVP choice, but only after proving a custom first-boot metadata service that regenerates identity and installs exactly the requested key. Do not rely on Hetzner's documented cloud-init behavior for the custom NixOS snapshot.

#### Scaleway — best explicit stop/park economics

- Scaleway can import a QCOW2 image from Object Storage as a snapshot and launch Instances from it. It supports cloud-init and full instance APIs.[11]
- Compute billing stops when an Instance is powered off; storage and Flexible IP billing continue. This gives Aion a real low-cost “park” state without snapshot/delete/restore.[12]
- Current pricing lists 3 vCPU/4 GiB at about €14.74/month before storage, Flexible IPv4, and tax. A Flexible IPv4 is €0.004/hour.[13]
- IAM supports application identities and granular permission sets.[14]

**Assessment:** the most promising alternative if parking idle workspaces is central to prepaid/ad-hoc pricing. It has no NixOS provider-specific image variant in the cited NixOS image list, so a generic QCOW2/cloud-init image must be tested. The image import path also adds Object Storage and region/AZ concepts.

#### Vultr and Akamai/Linode — sound fallbacks, not first choices

- Vultr supports custom ISOs, raw snapshot imports, snapshot cloning, cloud-init, API lifecycle, and many regions. Stopped instances continue billing; snapshots cost $0.05/GB-month.[15]
- Akamai accepts raw ext3/ext4 custom images, has cloud-init metadata and a full API, and NixOS exposes a `linodeImage` variant. Powered-off services continue billing; custom images cost $0.10/GB-month.[1][16]
- Both add provider integration work without beating DigitalOcean's image fit, Hetzner's expected cost, or Scaleway's park semantics.

**Assessment:** retain as geographic/capacity fallbacks. Vultr's ISO path is installation media and should not be the normal per-order path; use an imported snapshot/image.

#### AWS EC2 — capable but excessive for the MVP

AWS can import VM disks into AMIs, launch through EC2 APIs, and provide mature IAM, networking, snapshots, and regional capacity.[17] It also brings substantially more IAM, networking, billing, quota, and image-copy surface. Lightsail does not simplify custom NixOS image import enough to justify a separate integration.

**Assessment:** consider later for enterprise/BYOC requirements, not the first provider.

### Option 2: managed microVM/sandbox platforms — good future task runners, poor primary workspace

#### Fly Machines

Fly Machines are Firecracker VMs launched from OCI images, with API create/start/stop/suspend, fast resume, proxy routing, and persistent local Volumes. Stopped/suspended Machines charge storage rather than CPU/RAM.[18]

This is attractive for bursty agents and phone-triggered sessions. It does not provide the same contract as booting Aion's complete NixOS disk: Fly converts an OCI image to a root filesystem and runs its own init. Persistent Volumes are local to a region, cost $0.15/GB-month, cannot shrink, and require explicit backup/restore design.[18][19] A dedicated IPv4 also adds cost.

**Assessment:** best managed alternative if Aion changes from “NixOS cloud computer” to “fast resumable agent runtime.” Not the MVP while full NixOS/Kai machine provenance is a goal.

#### Daytona

Daytona offers container and Linux-VM sandboxes, snapshots, pause/resume, API lifecycle, token-based SSH, authenticated preview URLs, network controls, and per-second billing. Paused VM sandboxes charge disk but not CPU/RAM.[20]

Current published rates are $0.0504/vCPU-hour plus $0.0162/GiB-hour; 2 vCPU/4 GiB always running is about $121/month before storage. Current documented per-sandbox storage tops out at 10 GiB, too small for the proposed NixOS/Nix-store profile. The docs do not establish import of a complete custom NixOS boot disk.[20][21]

**Assessment:** strong for short agent jobs and parallel branch sandboxes; not for the persistent personal machine.

#### E2B

E2B supports custom templates, secure command/file APIs, pause/resume with filesystem or memory state, network policy, and per-second billing. It charges the same published CPU/RAM rates as Daytona. Hobby sandboxes have a one-hour maximum continuous duration; Pro is $150/month plus usage and raises that to 24 hours.[22]

**Assessment:** optimized for application-controlled coding tasks, not ordinary long-lived SSH/NixOS workspaces. Use only if Aion later offers ephemeral delegated tasks.

### Option 3: dedicated hosts with one Aion VM per user — later margin optimization

Possible foundations:

- **Incus/QEMU:** full VMs, images, projects/restricted certificates, quotas, backups, REST API, OVN tenant networks, and clustering.[23]
- **Proxmox/QEMU:** VM templates, cloud-init, firewalling, RBAC, clustering, storage, and a JSON REST API.[24]
- **Firecracker:** very low overhead and fast startup, but it is a VMM building block. Production safety requires jailer/cgroups/namespaces, trusted host paths, network namespaces, storage/network rate limits, snapshot handling, and an orchestrator written and operated by Aion.[25]
- **Cloud Hypervisor:** a modern VMM with HTTP API, snapshots, device hotplug, and live migration; it is likewise not a complete multi-tenant cloud control plane.[26]

**Pros:** full control, higher density, suspend/resume opportunities, and potentially better margins at steady utilization.

**Cons:** Aion must build and operate scheduling, image distribution, IP allocation/NAT, DNS, firewalls, disk quotas, backup replication, host draining, migration, monitoring, metering, capacity, kernel/VMM patching, abuse controls, and recovery. A single host failure affects many customers. Firecracker's small VMM does not remove these systems.

**Assessment:** wrong before product-market fit. If pursued later, start with Incus or Proxmox full VMs; do not write a Firecracker orchestrator first. Benchmark economics using measured concurrent RAM/CPU/disk and include spare capacity, replication, and on-call cost.

### Option 4: bring your own cloud account — useful secondary mode

Aion could ask advanced users for a narrowly scoped provider credential and create the VM in their account.

- Pros: user pays the provider directly; lower Aion credit/abuse exposure; customer owns lifecycle and region choice.
- Cons: destroys instant Mullvad-like onboarding; credential setup and IAM differ by provider; support becomes harder; Aion still handles a powerful cloud credential.

**Assessment:** add after hosted workspaces, especially for teams or enterprises. It should not replace the simple hosted flow.

## Recommendation

### MVP architecture

1. Use **one provider VM per workspace/user**. Sell a managed workspace lease, not hardware ownership.
2. Keep **one workspace active at all times** for the first pilot. Do not build pooling, migration, or multi-provider failover.
3. Run a two-provider image/bootstrap spike before cementing `plan.md`:
   - **DigitalOcean first** for the cleanest direct NixOS image path.
   - **Hetzner second** for expected cost advantage, explicitly testing custom-snapshot first boot without assuming provider cloud-init support.
   - Test **Scaleway third** only if low-cost parking is part of the initial pricing promise.
4. Select the provider from measurements, not headline price: image build/import time, create-to-SSH time, correct key/host identity, Nix closure provenance, reboot behavior, park/restore time, DNS update time, API error quality, quota increase, and full monthly cost.
5. Start with 2 vCPU/4 GiB and 40–80 GiB, then measure pi plus representative Kai/Nix builds before defining plans.

### Lifecycle and billing model

Expose three product states:

- **Active:** VM exists and may run unattended; charge a fixed monthly price or metered compute.
- **Parked:** on Scaleway, power off and retain storage/IP; elsewhere, take an application-consistent snapshot, delete the VM, and restore later. Expect a new IP and update DNS.
- **Deleted:** remove compute, DNS, provider SSH-key records, firewalls, snapshots/backups according to the retention policy.

“Stopped” must not imply cheap on Hetzner, DigitalOcean, Vultr, or Akamai because those providers continue compute billing. Keep model inference billing separate from compute.

### Required safeguards before strangers can create machines

- Verify payment and establish an abuse-response identity before provisioning; a GUID alone is not enough for arbitrary internet-connected compute.
- Deny inbound by default, opening only SSH and HTTPS required by the product. Password/root SSH stay disabled.
- Give each guest unique host keys, machine ID, web bootstrap token, and customer SSH key. Never clone these from the image.
- Put no model, provider, customer, or TLS secret in the image, cloud-init payload, command arguments, logs, or Nix store.
- Apply per-user cost limits, creation quotas, outbound abuse controls, and kill/archive procedures. Provider terms make Aion responsible for abusive or insecure guests.[27]
- Back up user state independently of the provider's boot-disk snapshot. Hetzner explicitly excludes attached Volumes from server snapshots.[7]

## Impact on the current plan

`plan.md` currently fixes Hetzner and assumes a custom NixOS snapshot can accept the requested SSH key through cloud-init. Hetzner's documentation makes that behavior unsupported for snapshots produced through rescue/other custom installation methods.[8]

The plan should remain provisional until a live, billable spike proves one of these:

1. Aion's own first-boot unit reads Hetzner's current `/hetzner/v1/` metadata/user-data endpoints, installs the customer key, removes all builder keys, regenerates identity, and reports health; or
2. the MVP switches to a provider that directly imports the Kai-built NixOS image, with DigitalOcean the clearest documented path.

This is an infrastructure research result, not a reason to bypass the existing Kai blocker. Kai still needs a typed machine/image boundary; direct provider commands hidden in shell tasks would violate the project rules.

## Sources

1. [NixOS manual: image variants](https://nixos.org/manual/nixos/stable/release-notes)
2. [DigitalOcean custom image requirements and API upload](https://docs.digitalocean.com/products/custom-images/how-to/upload)
3. [DigitalOcean API token scopes](https://docs.digitalocean.com/reference/api/scopes)
4. [DigitalOcean Droplet pricing/billing](https://docs.digitalocean.com/products/droplets/details/pricing) and [custom-image pricing](https://docs.digitalocean.com/products/custom-images/details/pricing)
5. [Hetzner Cloud API](https://docs.hetzner.cloud/reference/cloud)
6. [nixos-anywhere Hetzner quickstart](https://nix-community.github.io/nixos-anywhere/quickstart.html)
7. [Hetzner billing FAQ](https://docs.hetzner.com/cloud/billing/faq) and [backup/snapshot FAQ](https://docs.hetzner.com/cloud/servers/backups-snapshots/faq)
8. [Hetzner server FAQ: snapshots, SSH keys, and cloud-init](https://docs.hetzner.com/cloud/servers/faq)
9. [Hetzner API token permissions](https://docs.hetzner.com/cloud/api/getting-started/generating-api-token)
10. [Hetzner resource limits and location restrictions](https://docs.hetzner.com/cloud/general/faq)
11. [Scaleway QCOW2 snapshot import](https://www.scaleway.com/en/docs/instances/how-to/snapshot-import-export-feature) and [cloud-init](https://www.scaleway.com/en/docs/instances/how-to/use-cloud-init)
12. [Scaleway instance billing](https://www.scaleway.com/en/docs/instances/faq)
13. [Scaleway instance pricing](https://www.scaleway.com/en/pricing/virtual-instances)
14. [Scaleway IAM permission sets](https://www.scaleway.com/en/docs/iam/reference-content/permission-sets)
15. [Vultr billing](https://docs.vultr.com/support/platform/billing/how-am-i-billed-for-my-servers) and [snapshot FAQ](https://docs.vultr.com/products/storage/snapshots/faq)
16. [Akamai custom-image upload](https://techdocs.akamai.com/cloud-computing/docs/upload-an-image) and [billing](https://techdocs.akamai.com/cloud-computing/docs/understanding-how-billing-works)
17. [AWS VM Import/Export](https://docs.aws.amazon.com/vm-import/latest/userguide/what-is-vmimport.html)
18. [Fly Machines API](https://fly.io/docs/machines/api/machines-resource), [suspend/resume](https://fly.io/docs/reference/suspend-resume), and [pricing](https://fly.io/docs/about/pricing)
19. [Fly Volumes](https://fly.io/docs/volumes/overview) and [Fly OCI/VM process model](https://fly.io/docs/app-guides/multiple-processes)
20. [Daytona billing](https://www.daytona.io/docs/en/billing), [snapshots](https://www.daytona.io/docs/en/snapshots), and [SSH](https://www.daytona.io/docs/en/ssh-access)
21. [Daytona sandbox limits](https://www.daytona.io/docs/en/sandboxes) and [pricing](https://www.daytona.io/pricing)
22. [E2B billing/limits](https://docs.e2b.dev/billing), [pricing calculation](https://e2b.dev/docs/faq/calculate-sandbox-price), and [pause API](https://e2b.dev/docs/api-reference/sandboxes/pause-sandbox)
23. [Incus overview](https://linuxcontainers.org/incus/docs/main) and [OVN networks](https://linuxcontainers.org/incus/docs/main/reference/network_ovn)
24. [Proxmox VE introduction/API](https://pve.proxmox.com/pve-docs/chapter-pve-intro.html) and [cloud-init VM templates](https://pve.proxmox.com/pve-docs/qm.1.html)
25. [Firecracker production host setup](https://github.com/firecracker-microvm/firecracker/blob/main/docs/prod-host-setup.md)
26. [Cloud Hypervisor introduction](https://www.cloudhypervisor.org/docs/prologue/introduction)
27. [Hetzner terms: administrator and abuse responsibility](https://www.hetzner.com/legal/terms-and-conditions)

# Research: runtime PPQ model selection

## Question

How should users choose a curated subset of PPQ models before deployment and change that selection later without rebuilding the shared NixOS image?

## Findings

The current image makes `models.json` and `settings.json` root-owned symlinks into the Nix store. That is correct for immutable defaults but wrong for per-machine runtime state. Pi expects global model configuration under `~/.pi/agent/`, reloads `models.json` whenever `/model` opens, and supports switching models without restarting. `settings.json` can set the default model and `enabledModels` cycling list.

PPQ exposes an OpenAI-compatible `GET /v1/models` catalog, but an Aion coding-agent allowlist needs more than IDs: Pi benefits from accurate reasoning, input, context-window, output-limit, cost, and compatibility metadata. A dynamic PPQ response can confirm availability, but Aion should own the tested subset and Pi metadata.

### Option 1: bake every allowed model into a writable user config

- Build one immutable catalog template into the image.
- At first boot, copy it to user-owned `~/.pi/agent/models.json` and `settings.json` instead of symlinking those paths.
- Let users switch with Pi's `/model` and Ctrl+P.

**Pros:** smallest change; one image; no server; Pi reloads the model file on `/model`.

**Cons:** every user sees the entire Aion subset; no pre-deploy personalization; changing the default externally only affects a new Pi process unless the active user switches with `/model`.

### Option 2: provision a validated selection over SSH

- Store the user's non-secret selection in local Aion state before deployment: enabled model IDs plus one default.
- Add Aion commands to list the curated catalog and update that selection.
- During `create`, send a generated configuration alongside the model key, but keep the key in its separate mode-`0600` file.
- Have `aion-init` validate and atomically write regular, `aion`-owned `models.json` and `settings.json` files.
- Reuse the same path after deployment with a command such as `aion demo models apply`.

**Pros:** matches the requested upfront workflow; one shared image; no long-running guest server; selection can change later; invalid or untested model IDs are rejected by Roc code.

**Cons:** Aion must maintain a curated catalog and model metadata; an active Pi session still uses `/model` to switch immediately after the catalog changes.

### Option 3: fetch PPQ's catalog dynamically

- Fetch `GET /v1/models` from the local CLI, an Aion control service, or the guest.
- Filter the result through an Aion allowlist before rendering Pi configuration.

**Pros:** detects additions and removals without shipping a new VM image.

**Cons:** PPQ availability becomes part of provisioning; returned metadata may not fully describe Pi compatibility; silently exposing every PPQ model violates the curated-subset requirement; catalog changes can break reproducibility.

Use this only as availability enrichment around Option 2, not as the source of policy.

### Option 4: privileged configuration service in the guest

A root service could accept authenticated model-selection updates and rewrite root-owned configuration while Pi remains unprivileged.

**Pros:** prevents the `aion` account and its agent from changing the allowed catalog directly; suitable for centrally enforced billing or policy.

**Cons:** adds a daemon, authentication protocol, privilege boundary, update mechanism, and attack surface. If the human and Pi both operate as the same `aion` Unix user, a writable user file cannot distinguish human changes from agent changes.

## Recommendation

Use Option 2 for the MVP, with a small part of Option 3 later:

1. Keep one generic image containing Pi, Kai, `aion-init`, and no user-specific model configuration or secret.
2. Maintain a versioned, tested PPQ model catalog in Roc.
3. Let the local Aion CLI save enabled IDs and a default before `create`.
4. Provision regular user-owned Pi configuration atomically over SSH, separately from the PPQ key.
5. Add a post-deploy apply command using the same validation and write path.
6. Let users switch among enabled models inside Pi with `/model`; use `enabledModels` for Ctrl+P cycling.
7. Optionally query PPQ to report whether curated models are currently available, but never let remote catalog data expand the allowlist automatically.

Do not rebuild or reimport the NixOS image for model choices. Do not put a model key in `models.json`, settings, Aion state, the Nix store, or provider metadata. Continue resolving it from `/home/aion/.config/aion/model-key`.

Before implementation, choose the initial curated model IDs and metadata. Also decide whether user/agent mutability is acceptable; if the agent must be unable to change policy, Option 4 is required.

## Sources

- Pi custom model configuration and live `/model` reload: `/home/blu/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/docs/models.md`
- Pi defaults and model cycling: `/home/blu/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/docs/settings.md`
- Pi model selection commands: `/home/blu/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/docs/usage.md`
- Pi local-process security boundary: `/home/blu/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/docs/security.md`
- [PPQ API documentation](https://ppq.ai/api-docs)
- Current Aion image configuration: `plugins/aion/AionPlugin.roc`
- Current runtime handoff: `src/aion.roc`, `src/aion-init.roc`
