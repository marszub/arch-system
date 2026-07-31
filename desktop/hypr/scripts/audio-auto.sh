#!/bin/bash

BT_SINK="bluez_output.DC_73_85_9B_7A_67.1"
HEADSET_SINK="alsa_output.usb-Logitech_PRO_X_000000000000-00.analog-stereo"
HEADSET_SOURCE="alsa_input.usb-Logitech_PRO_X_000000000000-00.mono-fallback"
SPEAKER_SINK="alsa_output.pci-0000_00_1f.3.analog-stereo"
MIC_WEB="alsa_input.usb-Razer_Inc_Razer_Kiyo_X_01.00.00-02.analog-stereo"

apply() {
  SINK="$1"
  SOURCE="$2"

  wpctl set-default "$SINK"
  wpctl set-default "$SOURCE"

  pw-dump | jq -r '
    .[] |
    select(.type=="PipeWire:Interface:Node") |
    select(.info.props["media.class"]=="Stream/Output/Audio") |
    .id
  ' | while read -r id; do
      wpctl move "$id" "$SINK"
  done
}

while true; do
  BT=$(wpctl status | grep -c "bluez_output.DC_73_85_9B_7A_67.1")
  HS=$(wpctl status | grep -c "alsa_output.usb-Logitech_PRO_X")

  if [ "$BT" -gt 0 ]; then
    echo "bluetooth" > ~/.config/hypr/audio/current
    apply "$BT_SINK" "$MIC_WEB"

  elif [ "$HS" -gt 0 ]; then
    echo "headset" > ~/.config/hypr/audio/current
    apply "$HEADSET_SINK" "$HEADSET_SOURCE"

  else
    echo "speakers" > ~/.config/hypr/audio/current
    apply "$SPEAKER_SINK" "$MIC_WEB"
  fi

  sleep 2
done
