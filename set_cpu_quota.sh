#!/bin/bash
#
# Set cpu quota for task queue to 75% of total cores,
# but round down to a whole number of cores, with a
# minimum of one core

set -eu

NUM_CORES=$(nproc)
TARGET_QUOTA=$((NUM_CORES * 75 / 100 * 100))
(( TARGET_QUOTA < 100 )) && TARGET_QUOTA=100

SERVICE=task-queue

log() {
    local msg="$*"
    logger -t "$SERVICE" -p user.info -- "$msg"
    if [ -t 1 ]; then
        echo "$msg"
    fi
}

log "Detected ${NUM_CORES} cores. Setting CPUQuota to ${TARGET_QUOTA}%."

systemctl set-property --runtime "$SERVICE" CPUQuota="${TARGET_QUOTA}%"

CURRENT_QUOTA=$(systemctl show "$SERVICE" -p CPUQuotaPerSecUSec)

log "Systemd now reports $CURRENT_QUOTA"
