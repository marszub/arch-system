#!/bin/bash
#
# bt-audio-fix.sh -- diagnose + auto-fix the Bluetooth audio sink for Super+A.
#
# DESIGN (in-repo documentation):
#
#   Super+A path: audio-toggle.sh -> audio-profile.sh bluetooth
#     -> audio-get.sh "bluez_output" "razer_kiyo".
#   "Output device not found" always means the same thing: PipeWire has no
#   Audio/Sink node whose node.name contains "bluez_output". That is a
#   *symptom*. The cause lives one layer down in BlueZ. This script maps the
#   symptom to the cause and either fixes it (connect + wait for sink) or
#   notifies exactly what the user must do by hand. No sudo is used, so every
#   check also serves as a user-runnable diagnostic command.
#
#   STATES (checked in this order; first match wins):
#
#     S0 ADAPTER_DOWN   - `bluetoothctl show` not Powered:yes, or rfkill
#                         soft/hard blocked, or bluetooth.service inactive.
#                         Action: notify to unblock/power on; no connect try.
#     S1 DEVICE_UNKNOWN - MAC for $BT_NAME not in `bluetoothctl devices`
#                         and `bluetoothctl info $MAC` fails.
#                         Action: notify to pair from scratch (scan/pair/trust).
#     S2 HEALTHY        - BlueZ Connected:yes AND pw-dump has bluez_output sink.
#                         Action: nothing, exit 0 (audio-profile.sh can proceed).
#     S3 CONNECTED_NOSINK - Connected:yes but sink missing. First recheck
#                         Paired: if Paired:no it is really a stale key in a
#                         half-connected state (observed 2026-10-14) -> S5
#                         handling. Else wait up to ~10s for the sink (PipeWire
#                         lag); if it appears -> healthy, else notify to
#                         restart PipeWire/WirePlumber or reconnect.
#     S4 DISCONNECTED_FIXABLE - Connected:no, `connect` succeeds and sink
#                         appears. Earbuds were idle/asleep but connectable.
#                         Action: fully automatic, notify "Reconnected".
#     S5 STALE_KEY      - connect fails with br-connection-key-missing or
#                         AuthenticationFailed/auth failed, or Connected:yes +
#                         Paired:no with no sink (half-connected, observed
#                         2026-10-14). The BlueZ link key is gone. `remove` is
#                         REQUIRED: BlueZ keeps the dead key per device entry
#                         and a fresh `pair` against it fails, so the script
#                         deletes the entry, then a background waiter (max
#                         ~2 min, lock at /tmp/bt-audio-fix.wait.lock, log at
#                         /tmp/bt-audio-fix.wait.log) watches for pairing-mode
#                         advertisements and runs pair/trust/connect itself.
#                         The user only puts the buds in pairing mode and
#                         presses Super+A again on success. Zero manual cmds.
#     S6 OFF_NOTWORN    - connect times out / NotAvailable / HostDown AND a
#                         short scan does NOT see the MAC. Earbuds are off, in
#                         the case, out of range, or battery dead.
#                         Action: notify to take them out, wear them, charge,
#                         hold pairing button if needed, then retry.
#     S7 HELD_BY_OTHER  - connect fails (refused/busy/timeout, but NOT a key
#                         error) AND a short scan DOES see the MAC. Earbuds are
#                         on but held by another host (e.g. phone) or need to
#                         be worn/selected. Action: notify to disconnect from
#                         the other device, wear the buds, then retry.
#
#   WHY SCAN DISTINGUISHES S6 vs S7: both look identical in `info`
#   (Connected:no) and both fail `connect`. The only user-space signal that
#   separates "not there" from "there but busy" without sudo is whether the
#   MAC advertises during a short LE/BR scan. Scan-miss -> S6, scan-hit -> S7.
#   This heuristic can misfire in a noisy RF room; the notification therefore
#   lists both checks (visible in scan? connected to phone?).
#
#   ERROR STRINGS MAPPED (bluetoothctl connect output, case-insensitive):
#     key-missing | authentication failed | auth failed -> S5
#     not ready                                            -> S0
#     no such device | unknown | invalid                   -> S1
#     refused | busy | in progress | already exists |
#       not available *with scan-hit*                      -> S7
#     timeout (exit 124) | not available | host down |
#       failed *with scan-miss*                            -> S6
#
#   USAGE:
#     bt-audio-fix.sh [--auto]   ensure sink; notify every outcome (default)
#     bt-audio-fix.sh --status   print checks only, change nothing, no notify
#   INTEGRATION: audio-profile.sh (bluetooth branch) calls
#     `bt-audio-fix.sh` when the sink is missing, retries audio-get.sh once,
#     and skips its generic "Device missing" notice when the fix script
#     already notified. Exit 0 = sink present, non-zero = cause code
#     (1 adapter, 2 unknown, 3 stale key, 4 off/not-worn, 5 held, 6 no sink).
#
#   MANUAL CHECKS (same commands the script runs):
#     bluetoothctl show | grep Powered
#     rfkill list; systemctl is-active bluetooth
#     bluetoothctl devices | grep -i "$BT_NAME"
#     bluetoothctl info <MAC> | grep -e Connected -e Paired -e Trusted
#     timeout 15 bluetoothctl connect <MAC>
#     timeout 12 bluetoothctl --timeout 10 scan on
#     pw-dump | jq -r '.[] | select(.info.props["media.class"]=="Audio/Sink")
#       | .info.props["node.name"]' | grep bluez_output
#     ~/.config/hypr/scripts/audio-get.sh bluez_output razer_kiyo

