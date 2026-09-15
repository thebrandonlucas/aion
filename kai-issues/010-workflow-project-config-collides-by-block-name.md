# Bug: project configuration descriptors collide by block name

## Status on canonical SOPS Kai (`b6b1178`)

Generic workflow dispatch is implemented, but the underlying registry collision remains. Aion reproduced it while moving DigitalOcean host policy into an Aion-local plugin.

Planning collects project configuration descriptors from every effective command. If two commands or plugins use the same named block with different body shapes, Kai rejects the project before command reachability can disambiguate ownership:

```text
project config block 'machine' has conflicting body shapes across plugins
```

## Needed fix

Scope descriptors by owning command/plugin or by commands reachable from the requested plan. A project should be able to register a new producer with its own configuration without changing the schema seen by unrelated standard commands. Ambiguous references must fail explicitly at the point of selection.

## Aion reproduction

Aion registered a custom `service <service>` block that emits a
`kai.nixos.service/v1` host-policy artifact. `xkai` compiled the plugin, then
registry validation rejected it:

```text
InvalidRegistry({ message: "named Kaifile block 'service' has conflicting body shapes across plugins", plugin: "aion-host" })
```

The custom block deliberately has a different body from the standard executable
service because DigitalOcean guest and SSH policy has no standard service
fields.

## Aion impact

This prevents a clean Aion-specific host extension from coexisting with the
standard service command. Aion could make its block copy the standard service
shape and shadow the complete standard command, but that would overload
unrelated fields and require Aion to reproduce standard service behavior. The
other workaround is checked-in or directly generated backend configuration,
which violates Aion's Kai boundary.
