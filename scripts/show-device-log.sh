#!/bin/sh
set -eu
DEVICE_HOST="${1:-root@localhost}"
DEVICE_PORT="${2:-2222}"
ssh -p "$DEVICE_PORT" "$DEVICE_HOST" "tail -n 200 /var/mobile/Library/Logs/VPNTriggerManager.log"