set -u

CONF=~/.config/hypr/audio/devices.conf
# shellcheck disable=SC1090
[ -f "$CONF" ] && source "$CONF"
BT_NAME="${BT_NAME:-HUAWEI FreeBuds Pro}"
BT_MAC_OVERRIDE="${BT_MAC:-}"

MODE="${1:---auto}"
NOTIFY=1
[ "$MODE" = "--status" ] && NOTIFY=0

note() { # note <title> <body>
  echo "[$1] $2"
  [ "$NOTIFY" -eq 1 ] && notify-send -t 10000 "$1" "$2"
}

resolve_mac() {
  if [ -n "$BT_MAC_OVERRIDE" ]; then echo "$BT_MAC_OVERRIDE"; return 0; fi
  bluetoothctl devices 2>/dev/null \
    | grep -i "$BT_NAME" | head -n 1 | awk '{print $2}'
}

sink_present() {
  pw-dump 2>/dev/null | grep -q "bluez_output"
}

connected_yes() { # connected_yes <mac>: exit 0 iff info says Connected: yes
  bluetoothctl info "$1" 2>/dev/null | grep -q "Connected: yes"
}

wait_sink() { # wait up to ~10s for bluez_output node
  for _ in 1 2 3 4 5; do
    sleep 2
    sink_present && return 0
  done
  return 1
}

scan_sees_mac() { # exit 0 iff a short scan advertises $1
  local mac="$1"
  timeout 15 bluetoothctl --timeout 10 scan on 2>&1 | grep -q "$mac"
}

