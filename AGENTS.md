# arch-system — agent instructions

You are working on `arch-system`, a git-tracked Arch Linux machine-config repo.
It holds package inventories and desktop/system config that is synced with this
machine. Everything you need to work here is documented, so read first, act
after. Ask the user for anything that is not derivable from the repo.

## Read these first

- `README.md` — layout, sync workflow, aliases. It is the source of truth for
  how the repo is maintained; follow it over anything you guess.

Load it with your Read tool at the start of the session. `README.md` covers
the missing details; if something still is not clear, ask the user instead of
inferring it.

## What the repo contains

- `packages/` — package inventories: `explicit.txt` (official), `foreign.txt` (AUR).
- `desktop/` — user-facing config mirrored into `~/.config` (Hyprland, Waybar,
  GTK, Qt, fontconfig, xsettingsd, xdg-desktop-portal, nwg-look, fastfetch).
- `greetd/` — login-manager config installed to `/etc/greetd/` (root-owned).
- `etc/` — root-owned machine config installed to `/etc/...` (tracked files only).
- `scripts/` — `links` (the mapping), `excludes`, `save.sh`, `install.sh`,
  `aliases`, `bootstrap.sh`.

## Sync model

- `scripts/links` maps repo path -> live path, 3 columns:
  `<repo path> <live path> <owner>` (`home` = relative to `$HOME`,
  `root` = absolute, sudo). A directory entry is a recursive mirror; a file
  entry is a single copy. This file is the single source of truth for the mapping.
- `scripts/excludes` — rsync patterns relative to each synced root (e.g.
  Hyprland audio runtime state). Runtime state is excluded, never committed.
- `scripts/save.sh` — pull live -> repo. `--check` = dry run.
- `scripts/install.sh` — push repo -> live. `--check` = dry run.
- Both print an always-on skipped-deletion report so nothing is dropped
  silently; excludes are respected in transfers and deletions alike.
- `scripts/aliases` — defines `save`, `save-check`, `install`, `install-check`,
  `bootstrap`, and an `opencode` override that starts this repo.

## Conventions

- New tracked config must be added to `scripts/links`; never hardcode live
  paths into the scripts.
- Runtime/derived state belongs in `scripts/excludes`, not in git.
- Verify syncs with `save-check` / `install-check`; a correct sync is
  idempotent (a second run shows no changes).
- Syncs use `rsync -a`, so content and exec bits travel; there is no mode
  column in `links`.
- Don't commit unless asked.
