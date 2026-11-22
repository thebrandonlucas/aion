# Aion

A small operator tool for Kai boxes: one NixOS server per customer on Vultr,
defined by a `Kaifile.roc` in the customer's own git repository and reached
only over the customer's own tailnet. aion creates that repository from the
[kai-box](https://github.com/thebrandonlucas/kai-box) skeleton, creates and
destroys Vultr instances and runs `kai machine install` on them. Everything
else is kai in the customer's repository: `kai secret set`, `kai machine
switch`, `kai machine rollback`. See `plan-v3.md`, and `kai-issues/` for what
kai is missing.

## Operator setup

1. Nix with flakes. aion runs kai 0.0.13 with `nix run` (or `AION_KAI`), and
   `kai run build` builds `./aion`. That build is an optimized Roc build, so
   run it as `heavy kai run build`. `kai run dev -- <args>` runs aion
   unoptimized.
2. A Vultr API key in `.env` as `VULTR_API_KEY=...`. Use a Vultr sub-user
   that may only manage servers, and restrict its key to your IP addresses.
3. A recovery key, made offline with `age-keygen -o recovery.key` and kept on
   paper. Put its public recipient in `.env` as
   `AION_RECOVERY_RECIPIENT=age1...`. Every box's secrets are encrypted to it
   as well as to your SSH key, so they survive losing your laptop.
4. Your SSH key at `~/.ssh/id_ed25519` (or set `AION_OPERATOR_KEY` to the
   path of its public key file). Vultr creates each instance with it so nixos-anywhere can log
   in, and it stays root's key on the box.
5. A checkout of kai-box at `../kai-box-template` (or set `AION_TEMPLATE` to
   its `client/` directory).

## A customer

```console
$ aion customer new acme-hvac --tailnet tail1234.ts.net
$ cd ~/clients/acme-hvac                  # work through ONBOARDING.md
$ kai update
$ aion customer machine new acme-hvac box --dry-run   # builds; creates nothing
$ aion customer machine new acme-hvac box             # bills from here on
$ git add -A && git commit -m "Install the box"
$ kai machine switch box                  # after changing the Kaifile
$ aion customer machine destroy acme-hvac box
```

`machine new` builds the machine before anything is billed (kai refuses a
missing secret), checks that this laptop is on the customer's tailnet,
creates a stock Ubuntu instance with your key, waits for SSH and runs `kai
--yes machine install`. Then it waits for the box to join the tailnet as
`root@acme-hvac-box`. If the install fails, `aion customer machine install
acme-hvac box` retries it.

`aion customer machine install <slug> <machine> --to <host[:port]>` installs
on a server aion did not create. That covers moving a box into the customer's
own account, and testing on the local VM (`tools/vm`, at `127.0.0.1:2222`).

## Cost and secret safety

- Each instance create sends exactly one POST, carrying a unique `aion-op-*`
  tag that aion saves to `aion/machines/<machine>.json` before sending. A 4xx
  is a definite rejection. Any other outcome is uncertain: aion looks up the
  instance by its tag and never repeats the POST.
- aion forgets a machine only after Vultr answers its DELETE with `204`. A
  `404` may mean a key for the wrong account.
- The API key is only ever sent in the `Authorization` header. aion never
  decodes the `default_password` Vultr returns, and keeps secrets out of
  arguments, logs and `aion/` files. Customer secrets live only in the repo's
  `secrets/`, encrypted by kai.
- `aion resources` lists every aion-tagged instance, read-only, so orphans
  can be found.
