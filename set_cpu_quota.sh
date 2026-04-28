#!/bin/bash
#
# Set cpu quota for task queue to 50% of total cores

set -eu

NUM_CORES=$(nproc)
TARGET_QUOTA=$((NUM_CORES * 50))

SERVICE_NAME=task-queue.service

echo "Detected ${NUM_CORES} cores. Setting CPUQuota to ${TARGET_QUOTA}%."

systemctl set-property --runtime "$SERVICE_NAME" CPUQuota="${TARGET_QUOTA}%"

CURRENT_QUOTA=$(systemctl show "$SERVICE_NAME" -p CPUQuotaPerSecUSec)

echo "Systemd now reports $CURRENT_QUOTA"
