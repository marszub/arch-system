#!/bin/bash

STATE=~/.config/hypr/audio/state

if [ ! -f "$STATE" ]; then
  echo "speakers" > "$STATE"
fi

CUR=$(cat "$STATE")

case "$CUR" in
  speakers) NEXT=headset ;;
  headset) NEXT=bluetooth ;;
  bluetooth) NEXT=speakers ;;
esac

echo "$NEXT" > "$STATE"

notify-send "Audio preview" "$NEXT"
