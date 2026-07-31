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
      printf 'usage: save.sh [--check]\n\n'
      printf 'Pull live config -> repo (~/arch-system).\n'
      printf '  --check  dry run: show what would change, write nothing\n'
      exit 0
      ;;
    *) printf 'unknown option: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

# Read-only pass: files present in dst but missing from src.
# src = live, dst = repo for save.
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
  local src="$1" dst="$2"
  if (( check_mode )); then
    rsync -anv "${exclude_args[@]}" "$src" "$dst" 2>/dev/null |
      grep -vE '^(sending incremental file list|sent |total size )|^$' || true
  else
    mkdir -p "$(dirname -- "$dst")"
    rsync -a "${exclude_args[@]}" "$src" "$dst"
  fi
}

while read -r repo_path live_path owner; do
  [[ -n "$repo_path" ]] && [[ "$repo_path" != \#* ]] || continue

  local_path="$live_path"
  [[ "$owner" == home ]] && local_path="$HOME/$local_path"

  if [[ -d "$repo_root/$repo_path" ]]; then
    if [[ ! -d "$local_path" ]]; then
      printf 'skip  %s (no live dir)\n' "$live_path"
      continue
    fi
    printf 'sync  %s <- %s\n' "$repo_path" "$live_path"
    copy_dir "$local_path" "$repo_root/$repo_path"
    deletion_report "$local_path" "$repo_root/$repo_path" 'removed from live, left in repo'
  else
    if [[ ! -f "$local_path" ]]; then
      printf 'skip  %s (no live file)\n' "$repo_path"
      continue
    fi
    printf 'sync  %s <- %s\n' "$repo_path" "$live_path"
    copy_file "$local_path" "$repo_root/$repo_path"
  fi
done < "$links"
