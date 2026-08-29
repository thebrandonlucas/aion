# Bug: task execution loses the operator shell

## Reproduction

A task enters a Nix environment and invokes a launcher that opens an interactive shell:

```kai
task app-shell {
  environment: "cli"
  run: ["app-run", "shell"]
}
```

Although Kai was started from Zsh, `nix develop --command` replaces `SHELL` with its Bash path. The launcher cannot discover the original shell from its environment. Starting that Bash while inheriting the operator's prompt variables can print Zsh prompt escapes literally.

## Needed behavior

Kai's task execution boundary should retain the operator shell separately from the backend's build shell, for example as executor metadata or a stable `KAI_OPERATOR_SHELL` environment value. Runtime launchers should not need to inspect `/etc/passwd` or know backend-specific environment mutation.

## Aion workaround

Aion resolves the current user's login shell from `/etc/passwd`, falls back to declared Bash, and removes inherited prompt variables before starting it. This is Linux-oriented and can disappear when Kai preserves the original execution context.
