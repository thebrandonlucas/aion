# Feature: machines need structured NixOS option settings

## Limitation on Kai master (`d4a7fdd`)

A machine can create basic normal users and enable native services, but cannot set options on those services or on an imported NixOS module. Every named native service is rendered only as `services.<name>.enable = true`.

The homelab machine must enable Paseo under the intended user and apply its server settings. The same boundary can configure existing NixOS services such as OpenSSH without adding handwritten Nix.

## Needed capability

Let a machine assign basic values to NixOS option paths as structured Kaifile data. The minimum value types are booleans, strings, numbers, and lists of strings. For example, the design needs an equivalent of:

```text
machine server {
  options: {
    "services.paseo.enable": true
    "services.paseo.user": "dev"
  }
}
```

The exact syntax can differ. Kai should safely render the option paths and values, compose them with native and external modules, and report unknown options or invalid value types during the machine build.

Nested objects, functions, raw Nix expressions, option-schema discovery, and backend-neutral translation are not required for this recipe.
