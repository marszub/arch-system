#!/bin/bash

# Monitor bluetooth events
bluetoothctl monitor | while read -r line; do
    if echo "$line" | grep -q "Connected: yes"; then
        echo "Bluetooth device connected"

        # wait for PipeWire to register device
        sleep 2

        ~/.config/hypr/scripts/audio-profile.sh bluetooth
    fi

    if echo "$line" | grep -q "Connected: no"; then
        echo "Bluetooth device disconnected"

        sleep 1

        ~/.config/hypr/scripts/audio-profile.sh speakers
    fi
done
