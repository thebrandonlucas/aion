- no conventional commits
- very minimal fast css (inlined?) just for essentials like spinners/loading
- everything built in one language (roc). Developer tools, integration tests, etc
- Must use `kai`/`Kaifile` for all dependencies. You can run it via `nix run github:thebrandonlucas/kai/master -- <command>`. The purpose is to test and report `kai` issues as you build.
- Don't write any tests
- there is a folder `kai-issues` where you are to enumerate bugs and feature requests for kai whenever you run into bugs or limitations where this repo would be better served by that feature existing, and where there is a limitation it has that you could have done with `nix`.
- work in chunks. Hard limit of +300/-300 per commit. preference for +-50.

- Read all the agent files in ../kai-blueprint/ as well and when in doubt copy advice from there
