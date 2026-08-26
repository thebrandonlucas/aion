# Bug: project configuration descriptors collide by block name

## Status on Kai master (`a7373bd`)

Generic workflow dispatch is implemented, and Aion no longer has the custom machine command that first exposed this bug. The underlying registry collision remains.

Planning collects project configuration descriptors from every effective command. If two commands or plugins use the same named block with different body shapes, Kai rejects the project before command reachability can disambiguate ownership:

```text
project config block 'machine' has conflicting body shapes across plugins
```

## Needed fix

Scope descriptors by owning command/plugin or by commands reachable from the requested plan. A project should be able to register a new producer with its own configuration without changing the schema seen by unrelated standard commands. Ambiguous references must fail explicitly at the point of selection.

## Aion impact

This blocks clean extension commands and encourages projects to shadow standard commands. Removing Aion's plugin avoids its local collision but does not solve the generic composition bug.
