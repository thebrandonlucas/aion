# Plan: aion v2

aion's side of [kai#463](https://github.com/thebrandonlucas/kai/issues/463),
"Remote machines". The boundary:

> Anything that needs only an SSH address belongs to kai. Anything that needs
> a provider's API belongs to aion.

aion creates a server, hands kai `root@ADDRESS`, and kai installs and changes
the machine. kai never learns what DigitalOcean is; aion never writes Nix.

## What stays from v1

- The DigitalOcean HTTPS client (`DigitalOceanApi.roc`, `DigitalOcean.roc`):
  single-attempt billable POSTs, operation tags, tag-filtered reconciliation,
  `204`-only deletion.
- Local non-secret state under `.aion/`, the global create guard, and the
  `aion` tag on every resource.
- `status` and `resources`, and the cost confirmations (`create <name>`).
- SSH key validation and DigitalOcean key registration (`SshKey.roc`).
- The Everpaid payment gate (`Everpaid*.roc`, `aion-web.roc`): a settled
  invoice runs the same guarded launch, now `aion launch` instead of
  `aion create-paid`.
- The recipe catalog idea: one directory per recipe with a README title.

## What goes

- The image pipeline: `images build`, `image import`/`import-local`,
  `image status`/`reconcile`/`delete`, `.aion/image.*`.
- The Spaces bucket, its lifecycle rule and the Spaces key; `awscli2`.
- Every line of Nix aion writes: `render_digital_ocean_module`,
  `render_composition_flake`, and `plugins/aion/` (`AionPlugin.roc`,
  `AionBuildPlugin.roc`).
- aion's own closure copy and activation over SSH (`deploy`, `aion-switch`):
  `kai machine install` and `kai machine switch` do it.
- `aion-init.roc` and the model-key transfer. A recipe that needs a key
  declares a `Secret` and aion sets it with `kai secret set` (later slice).

v1 stays in the tree, unbuilt, until v2 replaces each command; it is deleted
in small commits after that, not in one.

## Kai

aion builds against the unmerged machine PR stack, kai#489 at `1a307ed`
(on #488 and #487; #466-#469 are merged). `Kaifile.bootstrap.roc` fetches
that commit into `.kai-pin/kai` (ignored), builds its platform host and its
`kai-x64musl` with the v0.0.11 release kai (the release whose platform kai's
own Kaifile names), and leaves `.kai-pin/kai-bin/bin/kai`. Recipes name the
checkout's platform, std and machine plugin by relative path, as kai's
`examples/` do. When the stack merges and is released, the pin moves to the
release and the paths become release URLs.

## CLI flow

```console
$ aion recipes list
$ aion launch web demo --dry-run          # plans everything, creates nothing
$ aion launch web demo                    # asks "create demo", then:
    1. stage .aion/instances/demo/ from recipes/web + profiles/digitalocean
    2. kai check, kai machine build web    (fails before anything is billed)
    3. POST /v2/droplets: ubuntu-24-04-x64, the operator's DO SSH key, tags
       aion + aion-droplet-<op>; poll until active; read the public IPv4
    4. write the instance's address inputs, wait for SSH
    5. kai --yes machine install web --to root@IP     (in the instance dir)
    6. save .aion/instances/demo/instance.json
$ aion update demo                        # kai machine switch web --to root@IP
$ aion destroy demo                       # DELETE the droplet; keep the dir
$ aion status | aion resources            # as v1
```

`--dry-run` stages the instance, runs `kai check` and
`kai --dry-run machine install web --to root@203.0.113.7`, and prints the
exact DigitalOcean request body and kai argv. It reads no token.

## Recipes and profiles

```text
recipes/<slug>/Kaifile.roc   one machine named <slug>; imports aion/* inputs
recipes/<slug>/README.md     first `#` heading is the title
profiles/digitalocean/digitalocean.nix
.aion/instances/<name>/      a launched copy: the recipe, its profile under
                             profiles/, aion/* inputs, and what kai writes
                             (machines/<slug>/facter.json, secrets/hosts/)
```

A recipe's Kaifile reads per-launch values as Roc string imports, so the
Kaifile stays the only machine description and aion writes plain text, not
Nix or Roc:

| File | Holds |
|---|---|
| `aion/name` | The instance name, used as `HostName`. |
| `aion/root-keys` | OpenSSH keys for root, one per line: the customer's and the operator's. |
| `aion/operators` | The operator's public key, the `Operators` for the host key and secrets. |
| `aion/domain` | `<ip-with-dashes>.sslip.io` once the address is known, `aion.invalid` before. |

The catalog ships placeholder `aion/*` files so `kai check` works in
`recipes/<slug>` itself. A profile is a NixOS module the Kaifile includes
with `Modules(["profiles/digitalocean.nix"])`; aion copies it into the
instance because kai requires module files inside the project. The DO
profile adds the QEMU guest profile and the serial console; disks come from
`Disk(SingleDisk("/dev/vda"))`, drivers from kai's nixos-facter report, and
networking from DHCP, which DigitalOcean serves for the public IPv4.

First recipe: `web`, NixOS with root SSH keys and the typed Caddy service
serving `/var/www` at the instance's sslip.io name, so a launch can be
checked over HTTPS with no DNS API.

## Decisions (defaults; Brandon to confirm)

1. **agenix**, as kai chose. aion only uses `Operators` and `kai secret set`.
2. **`install` does not write `Host` back.** aion keeps the address in
   `instance.json` and always passes `--to`; instances are short-lived and
   addresses are reused.
3. **Host keys live in the instance directory** under `.aion/instances/<name>/secrets/`,
   encrypted to the operator key. `Operators` is set on every recipe so kai
   makes the host key before boot. Later this directory can be a git repo
   per customer.
4. **Operator access stays after install**: the operator key is in
   `aion/root-keys` so `aion update` works. A customer-only machine is a
   flag for later.
5. **The customer key never goes to DigitalOcean**: the droplet is created
   with the operator's key only (nixos-anywhere needs it), and the customer
   key reaches the machine through the Kaifile.
6. **Default size `s-1vcpu-2gb`** in `nyc3`: kexec needs about 1 GB.
7. **Tests**: AGENTS.md says to write none, so checks are `kai check`,
   `--dry-run` plans and recorded DigitalOcean fixtures, not test files.

## Slices

1. This plan. ✔ when committed.
2. Pin kai at `1a307ed` (`Kaifile.bootstrap.roc`).
3. `profiles/digitalocean` and `recipes/web`; `kai check` and
   `kai --dry-run machine install` pass.
4. Root `Kaifile.roc` that builds the v2 CLI with the pinned kai.
5. `aion launch --dry-run`: instance staging, DO request body, kai argv.
6. Live `launch`, `update`, `destroy` behind the confirmations (needs go).
7. Everpaid gate calls `launch`; delete v1 in chunks.
8. More recipes (the Pi agent machine with a `Secret` for the model key).
