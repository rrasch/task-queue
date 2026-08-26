#!/bin/bash
#
# Set cpu quota for task queue to 75% of total cores,
# but round down to a whole number of cores, with a
# minimum of one core. Exit without setting quota
# if rstar.slice exists.

set -eu

SLICE=rstar.slice

if systemctl list-units --all --type=slice --plain --no-legend "$SLICE" |
    grep -q .; then
    echo "Slice $SLICE exists."
    exit
fi

NUM_CORES=$(nproc)
TARGET_QUOTA=$((NUM_CORES * 75 / 100 * 100))
(( TARGET_QUOTA < 100 )) && TARGET_QUOTA=100

SERVICE=task-queue

echo "Detected ${NUM_CORES} cores. Setting CPUQuota to ${TARGET_QUOTA}%."

systemctl set-property --runtime "$SERVICE" CPUQuota="${TARGET_QUOTA}%"

CURRENT_QUOTA=$(systemctl show "$SERVICE" -p CPUQuotaPerSecUSec)

echo "Systemd now reports $CURRENT_QUOTA"
