# Research: ad-hoc cloud computers for coding agents

## Question

What product, compute, model, remote-development, and provisioning choices best fit the proof of concept in `spec.md`?

Research checked 2026-08-18. Prices and product details can change; validate them immediately before launch.

## Findings

### Product category

This is not an unsolved infrastructure problem. Cloud agents (Codex, Devin, Replit), cloud development environments (Coder), and agent sandbox platforms (E2B, Daytona) cover major pieces already. The plausible gap is a deliberately simple combination: persistent personal machine, NixOS/Kai environment, model-neutral agent, phone access, and easy deployment/domains.

- Pros: coherent workflow and a narrower audience than generic VPS hosting.
- Cons: VPS resale is low-margin; abuse, support, billing, secret handling, and recovery become the product.
- Sources: [OpenAI Codex](https://openai.com/index/introducing-codex), [Coder](https://coder.com/docs/about), [E2B](https://e2b.dev/docs/use-cases/coding-agents), [Daytona](https://www.daytona.io/docs/en)

### Option 1: one provider VM per customer — recommended for MVP

Provision a cloud VM from a versioned NixOS image and inject the customer's SSH key at first boot.

- Pros: strongest simple tenant boundary, normal SSH semantics, easy deletion, low engineering burden.
- Cons: slower startup than warm sandboxes, idle VMs remain billable, provider account limits and abuse exposure.
- Hetzner has a complete server/firewall/image API and low-cost hourly-capped VMs. Vultr has broader regions and documented custom ISO support. DigitalOcean has straightforward APIs and custom images, but typically costs more.
- Sources: [Hetzner API](https://docs.hetzner.cloud/reference/cloud), [Hetzner billing](https://docs.hetzner.com/cloud/billing/faq), [Vultr custom ISO](https://docs.vultr.com/products/compute/cloud-compute/management/custom-iso), [DigitalOcean custom images](https://docs.digitalocean.com/products/custom-images/details/pricing)

### Option 2: sandbox provider

Build on E2B or Daytona rather than reselling VPSs.

- Pros: fast startup, snapshots/pause, strong agent-oriented APIs, easier parallel agents.
- Cons: another vendor and margin layer; less control over NixOS and long-lived machine semantics.
- Sources: [E2B persistence](https://e2b.dev/docs/use-cases/coding-agents), [Daytona persistence](https://www.daytona.io/docs/en/persistence)

### Option 3: self-hosted VM pool

Rent dedicated hosts and create one microVM/VM per customer.

- Pros: potentially better utilization and margins at stable scale; control over images and suspend/resume.
- Cons: capacity planning, noisy neighbors, VM escape risk, networking, storage, backups, metering, failover, and on-call operations. It is premature for a proof of concept.

### Model access

Use PPQ as the default because it is prepaid, model-neutral, OpenAI-compatible, and can work without registration. Also allow a user-supplied API key. Do not implement unofficial reuse of consumer ChatGPT/Claude subscriptions. Official Codex CLI supports ChatGPT login, but programmatic/always-on workflows should use an API key; vendor subscription OAuth rules can change.

- Sources: [PPQ API](https://ppq.ai/api-docs), [PPQ privacy](https://ppq.ai/privacy), [Codex authentication](https://learn.chatgpt.com/docs/auth)

### Remote tools and phone access

Remote execution does not require abandoning the local editor. SSH, VS Code Remote SSH, JetBrains Gateway, and terminal tools keep the UI local while language servers/builds run remotely. A declarative Kaifile plus optional dotfiles should install remote CLI tools. For phones, a PWA can expose a reconnecting terminal or structured agent chat over HTTPS/WebSocket; IRC adds identity, authorization, history, and gateway work without solving SSH.

- Sources: [VS Code remote development](https://code.visualstudio.com/api/advanced-topics/remote-extensions), [Coder workspace lifecycle](https://coder.com/docs/user-guides/workspace-lifecycle), [Tailscale browser SSH](https://tailscale.com/docs/features/tailscale-ssh/tailscale-ssh-console)

## Recommendation

Validate demand with one persistent VM per customer on Hetzner, with Vultr as the fallback if custom-image workflow or regions are decisive. Sell a managed agent workspace, not ownership of a machine. Start with card checkout, one compute size, PPQ or BYO API key, SSH, and a minimal reconnecting web terminal/chat. Keep model usage separate from compute. Add prepaid balance limits, automatic suspension/deletion policy, snapshots/export, and an abuse response path before accepting strangers.

## Sources

Primary links are embedded above. The direct-production Levels workflow is summarized on [Levels's conversation page](https://levels.io/conversation-on-startups-ai-indie-hacking); its safety and productivity claims are self-reported, not independent evidence.
