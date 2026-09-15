# Feature: machines need user-scoped runtime secret provisioning

## Limitation on Kai master (`d4a7fdd`)

Kai can declare a runtime `secret`, but only a generated Kai service can reference it. The Nix backend emits a `LoadCredential` path for that service; Kai has no command that places a value on a deployed machine, and an interactive user or externally supplied service cannot consume it.

The homelab machine needs one PPQ key available to Pi whether Pi is started from SSH or by Paseo. The value must not enter the Kaifile, generated Nix, image, store, command arguments, or logs.

## Needed capability

Let a machine bind a declared runtime secret to a file owned by a declared machine user, and add one argument-safe provisioning operation that reads the value from standard input or a local file and atomically writes that destination after deployment.

The minimum behavior is:

- the Kaifile declares only the secret name, destination, owner, and restrictive mode;
- the built machine contains an empty slot, not a value;
- provisioning sends the value through the machine's declared target without a command-line argument;
- the destination is readable by the selected user and no other unprivileged user;
- rerunning provisioning safely replaces the value;
- plans, logs, metadata, and errors never print the value.

Pi can then resolve the key from that file in its non-secret model configuration. The same user running Paseo can launch Pi without a second secret mechanism. Secret inspection, history, and a general secret-manager integration are not required for this recipe.
