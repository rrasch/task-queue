#!/bin/bash

set -eu

EXPECTED=18

WORKDIR=$HOME/work/task-queue

MY_CNF="/content/prod/rstar/etc/my-taskqueue.cnf"

EMAIL_CNF="/content/prod/rstar/etc/email.yaml"

# MAILTO="$USER"
MAILTO=$(awk '{print $2'} $EMAIL_CNF | sort | uniq | grep -v '-')

OUTPUT=$($WORKDIR/get-connections.py)
 
NUM_CONSUMERS=$(echo "$OUTPUT" | grep -v -- -- | grep -v Host | wc -l)

ERR=""

NL=$'\n'$'\n'

if [ $NUM_CONSUMERS -ne $EXPECTED ]; then
	ERR="Only $NUM_CONSUMERS task queue consumers.${NL}${OUTPUT}"
fi

JOB_ID=$(echo "SELECT job_id FROM job ORDER BY job_id DESC LIMIT 1" \
	| mysql --defaults-extra-file=$MY_CNF --skip-column-names --batch)

if ! [[ "$JOB_ID" =~ ^[0-9]+$ ]]; then
	[ -n "$ERR" ] && ERR="${ERR}${NL}"
	ERR="${ERR}There was a problem connecting to MySQL"
fi

if [ -n "$ERR" ]; then
	echo "$ERR" | mail -s "task queue problem" $MAILTO
fi
