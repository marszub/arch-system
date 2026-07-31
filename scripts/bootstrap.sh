#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

mapfile -t explicit_packages < <(grep -vE '^[[:space:]]*($|#)' "$repo_root/packages/explicit.txt")

if ((${#explicit_packages[@]} > 0)); then
  sudo pacman -S --needed "${explicit_packages[@]}"
fi

if [[ -s "$repo_root/packages/foreign.txt" ]]; then
  printf 'Foreign packages to install manually or with your AUR helper:\n'
  sed 's/^/- /' "$repo_root/packages/foreign.txt"
fi
