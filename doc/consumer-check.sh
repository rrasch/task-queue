#!/bin/bash

set -eu

EXPECTED=${1:-18}

if ! [[ "$EXPECTED" =~ ^[0-9]+$ ]]; then
    echo "Input '$EXPECTED' is not a number" >&2
    echo "Must supply an integer for expected number of consumers." >&2
    exit 1
fi

WORKDIR=$HOME/work/task-queue

MY_CNF="/content/prod/rstar/etc/my-taskqueue.cnf"

EMAIL_CNF="/content/prod/rstar/etc/email.yaml"

MAILTO=$(awk '{print $2'} $EMAIL_CNF | sort | uniq \
    | grep -v '-' | paste -sd ',' - | sed 's/,/, /g')

MAILTO=${2:-$MAILTO}


get_num_consumers()
{
    local queue=$1
    OUTPUT=$($WORKDIR/get-connections.py --queue "$queue")
    NUM_CONSUMERS=$(echo "$OUTPUT" | grep -v -- -- | grep -v Host | wc -l)
}

add_err()
{
    local msg=$1
    [ -n "$ERR" ] && ERR="${ERR}${NL}"
    ERR="${ERR}${msg}${NL}${OUTPUT}"
}

ERR=""

NL=$'\n'$'\n'

get_num_consumers "task_queue"
if [ $NUM_CONSUMERS -ne $EXPECTED ]; then
    add_err "Expected $EXPECTED task queue workers but got $NUM_CONSUMERS."
fi

get_num_consumers "tq_log_reader"
if [ $NUM_CONSUMERS -ne 1 ]; then
    add_err "There is a problem with the task queue logger."
fi

OUTPUT=$(echo "SELECT job_id FROM job ORDER BY job_id DESC LIMIT 1" \
    | mysql --defaults-extra-file=$MY_CNF --skip-column-names --batch 2>&1 \
	| tee /dev/null)

if ! [[ "$OUTPUT" =~ ^[0-9]+$ ]]; then
    add_err "There was a problem connecting to MySQL"
fi

if [ -n "$ERR" ]; then
    cat <<EOF - | /usr/sbin/sendmail -t
To: $MAILTO
Subject: task queue problem
Content-Type: text/html

<html>
<body>
<pre>
$ERR
</pre>
</body>
</html>
EOF
fi
