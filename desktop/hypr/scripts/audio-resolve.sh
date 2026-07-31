#!/bin/bash

pw-dump | jq -r '
  .[]
  | select(.type=="PipeWire:Interface:Node")
  | {
      id,
      name: .info.props["node.name"],
      media: .info.props["media.class"]
    }
  | select(.name != null)
  | "\(.id)|\(.name)|\(.media)"
'
