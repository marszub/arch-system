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
    ;;

  speakers)
    IFS='|' read -r OUT IN < <(
      ~/.config/hypr/scripts/audio-get.sh "pci-0000_00_1f.3" "razer_kiyo"
    )
    ;;

esac

if [ -z "$OUT" ] || [ -z "$IN" ]; then
  notify-send -t 2000 "Audio" "Device missing: OUT=$OUT IN=$IN"
  exit 1
fi

wpctl set-default "$OUT"
wpctl set-default "$IN"

notify-send -t 2000 "Audio" "Switched to $PROFILE"
