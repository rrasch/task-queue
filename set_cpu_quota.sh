#!/bin/bash
#
# Set cpu quota for task queue to 75% of total cores,
# but round down to a whole number of cores, with a
# minimum of one core. Exit without setting quota
# if rstar.slice exists.

set -eu

info() {
	echo "$*" 1>&2
}

abort() {
	echo "$*" 1>&2
	exit 1
}

get_cgroup_version() {
	case "$(stat -fc %T /sys/fs/cgroup 2>/dev/null)" in
		cgroup2fs) echo "v2" ;;
		tmpfs)     echo "v1" ;;
		*)         echo "none" ;;
	esac
}

has_cpu_quota() {
	local unit=${1:-task-queue.service}
	local quota
	quota=$(systemctl show "$unit" --property=CPUQuotaPerSecUSec --value)
	if [[ -n "$quota" && "$quota" != "infinity" ]]; then
		return 0
	else
		return 1
	fi
}

set_cpu_quota() {
	local service=task-queue
	local percentage=${1:-75}

	local num_cores
	num_cores=$(nproc)

	local target_quota=$((num_cores * percentage / 100 * 100))
	(( target_quota < 100 )) && target_quota=100

	info "Detected ${num_cores} cores. Setting CPUQuota to ${target_quota}%."
	systemctl set-property --runtime "$service" CPUQuota="${target_quota}%"

	local current_quota
	current_quota=$(systemctl show "$service" -p CPUQuotaPerSecUSec)
	info "Systemd now reports $current_quota"
}

get_sysconfig_path() {
	local env
	if [[ $(hostname -s) =~ ^d ]]; then
		env=dev
	else
		env=prod
	fi
	echo "/content/${env}/rstar/etc/task-queue.sysconfig"
}


unset USE_CGROUP USE_SLICE

CONFIG_FILE=$(get_sysconfig_path)

if [ -f "$CONFIG_FILE" ]; then
	# shellcheck disable=SC1090
	. "$CONFIG_FILE"
fi

USE_CGROUP=${USE_CGROUP:-true}
USE_SLICE=${USE_SLICE:-true}

if [ "$USE_CGROUP" != "true" ]; then
	info "USE_CGROUP config var set to '$USE_CGROUP' ... not setting quota."
	exit
fi

if [ "$(get_cgroup_version)" = "none" ]; then
	abort "Please enable cgroups."
fi

info "Undoing all changes to task-queue.service unit"
systemctl revert task-queue.service

SLICE_FILE=/etc/systemd/system/rstar.slice
if [ -f "$SLICE_FILE" ] && [ "$USE_SLICE" = "true" ]; then
	if ! has_cpu_quota rstar.slice; then
		abort "Slice file $SLICE_FILE exits but quota not set."
	fi
else
	set_cpu_quota
fi
