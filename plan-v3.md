# Plan: aion v3, a customer's Kai box on Vultr

Replaces plan-v2.md and plan-tailnet.md (2026-11-20).

## The rule

aion does only what needs a provider API or the operator's laptop: create a
customer repository, create and destroy a Vultr instance, run `kai machine
install`, print checklists. The box itself is the customer's `Kaifile.roc`
and the kai-box template's modules. What runs on it is kai's machine plugin
or Liton. Updates are `kai machine switch` in the customer's repository;
aion is not involved.

## Decided

- Vultr, on the operator's account; stock Ubuntu 24.04 (`os_id` 2284) and
  `kai machine install`, no custom images. Default `vc2-4c-8gb` in `atl`.
- One git repository per customer, `~/clients/<slug>`, an ordinary kai
  project copied from kai-box's `client/` skeleton.
- The kai-box template is its own repository, `github:thebrandonlucas/kai-box`,
  locked by each customer as an `Input` whose files the box names with
  `InputModules`. `kai update kai-box` moves a customer to a new template
  version: the operator's canary box first, then the customers.
- The customer's own tailnet. The box joins with a pre-approved auth key
  tagged `tag:kai-box`, and no port is open to the internet. The operator
  reaches boxes by `tailscale switch` into each customer's tailnet, and aion
  checks that the right one is current.
- The instance is created with the operator's key, which stays root's.
  `Operators` are that key and an offline recovery age key.
- Vultr's web console is the way in if the box never joins the tailnet; it
  logs root in with the `root-password-hash` secret.
- The status collector is self-hosted Healthchecks, which boxes push to.
- Pure file deletions may exceed the commit cap.

## Customer repository

```text
Kaifile.roc              from the skeleton, verbatim
.kai/lock.json           kai-box, nixpkgs, disko, agenix
aion/name, root-keys, operators, tailnet    written by aion
aion/machines/<m>.json   {address, id, machine, operation_tag, plan, region, status}
machines/<m>/facter.json, secrets/hosts/<m>.*, secrets/<m>/*.age   kai's
boxes/box.nix            the customer's own projects and routes
ONBOARDING.md            the checklist
```

A machine `<m>` of customer `<slug>` is `<slug>-<m>`: its Vultr label and
its host name on the tailnet.

## Where each piece belongs

| Piece | Where |
|---|---|
| Vultr create/poll/destroy, SSH key, orphans | aion |
| Customer repository, checklists | aion (copies the skeleton) |
| Vultr profile, tailnet-only access, console password | kai-box `profiles/vultr.nix`, `tailnet.nix` |
| Backups and the monthly restore test, status push, Liton, microVM host | kai-box modules (next) |
| Typed Tailscale, interface-scoped SSH/firewall, `system.configurationRevision`, Caddy wildcard (DNS-01), microVM `Guests` | kai's machine plugin |
| Agents proposing Kaifile changes; staff UI; fleet view; API spend | Liton (with kai on the box) |

## Done

1. Deleted v1: custom images, Spaces, the payment page, the model-key
   transfer, the image plugin, the old Kaifile and recipes, and the docs.
2. Built on the kai 0.0.13 release instead of the patched pin
   (`kai-issues/023`–`030` resolved). aion runs kai through `nix run` at the
   release commit (`kai-issues/031`).
3. Started the kai-box template, kept locally in `/home/dev/src/kai-box-template`
   until published: `profiles/vultr.nix`, `tailnet.nix`, and `client/` with
   `Kaifile.roc`, placeholders, `boxes/box.nix` and `ONBOARDING.md`.
4. Added the Vultr client (`Vultr.roc`, `VultrApi.roc`) and customers
   (`Customer.roc`, `aion customer new/list`).
5. Added `aion customer machine new/install/destroy` and `aion resources`, and
   deleted the DigitalOcean client, profile, mock and the `web` recipe.

## Next

1. Publish kai-box (Brandon). Then `kai update` works in a customer
   repository, and the skeleton can ship a `.kai/lock.json`.
2. `kai machine build box` from the skeleton, and `machine new --dry-run`.
3. Rehearse on `tools/vm`: `aion customer machine install <slug> box --to
   127.0.0.1:2222`. The VM has no tailnet, so the final wait times out there.
4. Canary: the operator's own box on Vultr, end to end through the tailnet,
   then destroyed. This confirms DHCP, `/dev/vda` and BIOS boot on Vultr.
5. `OFFBOARDING.md` in the skeleton: install into the customer's account with
   `--to`, `restic copy` and restore, rekey to their key, hand over the repo.
6. kai-box `modules/restic.nix` (each backup reports its runs and a monthly
   restore test) and `modules/status-push.nix` (pushes `kai machine status`
   to Healthchecks every 15 minutes) are on the kai-box branch
   `modules/backup-and-status`. Once it merges, the skeleton gets a
   `services.restic.backups.box` entry whose paths include `/var/lib/kai`, and
   the `restic-env` and `restic-password` secrets. Status push waits for a kai
   release with `kai machine status` (kai#534): on 0.0.13 its unit fails. Then
   `liton.nix` and `microvm-host.nix`.

## Risks

- Vultr networking and boot are unverified until the canary runs.
- A box that never joins the tailnet is reachable only through Vultr's
  console, and the auth key is single-use, so a reinstall needs a new one.
- The Vultr API key is account-wide unless it belongs to a limited sub-user.
