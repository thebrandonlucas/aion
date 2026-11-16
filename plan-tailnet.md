# Plan: agent machines on a tailnet

The first product: a customer gets a machine with an agent on it, reachable
only over Tailscale, where they and their agent can run and publish
services. The operator can reach every machine to help. Customers can change
their own machine. Later the machines are microVMs on our own hosts instead
of droplets.

blu-dev is the model: a NixOS guest on blu-tower, on the tailnet as
`blu-dev-1`, with Paseo listening on `127.0.0.1:6767` and published to the
tailnet only by `tailscale serve --tcp 6767` (a oneshot unit that waits for
tailscaled). lyceum-staging adds the rest of the pattern: the firewall
trusts only `tailscale0` (`allowedTCPPorts = [ ]`), and sites are Tailscale
Services, so tailscaled ends their TLS.

## The machine

A recipe, `agent`, on what kai can do today:

| Need | How, today | Typed in kai later |
|---|---|---|
| NixOS, disk, users, SSH | `Disk`, `User`, `Ssh` | done |
| Join the tailnet at first boot | `Secret("tailscale-authkey")`, read by `services.tailscale.authKeyFile` in a recipe module | a `Tailscale` service |
| Nothing public | a module: `trustedInterfaces = [ "tailscale0" ]`, no open ports, SSH on `tailscale0` | interface-scoped `Firewall` / `Ssh` |
| The agent | `Use(...)` with `paseo` and `pi-coding-agent` (both in nixpkgs), a `paseo` unit like blu-dev's in the module | a `Run`/service setting for programs |
| Agent keys (model API) | `Secret("model-api-key")`, owned by the agent's user | done |
| Publish the agent | `tailscale serve --tcp 6767`, as on blu-dev | part of `Tailscale` |
| Customer publishes services | the agent's user is tailscale's operator (`tailscale set --operator`), so it can `tailscale serve` its own ports | part of `Tailscale` |
| kai and the Kaifile on the machine | aion copies the project to `/root/project` and kai's binary after install | a `Kai` setting, after a kai release |

Secrets work in this order with no kai change: aion runs `kai secret set
agent tailscale-authkey` (encrypted to the operator) before the install, the
install makes the host key and re-encrypts the secret to it, and agenix
decrypts it on first boot, when tailscaled joins.

## Access

- **Operator:** the operator key stays in root's keys, and the operator
  reaches the machine over the tailnet. After install, `aion update` and
  `kai machine switch` target the machine's tailnet name, not its public
  IP, so public SSH can close.
- **Customer:** the machine is shared to them (see the tailnet question),
  they log in as their own user, and talk to their agent through Paseo, or
  liton later.
- **Customer edits:** the project on the machine is the source of truth: a
  git repo at `/root/project` with kai. The customer, or their agent, edits
  the Kaifile and runs `kai machine switch agent` on the machine itself.
  The operator does the same over SSH, or pulls the repo, changes it and
  switches with `--to`. aion's copy becomes the launch-time copy only.

## aion's side (provider APIs, not kai)

- A Tailscale API client beside the DigitalOcean one, with an OAuth client:
  mint a single-use, tagged auth key per launch; share or approve the node;
  delete the device on destroy.
- Launch: create droplet, set the secrets, install, wait for the node to
  appear on the tailnet, then switch to the tailnet address.
- Destroy: delete the droplet and the tailnet device, forget the host key.

## What kai is missing

For the droplet product, nothing blocks: modules cover what is not typed.
In order of how much they would help:

1. The bugs found on the first real install (#493, #494, #495), patched in
   aion's pin until they merge.
2. Trusting the host key kai made (#496); aion pins it itself for now.
3. A typed `Tailscale` service: join with a secret auth key, tags, `Serve`
   entries, operator user. It is the second typed service #463 lists.
4. A service setting for a program (`Run`), so Paseo, liton or a customer's
   app is a Kaifile line, not a module.
5. Interface-scoped firewall and SSH (`tailscale0` only).
6. kai on the machine (#463 has `kai switch <shared-url>`): installing kai
   itself and the project into a machine, which needs a kai release that
   carries the machine plugin.
7. One declaration, many installs (#498), and modules shipped outside the
   project (#497), so aion stops copying projects and profiles around.

For microVMs: a microvm.nix guest is a NixOS module today, so a host
machine can import `inputs.microvm.nixosModules.host` through `Modules` with
an `Input`, as `docs/machines.md` describes. Missing is a typed host with
`Guests([...])`, its TAP networking and volumes, and `kai machine switch`
reaching a guest through its host. #463 lists microVMs under "Afterwards"
(test machines, #288).

## Open questions for Brandon

1. **Whose tailnet?** (a) The operator's, one tag per customer, nodes
   shared to the customer's account: the operator sees everything, the
   customer needs a Tailscale account. (b) The customer's own: they hand
   aion an auth key; the operator joins as a shared node or not at all.
   Default: (a), as blu-dev and lyceum-staging are.
2. **Public SSH as a way back in?** If tailscaled never joins, a machine
   with no public port is reachable only through DigitalOcean's console.
   Default: keep key-only public SSH for the first launches, close it once
   the join is reliable.
3. **Paseo first, liton later?** Paseo is packaged and runs today; liton
   needs packaging and a daemon unit. Default: Paseo.
4. **One user or two on the machine?** Default: the customer's user runs
   the agent; root is the operator's.

## Next steps

1. `recipes/agent`: Tailscale, Paseo and Pi in a recipe module, the two
   secrets, nothing public but SSH. Check and build locally.
2. A Tailscale OAuth client (Brandon) with a tag such as
   `tag:aion-machine`; aion mints auth keys and deletes devices.
3. One real launch onto a test tailnet tag; reach Paseo from blu-dev over
   the tailnet; update; destroy.
4. kai and the project on the machine; a customer-side switch.
