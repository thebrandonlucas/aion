# Analysis and improved answers for `spec.md`

_Checked 2026-08-18. Provider prices and model terms change quickly; recheck before launch._

## Executive answer

The strongest version of this idea is **a personal cloud development computer for agents**, not another generic VPS seller and not another proprietary coding agent.

For the proof of concept:

1. Lease one provider VM per customer; do not operate your own multi-tenant VM hosts yet.
2. Launch a versioned NixOS cloud image/snapshot, not an installer ISO.
3. Install Kai and pi, then apply a user Kaifile and optional dotfiles.
4. Use PPQ as the default model gateway, while allowing a user-owned API key.
5. Offer SSH first and a small phone PWA second. Do not invent an IRC layer.
6. Use hosted card checkout first. Add Bitcoin/Lightning only after the machine lifecycle works.
7. Sell a workspace or prepaid compute time, not a “machine”; the user does not own hardware.

The opportunity is real but narrow. Codex, Devin, Replit, Coder, E2B, and Daytona already solve overlapping parts. The differentiation must be the complete low-friction workflow: persistent machine, NixOS/Kai reproducibility, model choice, terminal ownership, phone continuity, privacy-conscious accounts, and one-command deployment.

## Problems in the current framing

### The use case is incomplete

“The @levelsio use case” ends with an unfinished sentence: “His main complaint is how …”. Replace it with a measurable job:

> From a laptop or phone, start or reconnect to a persistent coding-agent session, let it continue after disconnecting, inspect its work, and publish a result without maintaining cloud infrastructure.

This separates the user problem from one person's unusual direct-production workflow.

### “Buy a machine” is misleading

Cloud instances are rented and remain under the platform/provider's administrative control. “Create a workspace” or “rent a cloud computer” is more accurate. If the service later sells dedicated hardware, that can be a separate product.

### Anonymous account is not authentication

A GUID-like account number can be an identifier or bearer credential, but it is not enough for control of a server. Losing a PPQ credit ID loses money; losing this credential may expose source, secrets, deployments, and domains.

Use:

- a random account ID that is safe to disclose;
- a passkey for web authentication;
- one or more SSH public keys for machine access;
- offline recovery codes or a recovery key;
- explicit key rotation and machine transfer.

A Mullvad-style account minimizes collected identity, but card processors still retain payment data and accounting law still applies.[16] Privacy claims must distinguish “no email required” from “anonymous.”

### `stripe-cli` is not a customer purchase interface

`stripe-cli` is a development and webhook-testing tool. For the first real flow, use Stripe-hosted Checkout and an idempotent payment webhook. A terminal command can print/open the Checkout URL and poll the order status.

### An ISO is the wrong launch artifact

An ISO is installation media. Re-running an installer for every order is slow and failure-prone. Build a versioned NixOS disk image or create a known-good provider snapshot, then launch instances from it. Inject the SSH key, machine ID, and bootstrap configuration at creation. Never bake user or PPQ secrets into the image.

Keep two configurations separate:

- **host configuration:** NixOS, SSH, firewall, updates, agent service, telemetry policy;
- **workspace configuration:** the user's Kaifile, editor/CLI tools, project dependencies, and pi configuration.

## Answers to the investigation questions

### 1. How does Levels handle it, and is the problem unsolved?

The reported current workflow is:

- a cheap Hetzner VPS as the persistent computer;
- Claude Code running on the VPS;
- Termius from laptop and iPhone;
- one tmux session per project so sessions survive disconnects;
- Tailscale for private access;
- Cloudflare Tunnel for public applications;
- password SSH disabled, inbound traffic restricted, updates/fail2ban, and backups;
- direct edits to production for solo projects, with staging recommended for teams or important systems.[1]

Treat the speed and reliability claims as self-reported. Direct production access and permission-bypass mode are personal risk decisions, not safe defaults for a hosted product.

The technical problem is already solved in pieces:

