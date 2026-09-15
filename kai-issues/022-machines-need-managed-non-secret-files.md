# Feature: machines need managed non-secret files

## Limitation on Kai master (`d4a7fdd`)

Machine configuration can install packages, create basic users, and enable services. It cannot place a project file at a declared path in the machine with controlled ownership and permissions.

The homelab machine needs local Pi and Paseo JSON configuration installed in the daemon user's home. Those files can refer to the separately provisioned PPQ secret, but must not contain its value.

## Needed capability

Let a machine materialize a local project file as a regular file at a declared absolute destination. The declaration needs only:

- a workspace-relative source path;
- an absolute destination path;
- an owner from the machine's declared users; and
- a file mode, with the owner's primary group as the default.

Kai should include the source in the machine build, create missing parent directories, and produce the same file for `machine`, `image`, and `deploy`. The destination must be a writable regular file owned by the selected user rather than a symlink to the Nix store, because the application may update its configuration after installation.

Remote URL inputs, templates, recursive directory synchronization, runtime updates, and secret contents are not required for this recipe.
