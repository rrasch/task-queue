#!/bin/bash

set -eu

SHUTDOWN_FILE="/content/prod/rstar/tmp/tq-shutdown.txt"

QUEUE_NAME="task_queue"

. /content/prod/rstar/etc/task-queue.sysconfig

msg_count=$(curl -s -u guest:guest \
	http://${MQHOST}:15672/api/queues/%2f/${QUEUE_NAME} | \
	jq -r .messages)

if [ -f $SHUTDOWN_FILE -a "$msg_count" = "0"  ]; then
	rm -f $SHUTDOWN_FILE
	notice="Shutting down task queue on $(hostname)"
	#/usr/local/dlib/task-queue/workersctl stop
fi