- OpenAI Codex runs parallel jobs in isolated cloud environments.[2]
- Devin provides agent VMs, persistent sessions, automation, and spend limits.[3]
- Replit combines agent, browser IDE, and deployment.[4]
- Coder provides persistent cloud workspaces, SSH, browser/desktop IDEs, dotfiles, and automatic shutdown.[5]
- E2B and Daytona provide isolated agent sandboxes and snapshots.[6][7]

What is still imperfect is the **integrated, user-owned-feeling, model-neutral, terminal-first setup**. That is a valid niche. It is not a defensible business merely because a VPS is provisioned quickly; providers already expose that API.

### 2. Should users buy a machine, use a VM, or share hosts?

For the MVP, give each customer one cloud VM. A normal VPS is already a VM. Expose only size, region, storage, and lifecycle—not virtualization terminology.

**Recommended progression:**

| Stage | Isolation unit | Why |
|---|---|---|
| Proof of concept | One existing VM for the founder/testers | Validates the remote-agent workflow |
| MVP | One provider VM per customer | Simple, strong boundary, easy API lifecycle |
| Later | One VM per workspace, potentially on owned hosts | Better utilization after demand is predictable |
| Parallel-agent product | Ephemeral VM/sandbox per task or branch | Prevents agents racing in one checkout |

Do not put unrelated customers in containers on a few self-managed machines for the MVP. That adds host patching, capacity allocation, noisy-neighbor control, network isolation, storage durability, VM escape risk, metering, and failover before product-market fit.

A persistent VM is appropriate if the promise is “my cloud computer.” If the promise becomes “run this task and return a patch,” use E2B/Daytona or ephemeral VMs instead.

### 3. Should the platform choose the agent/model? Can users bring ChatGPT?

Separate four concepts:

1. **Harness:** pi.
2. **Model gateway:** PPQ or direct provider.
3. **Model:** Codex, Claude, Gemini, etc.
4. **Credential/billing owner:** user or platform.

Recommended MVP:

- pi is the opinionated default harness;
- PPQ is the default gateway because it is prepaid, model-neutral, OpenAI-compatible, and exposes privacy tiers;[8]
- default to one tested Codex model, but expose PPQ's available models dynamically;
- allow a user-supplied PPQ or provider API key;
- deliver secrets directly to the instance where practical, redact them from logs, and never include them in snapshots.

Do not build the business around reverse-engineered consumer-subscription OAuth. Official Codex CLI can sign in with ChatGPT, but OpenAI recommends API-key authentication for programmatic workflows.[9] Other vendors may restrict consumer OAuth in third-party or always-on tools. A user can interactively sign into an official CLI over SSH, but the platform should not capture, proxy, or promise support for that token.

“Bring your own model” normally means **bring your own API credential**, not upload model weights. It can be cheaper for heavy users with a subscription, but it can also be more expensive than PPQ/API use. Show actual usage rather than promising savings.

Keep compute billing and inference billing separate at first. Letting PPQ bill the user directly avoids opaque markup, reconciliation errors, and a large shared API-key blast radius.

### 4. Do remote users lose Neovim, lazygit, and their normal tools?

No. There are three useful modes:

1. **Terminal-native:** local terminal + SSH/mosh + tmux/zellij; Neovim and lazygit run remotely.
2. **Local UI, remote execution:** VS Code Remote SSH, JetBrains Gateway, or similar; editor UI stays local while files, language servers, builds, and tests run on the VM.[10]
3. **Browser/phone:** PWA web terminal or structured agent chat.

The user should be able to provide:

- a Kaifile for reproducible packages and agent configuration;
- a dotfiles repository for shell/editor preferences;
- SSH public keys;
- optional project bootstrap commands.

Do not make one giant personalized host image. Keep the base image small and stable, cache common Kai/Nix closures, and apply user configuration after provisioning. Kaifile is the portable tool contract; dotfiles are optional presentation preferences.

