#!/usr/bin/env bash
# rofi power menu: Logout / Reboot / Shutdown.
# Shutdown is preselected; k/j (or arrows) move; Enter or single-click accepts;
# Escape or click-outside cancels.

entries="󰍃 Logout\n󰜉 Reboot\n󰐥 Shutdown"

choice=$(printf '%b' "$entries" | rofi -dmenu \
    -theme "$HOME/.config/rofi/power.rasi" \
    -selected-row 2 \
    -no-custom \
    -hover-select \
    -me-select-entry '' \
    -me-accept-entry MousePrimary \
    -kb-cancel 'Escape' \
    -kb-row-up 'Up,k' \
    -kb-row-down 'Down,j' \
    -p '')

case "$choice" in
    *Logout)   hyprctl dispatch 'hl.dsp.exit()' ;;
    *Reboot)   systemctl reboot ;;
    *Shutdown) systemctl -i poweroff ;;
esac
