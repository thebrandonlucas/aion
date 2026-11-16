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
- `resources` (provider inventory), later.
- SSH key validation and DigitalOcean key registration (`SshKey.roc`).
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
- Every gate, for now: the Everpaid payment page (`Everpaid*.roc`,
  `aion-web.roc`) and the typed cost confirmations. aion is an internal tool;
  `launch` creates at once.
- `aion-init.roc` and the model-key transfer. A recipe that needs a key
  declares a `Secret` and aion sets it with `kai secret set` (later slice).

v1 stays in the tree, unbuilt, until v2 replaces each command; it is deleted
in small commits after that, not in one.

## Kai

aion builds against the unmerged machine PR stack, kai#489 at `1a307ed`
(on #488 and #487; #466-#469 are merged). `tools/kai-pin/Kaifile.roc` fetches
that commit into `.kai-pin/kai` (ignored), builds its platform host and its
`kai-x64musl` with the v0.0.11 release kai (the release whose platform kai's
own Kaifile names), and leaves `.kai-pin/kai-bin/kai`. Recipes name the
checkout's platform, std and machine plugin by relative path, as kai's
`examples/` do. When the stack merges and is released, the pin moves to the
release and the paths become release URLs.

## CLI flow

```console
$ aion launch web demo --dry-run          # plans everything, creates nothing
$ aion launch web demo                    # creates at once:
    1. stage .aion/instances/demo/ from recipes/web + profiles/digitalocean
    2. kai check, kai machine build web    (fails before anything is billed)
    3. POST /v2/droplets: ubuntu-24-04-x64, the operator's DO SSH key, tags
       aion + aion-droplet-<op>; poll until active; read the public IPv4
    4. write the instance's address inputs, wait for SSH
    5. kai --yes machine install web --to root@IP     (in the instance dir)
    6. save .aion/instances/demo/instance.json
$ aion update demo                        # kai machine switch web --to root@IP
$ aion install demo                       # retry the kai install step
$ aion destroy demo                       # DELETE the droplet, then the dir
$ aion list
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

1. This plan. Done.
2. Pin kai at `1a307ed` (`tools/kai-pin/Kaifile.roc`). Done.
3. `profiles/digitalocean` and `recipes/web`; `kai check` and
   `kai --dry-run machine install` pass, and `kai machine build web` builds
   the NixOS system. Done.
4. Root `Kaifile.roc` that builds the v2 CLI with the pinned kai. Done.
5. `aion launch --dry-run`: instance staging, DO request body, kai argv. Done.
6. Live `launch`, `install`, `update`, `destroy`, `list`. Built; tested
   against the mock API (create, poll, state, destroy) and a local VM of
   the base image (boots, root SSH). The VM install and update wait on an
   SSH alias for port 2222 (`kai-issues/027`); the real-droplet run waits
   on a go.
7. Delete v1 in chunks.
8. More recipes (the Pi agent machine with a `Secret` for the model key).

## Found while building slices 1-5

- kai refuses symlinked or `..` module paths, so the profile is copied into
  each launch (`kai-issues/024`), and a launch is a whole project copy
  because kai keys facts and host keys by machine name (`025`).
- `kai machine switch --to` checks the host key against the operator's
  `known_hosts`, which a fresh droplet is never in (`023`). Slice 6 needs a
  decision: pin `secrets/hosts/<slug>.pub` into `known_hosts` after
  install, or wait for kai to do it.
- `DigitalOceanApi.roc` is on basic-cli 0.22's `Http`; the v2 CLI is on
  0.26, kai's pin, so the client is ported in slice 6.
- DigitalOcean DHCP for the installed system is inferred from v1, whose
  droplets booted with only NixOS's DHCP; the first live launch confirms it.

## Testing without a bill

```console
$ kai run mock-digitalocean 8090 &           # mock API, prints each request
$ AION_DIGITALOCEAN_URL=http://127.0.0.1:8090 DIGITALOCEAN_TOKEN=mock \
    ./aion launch web t1                     # creates a mock droplet
$ kai build ubuntu-image --out-link .aion/ubuntu-image
$ kai run vm-start                           # Ubuntu 24.04 VM, SSH on :2222
$ AION_SSH_HOST=aion-vm ... ./aion launch web t1   # install onto the VM
$ kai run vm-stop
```

`AION_SSH_HOST` sends ssh and kai to another host than the droplet's
address; it needs a `Host aion-vm` alias with `Port 2222` in
`~/.ssh/config`, because kai's `--to` takes no port.