For uninterrupted work, the agent process must not depend on the SSH connection. Run it in a managed session/service with a persisted event log. tmux is adequate for the proof of concept, but the PWA eventually needs structured session state: running, waiting for approval, failed, completed, and unread output.

### 5. Which provisioning service and pricing model should be used?

#### Provider choice

| Option | Fit | Advantages | Drawbacks |
|---|---|---|---|
| Hetzner Cloud | Best first test | Low cost; server, key, firewall, network, snapshot, and DNS APIs[11] | Fewer regions; hourly rounding; powered-off VMs still bill; strict abuse responsibility[12] |
| Vultr | Best fallback | Many regions; API; direct custom-ISO workflow[13] | Usually higher cost; service-provider obligations still apply |
| DigitalOcean | Easiest conventional cloud | Good API/docs; custom image import; per-second VM billing[14] | Usually higher base cost; powered-off Droplets still bill |
| E2B/Daytona | Task/sandbox product | Fast isolated environments, snapshots, pause/fork primitives | Less like a permanent NixOS computer; extra vendor/margin layer |
| Dedicated hosts + own VMs | Later optimization | Better margins at high stable utilization | Highest operational and security burden |

Start with Hetzner if a prebuilt snapshot launches reliably in the desired region. Test Vultr next because its custom ISO flow is explicit. Provider choice must also pass a written review of resale/service-provider terms, account limits, abuse handling, data location, and tax—not only a benchmark.

#### Billing model

A PPQ/Mullvad-style prepaid balance fits privacy and ad-hoc use, but compute is not priced like queries. Most VPS providers bill while a VM exists even when powered off.[12][14]

Offer two clear states:

- **Running/stopped:** full compute price because resources remain allocated.
- **Archived:** snapshot the disk and delete the VM; charge storage only, then restore to a new VM/IP later.

For the pilot, use one fixed-size monthly workspace plus separately billed model usage. Later add prepaid hourly compute with:

- low-balance alerts;
- a hard spending ceiling;
- automatic archive or deletion policy chosen in advance;
- a grace period and explicit data-retention period;
- no surprise egress bill;
- no unrestricted free trial, because disposable servers attract abuse.

Set retail price from measured cost:

> retail price = total cost / (1 - target gross-margin fraction).

Total cost includes the provider VM, IPv4, snapshot/backup, expected egress, payment fees, and a support/abuse reserve.

For example, a 50% gross margin requires charging roughly twice infrastructure cost, before tax. Do not copy the provider's `$5` headline and add a tiny markup; support and abuse response will dominate the smallest plans.

## Improved MVP

### User-visible flow

1. User runs `ai-cloud create` or visits the site.
2. Service creates an account ID and passkey; user adds an SSH public key.
3. User chooses one machine size and one region.
4. Hosted Checkout accepts a card.
5. A verified, idempotent webhook creates an order.
6. Control plane launches a VM from the current signed/versioned NixOS snapshot with a deny-by-default firewall.
7. Bootstrap installs/applies the workspace Kaifile, creates a non-root user, and reports health.
8. User receives `ssh user@host` plus a PWA session link.
9. User adds a PPQ/API credential directly to the workspace and starts pi.
10. The session continues after disconnect; the PWA shows status and reconnects to output.
11. User can snapshot/export, rebuild from configuration, or destroy the workspace.

### What to omit from the first proof

- Bitcoin, Lightning, and ecash discounts;
- multiple infrastructure providers;
- dedicated servers or a self-hosted VM pool;
- bring-your-own domains;
- automatic production deployment;
- multiple simultaneous agents;
- a full browser IDE;
- teams, collaboration, and shared credentials.

The proposed 5%/10% payment discounts are arbitrary until real processor, support, refund, volatility, and accounting costs are measured. On-chain confirmation also conflicts with instant provisioning. Add crypto as prepaid credit later; Lightning is the better fast path if demand is demonstrated. Stripe's crypto checkout currently focuses on supported stablecoins, not a universal Bitcoin/Lightning replacement.[15]

