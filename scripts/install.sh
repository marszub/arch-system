#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
links="$repo_root/scripts/links"
excludes="$repo_root/scripts/excludes"
exclude_args=()
[[ -f "$excludes" ]] && exclude_args=(--exclude-from="$excludes")

check_mode=0
for arg in "$@"; do
  case "$arg" in
    --check) check_mode=1 ;;
    -h|--help)
      printf 'usage: install.sh [--check]\n\n'
      printf 'Push repo config -> live system.\n'
      printf '  --check  dry run: show what would change, write nothing\n'
      exit 0
      ;;
    *) printf 'unknown option: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

# Read-only pass: files present in dst but missing from src.
# src = repo, dst = live for install.
deletion_report() {
  local src="$1" dst="$2" label="$3"
  rsync -anv --delete "${exclude_args[@]}" "$src/" "$dst/" 2>/dev/null |
    grep '^deleting ' | sed -e 's/^deleting //' -e "s|^|  $label: |" || true
}

copy_dir() {
  local src="$1" dst="$2"
  if (( check_mode )); then
    rsync -anv "${exclude_args[@]}" "$src/" "$dst/" 2>/dev/null |
      grep -vE '^(sending incremental file list|sent |total size |deleting )|^$' |
      grep -vE '^\./?$' || true
  else
    rsync -a "${exclude_args[@]}" "$src/" "$dst/"
  fi
}

copy_file() {
  local src="$1" dst="$2" owner="$3"
  if (( check_mode )); then
    rsync -anv "${exclude_args[@]}" "$src" "$dst" 2>/dev/null |
      grep -vE '^(sending incremental file list|sent |total size )|^$' || true
  else
    if [[ "$owner" == root ]]; then
      sudo mkdir -p "$(dirname -- "$dst")"
      # Keep root-owned targets root:root; the repo files belong to the user.
      sudo rsync -rlptD --chown=root:root "${exclude_args[@]}" "$src" "$dst"
    else
      mkdir -p "$(dirname -- "$dst")"
      rsync -a "${exclude_args[@]}" "$src" "$dst"
    fi
  fi
}

while read -r repo_path live_path owner; do
  [[ -n "$repo_path" ]] && [[ "$repo_path" != \#* ]] || continue

  local_path="$live_path"
  [[ "$owner" == home ]] && local_path="$HOME/$local_path"

  if [[ -d "$repo_root/$repo_path" ]]; then
    printf 'sync  %s -> %s\n' "$repo_path" "$live_path"
    copy_dir "$repo_root/$repo_path" "$local_path"
    deletion_report "$repo_root/$repo_path" "$local_path" 'removed from repo, left on live'
  else
    if [[ ! -f "$repo_root/$repo_path" ]]; then
      printf 'skip  %s (no repo file)\n' "$repo_path"
      continue
    fi
    printf 'sync  %s -> %s\n' "$repo_path" "$live_path"
    copy_file "$repo_root/$repo_path" "$local_path" "$owner"
  fi
done < "$links"