# ---- S5 auto-repair: remove the dead entry now, then wait for pairing mode.
# Why remove? BlueZ stores the link key per device; br-connection-key-missing
# means that entry is unusable and a fresh `pair` against it fails
# (AlreadyExists/auth errors). Deleting it forces a clean bonding. The waiter
# runs in the background so Super+A returns immediately; the user only puts
# the buds in pairing mode (white flashing) and presses Super+A once more
# when the success notification arrives. Lock dir prevents stacking waiters
# when Super+A is mashed. Log: /tmp/bt-audio-fix.wait.log
WAIT_LOCK="/tmp/bt-audio-fix.wait.lock"
WAIT_LOG="/tmp/bt-audio-fix.wait.log"
WAIT_SECS=120
repair_waiter() { # repair_waiter <mac>: background re-pair loop, lock-guarded
  local mac="$1"
  (
    exec >>"$WAIT_LOG" 2>&1
    echo "=== waiter start $(date -Is) mac=$mac ==="
    bluetoothctl power on >/dev/null 2>&1 || true
    bluetoothctl pairable on >/dev/null 2>&1 || true
    local waited=0
    while [ "$waited" -lt "$WAIT_SECS" ]; do
      if timeout 25 bluetoothctl --timeout 20 scan on 2>&1 | grep -q "$mac"; then
        echo "scan hit, pairing $mac"
        bluetoothctl pair "$mac" 2>&1 | tail -n 3
        bluetoothctl trust "$mac" 2>&1 | tail -n 1
        if timeout 20 bluetoothctl connect "$mac" 2>&1 | tail -n 3; then
          :
        fi
        local i
        for i in 1 2 3 4 5; do
          sleep 2
          sink_present && break
        done
        if sink_present; then
          notify-send -t 10000 "Bluetooth" "$BT_NAME re-paired and connected. Press Super+A to switch audio."
          echo "re-pair success"
          break
        fi
        echo "pair attempt done, no sink yet; keep waiting"
      else
        echo "scan miss at waited=${waited}s"
      fi
      waited=$((waited + 25))
    done
    if ! sink_present; then
      notify-send -t 10000 "Bluetooth" "Still not paired after ~2 min. Keep $BT_NAME in pairing mode (white flashing) and press Super+A to retry."
      echo "waiter timeout"
    fi
    rmdir "$WAIT_LOCK" 2>/dev/null || true
    echo "=== waiter end ==="
  ) >/dev/null 2>&1 &
  disown || true
}
s5_stale() { # s5_stale <mac> <detail>: notify + remove + background waiter
  local mac="$1" detail="$2"
  bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
  bluetoothctl remove "$mac" >/dev/null 2>&1 || true
  if mkdir "$WAIT_LOCK" 2>/dev/null; then
    note "Bluetooth" "$detail Put $BT_NAME in pairing mode (case open, hold button till white flashes) — I removed the dead entry and am waiting for it; no commands needed. I will notify when it is back, then press Super+A."
    : >"$WAIT_LOG" 2>/dev/null || true
    repair_waiter "$mac"
  else
    note "Bluetooth" "$detail Repair already waiting for pairing mode — just put $BT_NAME in pairing mode (white flashing), no commands needed."
  fi
  exit 3
}

if [ "$MODE" = "--status" ]; then
  echo "BT_NAME=$BT_NAME"
  echo "--- adapter ---"
  bluetoothctl show 2>&1 | grep -e Powered -e Discovering || echo "(show failed)"
  rfkill list 2>&1 | grep -A1 hci || true
  systemctl is-active bluetooth 2>&1 || true
  echo "--- device ---"
  MAC=$(resolve_mac)
  echo "MAC=${MAC:-(not in bluetoothctl devices)}"
  if [ -n "${MAC:-}" ]; then bluetoothctl info "$MAC" 2>&1 | grep -e Connected -e Paired -e Trusted -e Blocked || true; fi
  echo "--- pipewire ---"
  if sink_present; then
    pw-dump 2>/dev/null | jq -r '.[] | select(.info.props["node.name"] // "" | contains("bluez_output")) | "\(.id) | \(.info.props["node.name"])"'
  else
    echo "(no bluez_output sink)"
  fi
  echo "--- audio-get ---"
  ~/.config/hypr/scripts/audio-get.sh "bluez_output" "razer_kiyo" 2>&1 || true
  exit 0
fi

# ---- S0: adapter ----
if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
  note "Bluetooth" "Adapter off or blocked. Steps: 1) rfkill unblock bluetooth 2) bluetoothctl power on 3) Super+A again. Check: bluetoothctl show | grep Powered; rfkill list"
  exit 1
fi

