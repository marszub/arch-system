#!/bin/bash

source ~/.config/hypr/audio/devices.conf

while true; do

  BT=$(wpctl status | grep -i "$BT_NAME")
  HS=$(wpctl status | grep -i "$HEADSET_NAME")

  if [ -n "$BT" ]; then
    ~/.config/hypr/scripts/audio-profile.sh bluetooth

  elif [ -n "$HS" ]; then
    ~/.config/hypr/scripts/audio-profile.sh headset

  else
    ~/.config/hypr/scripts/audio-profile.sh speakers
  fi

  sleep 2
done
