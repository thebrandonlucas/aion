# Feature: tasks need scoped runtime secret inputs

## Limitation

Kai tasks can run a fixed argv inside a declared environment, but cannot load runtime values from an ignored environment file or declare which inherited variables a task may receive. An operator must otherwise source `.env` before Kai and remember to remove unrelated AWS, model, or payment credentials between operations.

Secrets cannot be stored in the `Kaifile`, generated Nix, task argv, or build output because each is inspectable or enters the Nix store. Standard Kai `secret` blocks currently target NixOS services through systemd credentials and do not supply local tasks.

## Needed capability

Allow a task to declare runtime-only secret names and an operator-side provider such as an ignored dotenv file. Kai should resolve values only during execution, pass only the declared names in the child environment, remove undeclared sensitive variables, avoid values in plans and logs, and preserve argument-safe execution.

## Aion impact

A small Roc launcher currently reads `.env` and scopes credentials for image import, image status, and the Everpaid server. Kai tasks provide runtime packages and invoke that launcher. This code can disappear when Kai owns the local runtime-secret boundary.
