# Feature: machines need runtime configuration provisioning

## Limitation on Kai master (`a7373bd`)

Machine files are image-time NixOS configuration, while runtime slots model only secret credentials consumed by generated services. Kai cannot declare a non-secret, mutable configuration file whose value is selected at deployment and updated without rebuilding the image.

## Needed capability

Add typed runtime configuration slots alongside secrets. A slot should declare destination, owner, mode, validation/schema identity, and update semantics while keeping its value out of the image and Nix store. Kai should emit a provisioning manifest that deployment tools can apply atomically and argument-safely.

Secret and non-secret slots may share transport machinery, but plans and logs must preserve their different redaction requirements. Updates should not require replacing the machine image or restarting unrelated services.

## Aion impact

Enabled PPQ models and Pi defaults are per-user runtime configuration. They should be selected before deployment and changed later while every Aion machine continues to use one generic image.
