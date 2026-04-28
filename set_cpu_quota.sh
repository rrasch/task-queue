#!/bin/bash
#
# Set cpu quota for task queue to 50% of total cores

set -eu

NUM_CORES=$(nproc)
TARGET_QUOTA=$((NUM_CORES * 50))

SERVICE=task-queue

log() {
    local msg="$*"
    logger -t "$SERVICE" -- "$msg"
    if [ -t 1 ]; then
        echo "$msg"
    fi
}

log "Detected ${NUM_CORES} cores. Setting CPUQuota to ${TARGET_QUOTA}%."

systemctl set-property --runtime "$SERVICE" CPUQuota="${TARGET_QUOTA}%"

CURRENT_QUOTA=$(systemctl show "$SERVICE" -p CPUQuotaPerSecUSec)

log "Systemd now reports $CURRENT_QUOTA"
