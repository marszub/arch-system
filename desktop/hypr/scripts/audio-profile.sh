#!/bin/bash

PROFILE="$1"

case "$PROFILE" in

  headset)
    IFS='|' read -r OUT IN < <(
      ~/.config/hypr/scripts/audio-get.sh "usb-logitech" "usb-logitech"
    )
    ;;

  bluetooth)
    IFS='|' read -r OUT IN < <(
      ~/.config/hypr/scripts/audio-get.sh "bluez_output" "razer_kiyo"
    )
    # Auto-heal: missing BT sink is usually a BlueZ state (idle/stale/off),
    # not a script bug. bt-audio-fix.sh diagnoses, reconnects when it can,
    # and notifies the exact manual steps otherwise; then we retry once.
    if [ -z "$OUT" ]; then
      ~/.config/hypr/scripts/bt-audio-fix.sh
      IFS='|' read -r OUT IN < <(
        ~/.config/hypr/scripts/audio-get.sh "bluez_output" "razer_kiyo"
      )
      BT_FIX_RAN=1
    fi
    ;;

  speakers)
    IFS='|' read -r OUT IN < <(
      ~/.config/hypr/scripts/audio-get.sh "pci-0000_00_1f.3" "razer_kiyo"
    )
    ;;

esac

if [ -z "$OUT" ] || [ -z "$IN" ]; then
  # bt-audio-fix.sh already notified the specific cause; don't double-notify.
  [ "${BT_FIX_RAN:-0}" = "1" ] || notify-send -t 2000 "Audio" "Device missing: OUT=$OUT IN=$IN"
  exit 1
fi

wpctl set-default "$OUT"
wpctl set-default "$IN"

notify-send -t 2000 "Audio" "Switched to $PROFILE"
