Aion - remote agent and software deployment assistant

`aion` allows users to spin up an agent machine in the cloud and deploy their own tools to a subdomain on e.g. `<site>.<user>.aion.sh`

It starts out as a cli tool which can interact with the agent and execute remote commands, do research, etc.

```sh
# deferred
# aion login - logs in mullvad style with a guid secret
# aion signup - creates a registered guid secret which it asks the user to save
# aion topup - pays a bitcoin lightning invoice <mocked for now> to add credit
aion create <machine name> - creates a machine with the default Kaifile settings
aion <name> shell - creates a remote ssh shell where user can interact with the machine
aion <name> shell pi - opens a `pi` prompt over ssh so the user can interact
```

```Kaifile
machine {
    ...
}

service {
    ...
}

secrets {
    ...
}

task {
    ...
}

# etc...
```


`aion` spins up a VM with the build specified in `Kaifile` (at first we just hardcode one that has `pi`, `kai`, and a given default agent model and either scoped api key or some sort of auth which is metered by the Aion company backend)

Assume we will be using DigitalOcean NixOS. All code including deploy scripts must be written in `roc`. Only permissible to not be in roc is the standard `zig` roc bootstrapping like we do in ../kai-blueprint/
