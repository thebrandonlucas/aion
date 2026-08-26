# Feature: machine environments need build artifacts

## Limitation on Kai master (`a7373bd`)

A machine environment installs packages resolved from its determinate-system package source. Generated services can consume one `kai.build/v1` executable, but machines cannot install ordinary project build artifacts as commands or files.

This forces a project plugin to wrap helper executables as packages or misuse long-running services merely to place them in the guest.

## Needed capability

Let machines request typed build artifacts and declare where they are installed, with target-system validation and deterministic permissions. Kai should plan the artifact build automatically and let each backend package or place it without shell interpolation.

The same mechanism should support installing Kai itself from a pinned flake/package artifact rather than assuming it exists in the backend's default package collection.

## Aion impact

The agent image needs `aion-init` as an ordinary command and a pinned Kai executable. `AionPlugin.roc` currently packages and installs both.
