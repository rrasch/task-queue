#!/bin/bash

set -eu

# shutdown service if this file exists
SHUTDOWN_FILE="/content/prod/rstar/tmp/tq-shutdown.txt"

# task queue config file
TQ_CONFIG_FILE="/content/prod/rstar/etc/task-queue.sysconfig"

# userid to email address mapping file
EMAIL_FILE="/content/prod/rstar/etc/email.yaml"

# name of queue on rabbitmq server
QUEUE_NAME="task_queue"

function get_admin_email
{
	admin_email=$(python3 -c \
		"import yaml;print(yaml.safe_load(open('$EMAIL_FILE'))['rstar'])")
}

function get_msg_count()
{
	msg_count=$(curl -s -u guest:guest \
		http://${MQHOST}:15672/api/queues/%2f/${QUEUE_NAME} | \
		jq -r .messages)
}

. $TQ_CONFIG_FILE

get_admin_email

[ -n "$MQHOST" ] || exit
[ -n "$admin_email" ] || exit

if [ -f $SHUTDOWN_FILE ]; then
	get_msg_count
	# make sure message queue is empty before shutting down
	if [ "$msg_count" = "0"  ]; then
		#rm -f $SHUTDOWN_FILE
		notice="Shutting down task queue on $(hostname)"
		echo "$notice" | systemd-cat -t task-queue
		echo "$notice" | mail -s "$notice" $admin_email
		/usr/local/dlib/task-queue/workersctl stop
	fi
fi

