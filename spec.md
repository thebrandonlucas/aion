I need to be able to spin up AI agents in the cloud ad-hoc.

The common use case the agent must serve is:

1. The @levelsio use case:
- Building things with code.
- Letting agents run without direct supervision all the time. His main complaint is how 

## MVP
A very minimal proof of concept can just be:
1. You buy a machine via `stripe-cli`, website with card, or bitcoin onchain (5% discount) or lightning/ecash (10% discount)
2. `ppq.ai` or mullvad like accounting model. start with only guid-like string.
3. only your public key is authorized to ssh into it. no passwords.
4. Spins up a NixOS with `kai` preinstalled and also a `Kaifile` with an agent configuration setup for `pi.dev` tool. It uses `ppq.ai`. We default to codex but the user may switch to any model ppq has available. I could prebuild the ISO and then just launch that ISO to the servers?
5. An extremely minimal way to talk to the agent from anywhere. Phone should probably be a PWA instead of an app so we can easily ship cross-platform. The PWA should be able to connect via the simplest secure communication protocol possible (IRC?)

 
## Later

 Levelsio advice:

 ### Infrastructure and safety

 - Tailscale for private server access.
 - Cloudflare Tunnel for public traffic.
 - All normal inbound VPS traffic blocked.
 - 3-2-1 backups, both onsite and offsite.
 - He recommends direct-production operation only for solo work; teams should use the same
   setup against staging.
 - He has experimented with bypass/auto-accept modes, but explicitly warns against
   unrestricted mode on important production systems.

- Just use pi.dev and figure out how to optimize it.
- Connect with unhuman.domains so that anyone could build from their own domains and buy on spot.
- Allow deployment of self-hosted software on domains/subdomains
- NixOS machines

novelty factor:
- Buy via the terminal like terminal.shop
- Super fast/easy onboarding
- CLI for purchases
- Easy spinning up of subdomains with their website(s) for experimentation
  (advanced feature buy your own/bring your own domain)




Questions to investigate.
- How does @levelsio handle this problem? is this something people still haven't found a great solution for (the problem of easily spinning up machines with AI agents for dev)?
- Should the user have to "buy a machine" for this or should we be able to allow VM setups?
- (should we just handle the agent selection ourselves? can we make it cheaper for the user if they "bring their own model" like chatgpt?)
- developers like using certain tools. for example i like my neovim setup on my local computer and i use lazygit. if im editing over ssh, don't i lose all my tools? what are some thoughts on this? should i define a set of tools that every remote machine with my agent needs, and then i can just use tmux/zellij or something (i.e. i could upload my kaifile and my remote machine would have my setup preinstalled?)
- Need to investigate what service to use for spinning up the agents for people and whether I should just have a few machines with VMs or spin up 1 vps per, and how pricing models work.