### Minimal PWA protocol

Do not use IRC. IRC appears simple only because it omits the hard product requirements: machine authorization, session ownership, replay, approvals, file/diff references, reconnect cursors, and per-user routing.

Use HTTPS plus WebSocket/SSE with a tiny session API:

- create/list/stop sessions;
- append a user message;
- stream events from a cursor;
- approve or deny a requested action;
- report machine/session health.

For the very first demo, a web terminal proxied over the private network is sufficient. Tailscale's browser SSH demonstrates that end-to-end encrypted browser SSH is practical,[17] but requiring every customer to operate a tailnet may undermine instant onboarding. Use Tailscale for administrator/private SSH only if that is simpler; use Cloudflare Tunnel only for intentionally public web traffic.

## Minimum safety baseline

“Only your public key is authorized” does not mean only the user can access the disk. The cloud provider and your control plane may have console, snapshot, or root capabilities. Document this accurately.

Before selling to strangers:

- deny inbound traffic by default; expose SSH only through a defined private or tightly controlled path;
- disable password and root SSH login;
- use a non-root agent account and explicit privilege escalation;
- separate control-plane credentials from customer machines;
- prohibit scanning, spam, mining, phishing, and malware; enforce resource/rate limits;
- limit agent spend and outbound network scope where possible;
- never place production credentials in the default image;
- provide backups and test restoration, not merely snapshot creation;
- keep code changes in Git and default deployments to staging/preview;
- provide kill, archive, rebuild, and credential-revocation controls;
- define abuse, nonpayment, deletion, and incident-response procedures.

Cloudflare Tunnel protects public ingress; it does not sandbox an agent or stop data exfiltration. Tailscale protects private connectivity; it does not replace host hardening. NixOS/Kai improves reproducibility; it does not make arbitrary agent commands safe.

## Better product statement

> Start a private, reproducible cloud workspace for coding agents in minutes. Connect from SSH or your phone, use your preferred model, keep sessions running after disconnecting, and publish experiments without configuring a VPS by hand.

The first validation question is not “can a VM launch?” It is:

> Will developers pay enough above raw VPS cost for reproducible setup, persistent agent sessions, phone continuity, model choice, and safe deployment?

## Sources

1. [Levels: conversation and linked setup posts](https://levels.io/conversation-on-startups-ai-indie-hacking)
2. [OpenAI: Introducing Codex](https://openai.com/index/introducing-codex)
3. [Devin automations and safeguards](https://docs.devin.ai/product-guides/automations)
4. [Replit Agent updates](https://docs.replit.com/updates/2025/09/12/changelog)
5. [Coder overview](https://coder.com/docs/about)
6. [E2B coding-agent sandboxes](https://e2b.dev/docs/use-cases/coding-agents)
7. [Daytona documentation](https://www.daytona.io/docs/en)
8. [PPQ API and privacy tiers](https://ppq.ai/api-docs)
9. [OpenAI Codex authentication](https://learn.chatgpt.com/docs/auth)
10. [VS Code remote development](https://code.visualstudio.com/api/advanced-topics/remote-extensions)
11. [Hetzner Cloud API](https://docs.hetzner.cloud/reference/cloud)
12. [Hetzner billing FAQ](https://docs.hetzner.com/cloud/billing/faq)
13. [Vultr custom ISO](https://docs.vultr.com/products/compute/cloud-compute/management/custom-iso)
14. [DigitalOcean Droplet pricing](https://docs.digitalocean.com/products/droplets/details/pricing)
15. [Stripe stablecoin payments](https://docs.stripe.com/payments/stablecoin-payments)
16. [Mullvad no-logging/payment data policy](https://mullvad.net/en/help/no-logging-data-policy)
17. [Tailscale browser SSH security model](https://tailscale.com/docs/features/tailscale-ssh/tailscale-ssh-console)
