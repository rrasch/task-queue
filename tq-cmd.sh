#!/bin/bash
#
# Administer task-queue service by reading commands from a file.
#
# This script is intended to run periodically via cron or a systemd timer.
# - It checks the action file (tq-action.txt) and validates its command.
# - Ensures the message queue is empty before stopping/restarting the
#   service or adding/removing workers.
# - Sends a log notice via systemd and email to the admin.
# - Executes the systemctl action corresponding to the command read from
#   the file.
#
# Requirements:
# - python3, curl, jq, mail, systemd tools
# - EMAIL_FILE must map 'rstar' to admin email
# - MQHOST must be defined in task-queue.sysconfig

set -eu

HOST=$(hostname -s)

if [[ $HOST =~ ^d ]]; then
    ENV=dev
else
    ENV=prod
fi

# temp directory
RSTAR_TMPDIR="/content/$ENV/rstar/tmp"

# execute command if this file exists
ACTION_FILE="$RSTAR_TMPDIR/tq-action.txt"

# store date/time of command here
TIMESTAMP_FILE="$RSTAR_TMPDIR/tq-action-timestamp-$HOST.txt"

# task queue config file
TQ_CONFIG_FILE="/content/$ENV/rstar/etc/task-queue.sysconfig"

# userid to email address mapping file
EMAIL_FILE="/content/$ENV/rstar/etc/email.yaml"

# name of queue on rabbitmq server
QUEUE_NAME="task_queue"

# command to run other commands as non-privileged user
RUNUSER="runuser -u nobody --"

function get_admin_email
{
    admin_email=$($RUNUSER python3 <<EOF
import yaml
print(yaml.safe_load(open('$EMAIL_FILE')).get('rstar', ''))
EOF
    )
}

function get_msg_count()
{
    msg_count=$($RUNUSER curl -s -u guest:guest \
        "http://${MQHOST}:15672/api/queues/%2f/${QUEUE_NAME}" | \
        jq -r .messages)
}

function check_perms()
{
    owner=$(stat -c "%U" "$ACTION_FILE")
    perm=$(stat -c "%a" "$ACTION_FILE")
    if ! [ "$owner" = "root" -a "$perm" -eq 644 ]; then
        echo "Error: $ACTION_FILE is not owned by root or not 644" >&2
        exit 1
    fi
}

MQHOST=""

. "$TQ_CONFIG_FILE"

get_admin_email

[ -n "$MQHOST" ] || exit
[ -n "$admin_email" ] || exit
[ -f "$ACTION_FILE" ] || exit
[ -f "$TIMESTAMP_FILE" ] && exit

check_perms

CMD=$(<"$ACTION_FILE")

case "$CMD" in
    restart|stop|add-worker|remove-worker)
        ;;
    *)
        echo "Invalid command '$CMD' found in '$ACTION_FILE', must be " \
             "{restart|stop|add-worker|remove-worker}" >&2
        exit 1
        ;;
esac

# make sure message queue is empty before executing service actions
get_msg_count
if [ "$msg_count" != "0"  ]; then
    echo "There are still $msg_count messages in the queue." >&2
    exit 1
fi

# map command to a descriptive msg that will prefix
# the log notice
declare -A log_notice_prefix=(
    ["restart"]="Restarting"
    ["stop"]="Shutting down"
    ["add-worker"]="Adding worker to"
    ["remove-worker"]="Removing worker from"
)

date "+%Y-%m-%d %H:%M:%S" > "$TIMESTAMP_FILE"
notice="${log_notice_prefix[$CMD]} task queue on $(hostname)"
echo "$notice" | systemd-cat -t task-queue
echo "$notice" | mail -s "$notice" $admin_email

case "$CMD" in
    restart|stop)
        systemctl $CMD task-queue
        ;;
    add-worker)
        systemctl kill -s SIGUSR1 task-queue
        ;;
    remove-worker)
        systemctl kill -s SIGUSR2 task-queue
        ;;
esac
