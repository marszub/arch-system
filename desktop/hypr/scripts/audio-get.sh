#!/bin/bash

query_out="$1"
query_in="$2"

norm() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

get_id() {
  local q
  q=$(norm "$1")
  local media="$2"

  pw-dump | jq -r --arg q "$q" --arg m "$media" '
    .[]
    | select(.type=="PipeWire:Interface:Node")
    | select(.info.props["media.class"] == $m)
    | select(
        ((.info.props["node.name"] // "") | ascii_downcase) |
        contains($q)
    )
    | .id
  ' | head -n 1
}

OUT_ID=$(get_id "$query_out" "Audio/Sink")
IN_ID=$(get_id "$query_in" "Audio/Source")

echo "$OUT_ID|$IN_ID"
