#!/bin/bash

set -eu

CMD=$(basename "$0")
CMD=${CMD%.sh}

case "$CMD" in
    restart|stop)
        ;;
    *)
        echo "Invalid command '$CMD', must be {restart|stop}" >&2
        exit 1
        ;;
esac

HOST=$(hostname -s)

if [[ $HOST =~ ^d ]]; then
	ENV=dev
else
	ENV=prod
fi

# temp directory
RSTAR_TMPDIR="/content/$ENV/rstar/tmp"

# execuite command if this file exists
TRIGGER_FILE="$RSTAR_TMPDIR/tq-$CMD.txt"

# store date/time of command here
DATE_FILE="$RSTAR_TMPDIR/tq-$CMD-date-$HOST.txt"

# task queue config file
TQ_CONFIG_FILE="/content/$ENV/rstar/etc/task-queue.sysconfig"

# userid to email address mapping file
EMAIL_FILE="/content/$ENV/rstar/etc/email.yaml"

# name of queue on rabbitmq server
QUEUE_NAME="task_queue"

RUNUSER="runuser -u nobody --"

function get_admin_email
{
	admin_email=$($RUNUSER python3 -c \
		"import yaml;print(yaml.safe_load(open('$EMAIL_FILE'))['rstar'])")
}

function get_msg_count()
{
	msg_count=$($RUNUSER curl -s -u guest:guest \
		"http://${MQHOST}:15672/api/queues/%2f/${QUEUE_NAME}" | \
		jq -r .messages)
}

unset MQHOST

. $TQ_CONFIG_FILE

get_admin_email

[ -n "$MQHOST" ] || exit
[ -n "$admin_email" ] || exit

declare -A cmd_verbs=(
	["restart"]="Restarting"
	["stop"]="Shutting down"
)

if [ -f $TRIGGER_FILE -a ! -f $DATE_FILE ]; then
	get_msg_count
	# make sure message queue is empty before shutting down
	if [ "$msg_count" = "0"  ]; then
		date "+%Y-%m-%d %H:%M:%S" > $DATE_FILE
		notice="${cmd_verbs[$CMD]} task queue on $(hostname)"
		echo "$notice" | systemd-cat -t task-queue
		echo "$notice" | mail -s "$notice" $admin_email
		systemctl $CMD task-queue
	fi
fi
