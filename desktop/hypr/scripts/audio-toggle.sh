#!/bin/bash

STATE=~/.config/hypr/audio/state
mkdir -p ~/.config/hypr/audio

[ ! -f "$STATE" ] && echo "speakers" > "$STATE"

CUR=$(cat "$STATE")

case "$CUR" in
  speakers) NEXT=headset ;;
  headset) NEXT=bluetooth ;;
  bluetooth) NEXT=speakers ;;
esac

echo "$NEXT" > "$STATE"

~/.config/hypr/scripts/audio-profile.sh "$NEXT"