# ---- S1: device unknown ----
MAC=$(resolve_mac)
if [ -z "${MAC:-}" ]; then
  if ! bluetoothctl info "${BT_MAC_OVERRIDE:-XX:XX}" 2>&1 | grep -q "Device"; then
    note "Bluetooth" "No paired device named '$BT_NAME'. Steps: put buds in pairing mode (case open, hold button till white flashes), then: bluetoothctl scan on; pair <MAC>; trust <MAC>; connect <MAC>. Then Super+A."
    exit 2
  fi
  MAC="$BT_MAC_OVERRIDE"
fi
if ! bluetoothctl info "$MAC" 2>&1 | grep -q "Device $MAC"; then
  note "Bluetooth" "Device $MAC unknown. Re-pair it: pairing mode on, bluetoothctl scan on, pair/trust/connect, then Super+A."
  exit 2
fi

# ---- S2: healthy ----
if connected_yes "$MAC" && sink_present; then
  exit 0
fi

# ---- S3: connected but no sink ----
# NOTE (observed 2026-10-14): a stale key can leave a half-connected state:
# info shows Connected:yes + Paired:no with no PipeWire sink. Bonded:no alone
# is NORMAL for FreeBuds Pro; Paired:no is the stale signal. Catch it here so
# we advise re-pair instead of a generic PipeWire restart.
if connected_yes "$MAC" && ! sink_present; then
  if bluetoothctl info "$MAC" 2>/dev/null | grep -q "Paired: no"; then
    s5_stale "$MAC" "Stale pairing key ($BT_NAME connected without audio, pairing lost)."
  fi
  if wait_sink; then exit 0; fi
  note "Bluetooth" "Earbuds connected but no PipeWire sink appeared. Steps: 1) wait 10s, retry Super+A 2) bluetoothctl disconnect $MAC; connect $MAC 3) systemctl --user restart pipewire wireplumber. Check: pw-dump | grep bluez_output"
  exit 6
fi

# ---- S4..S7: disconnected -> try one connect, capture output ----
CONN_OUT=$(timeout 20 bluetoothctl connect "$MAC" 2>&1)
CONN_RC=$?
echo "$CONN_OUT"
LOW=$(echo "$CONN_OUT" | tr '[:upper:]' '[:lower:]')

if echo "$LOW" | grep -q "connection successful"; then
  if wait_sink; then
    note "Bluetooth" "Reconnected $BT_NAME. Super+A again to switch audio."
    exit 0
  fi
  note "Bluetooth" "Connected but PipeWire sink still missing. Wait 10s and retry Super+A; if stuck: disconnect/connect once more, then restart pipewire+wireplumber."
  exit 6
fi

# key errors must be matched before generic scan logic
if echo "$LOW" | grep -qE "key-missing|authentication failed|auth failed"; then
  s5_stale "$MAC" "Stale pairing key for $BT_NAME."
fi
if echo "$LOW" | grep -qE "not ready"; then
  note "Bluetooth" "Adapter not ready. Run: rfkill unblock bluetooth; bluetoothctl power on; then Super+A."
  exit 1
fi
if echo "$LOW" | grep -qE "no such device|unknown|invalid"; then
  note "Bluetooth" "Device entry gone. Re-pair: pairing mode on, bluetoothctl scan on, pair/trust/connect $BT_NAME, then Super+A."
  exit 2
fi

# Remaining failures: distinguish off/not-worn (S6) from held-by-other (S7)
if scan_sees_mac "$MAC"; then
  note "Bluetooth" "$BT_NAME is visible but busy - likely connected to another device (phone) or not worn. Steps: 1) disconnect it from the phone / turn phone BT off 2) wear both buds 3) run: timeout 15 bluetoothctl connect $MAC 4) Super+A."
  exit 5
else
  if [ "$CONN_RC" -eq 124 ]; then DETAIL="connect timed out"; else DETAIL="not reachable"; fi
  note "Bluetooth" "$BT_NAME $DETAIL and not advertising - earbuds off, in case, or battery dead. Steps: 1) take them out, wear them 2) if no light, charge 3) hold case button till white flashes 4) connect $MAC, then Super+A."
  exit 4
fi
