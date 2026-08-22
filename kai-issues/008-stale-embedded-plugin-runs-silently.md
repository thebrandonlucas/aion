# Feature: warn when plugin source is newer than the kai binary

## Limitation

The project `./kai` binary embeds the compiled plugin (built once via
`xkai build plugins/aion/MachinePlugin.roc`). Editing the plugin source and
running `./kai build <artifact>` silently re-renders backends with the *old*
embedded plugin: `.kai/roc-build/build.nix` was regenerated from stale renderer
code immediately after a plugin edit, with no warning. The only signal was a
puzzling downstream failure (`Error: DownloadFailed` for a URL the edited
renderer no longer references).

## Suggested feature

Record the plugin source hash in the built kai binary and compare it against
`plugins/**` (or the declared plugin path) on startup; warn or refuse to run
when they differ. Alternatively, document the required re-bootstrap step in
the error output when a renderer-produced artifact references something the
current plugin source no longer emits.
