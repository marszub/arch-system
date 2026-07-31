# Arch System

Machine-level config and desktop/session state for this Arch Linux setup.

Scope:

- package lists
- Hyprland, Waybar, GTK, Qt, fontconfig, xsettingsd
- greetd and regreet
- `/etc` files for boot, locale, hostname, and pacman

Layout:

- `packages/` for package inventories
- `desktop/` for user-facing desktop/session config
- `greetd/` for login-manager config
- `etc/` for root-owned machine config
- `scripts/` for sync, install, and bootstrap helpers

## Sync

Bidirectional sync between this repo and the live system:

- `scripts/save.sh` — pull live config → repo.
- `scripts/install.sh` — push repo config → live system (root-owned `/etc` files need sudo).

Both read the single source of truth `scripts/links`:

- `<repo path>  <live path>  <owner>`
- `<live path>` is relative to `$HOME` for `owner=home`, absolute for `owner=root`.
- A directory entry is mirrored recursively; a file entry is a single copy.
- Exec bits travel with the files, so there is no mode column.
- Exclusions (e.g. Hyprland audio runtime state) live in `scripts/excludes`,
  with patterns relative to each synced root. They apply to transfers and to
  the skipped-deletion report alike.

Both scripts print an always-on skipped-deletion report for directory roots:
files that exist on the destination but not in the source, so nothing is ever
silently dropped. Labels tell you the direction:

- install: `removed from repo, left on live`
- save: `removed from live, left in repo`

## Aliases

Source `scripts/aliases` (or add `. ~/arch-system/scripts/aliases` to your
shell rc) for short commands, `-check` suffixes are dry runs:

- `save` / `save-check`
- `install` / `install-check`
- `bootstrap`
- `opencode` — starts opencode in this repo, so the agent instructions in
  `AGENTS.md` are loaded automatically

The aliases derive the repo location from the aliases file itself, so they
work from any clone path. `AGENTS.md` is the agent prompt for developing this
repo; it points the agent at `README.md` and tells it to ask you for anything
that is not derivable from the repo.

## Apply flow

1. Review `packages/explicit.txt` and `packages/foreign.txt`.
2. Install official packages with `scripts/bootstrap.sh` (`rsync` is a sync
   dependency and is already in the list).
3. Push the tracked config with `scripts/install.sh`.

The explicit package list includes user-space bootstrap dependencies as well,
such as `unzip` for Neovim's Mason tool installation flow.
